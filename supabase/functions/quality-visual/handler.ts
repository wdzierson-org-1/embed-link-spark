import { authorized } from '../quality-worker/handler.ts';
import { livePublicUrl } from '../quality-worker/liveEvidence.ts';
import { isPublicPreviewUrl } from '../_shared/previewUrl.ts';
import { captureCanary, cleanupCanary, type CanaryAuth } from './canary.ts';
import { resolveVisualSurfaces } from './display.ts';
import { inspectVisuals, type VisualInspection, type VisualReference } from './inspection.ts';

type Env = (name: string) => string | undefined;
type DB = {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: any; error: unknown }>;
  from(table: string): any;
  storage: { from(bucket: string): any };
};
type Job = {
  id: string; kind: 'canary' | 'sample'; owner_id: string; item_id: string | null; checked_url: string;
  fixture_id?: string | null; fixture_version?: number | null;
  fixture?: { id: string; url: string } | null; reference?: VisualReference | null;
  lease_token: string; fence: number; created_at: string; attempts: number;
};
type Dependencies = {
  db: DB; auth: CanaryAuth; env: Env; fetcher?: typeof fetch;
  inspect?: typeof inspectVisuals; capture?: typeof captureCanary; now?: () => number;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ITEM_COLUMNS = 'id,user_id,type,url,title,page_body,file_path,attributes,is_public,created_at';
const MAX_SETTLEMENT_MS = 20 * 60_000;
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
});
async function bounded<T>(operation: PromiseLike<T>, ms = 8_000): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([operation, new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error('operation_timeout')), ms);
    })]);
  } finally { if (timer !== undefined) clearTimeout(timer); }
}

function validJob(value: any): value is Job {
  return value && UUID.test(value.id) && UUID.test(value.owner_id) && UUID.test(value.lease_token) &&
    typeof value.checked_url === 'string' && livePublicUrl(value.checked_url) && isPublicPreviewUrl(value.checked_url) &&
    !value.checked_url.includes('#') && !/[?&][^=&]*%[^=&]*=/.test(value.checked_url) &&
    ['canary', 'sample'].includes(value.kind) && Number.isSafeInteger(value.fence) && value.fence > 0 &&
    (!value.item_id || UUID.test(value.item_id)) && Number.isFinite(Date.parse(value.created_at));
}

/** Cron-only coordinator. Input JSON is intentionally ignored: jobs, owners,
 * references and URLs all come from the service-only durable queue. A wake
 * handles one job; live captures settle across later scheduled wakes. */
export function createVisualHandler({ db, auth, env, fetcher = fetch, inspect = inspectVisuals,
  capture = captureCanary, now = Date.now }: Dependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json(405, { error: 'post_only' });
    if (!await authorized(req.headers.get('x-cron-secret'), env('CRON_SECRET'))) return json(401, { error: 'unauthorized' });
    const call = async (name: string, args: Record<string, unknown> = {}) => {
      const result = await bounded(db.rpc(name, args), 5_000);
      if (result.error) throw new Error('database_error');
      return result.data;
    };

    // Turning off paid checks must not turn off retention or registered cleanup.
    try { await call('prune_hosted_visual_data'); }
    catch { return json(503, { error: 'visual_retention_failed' }); }
    const monitorOwner = env('QUALITY_CANARY_USER_ID') || '';
    let cleaned = 0;
    let cleanupPending = 0;
    if (UUID.test(monitorOwner)) {
      try {
        const rows = await call('list_hosted_visual_cleanup');
        if (!Array.isArray(rows)) throw new Error('invalid_cleanup_rows');
        // Different registered jobs can clean up independently. The SQL delete
        // is idempotent and retains a media tombstone for interrupted cleanup.
        await Promise.all(rows.slice(0, 3).map(async row => {
          if (!UUID.test(row.job_id) || row.owner_id !== monitorOwner) { cleanupPending++; return; }
          const result = await cleanupCanary({ jobId: row.job_id, expectedUserId: monitorOwner }, {
            registeredItem: async () => ({ item_id: row.item_id, user_id: row.owner_id,
              is_public: row.is_public, settled: row.settled, file_path: row.file_path }),
            deleteItem: async ({ jobId, expectedFilePath }) =>
              await call('purge_hosted_visual_canary', { job_id: jobId, expected_file_path: expectedFilePath }) === true,
            isPreviewReferenced: async path => await call('hosted_visual_preview_referenced', { preview_path: path }) !== false,
            removePreview: async path => {
              const result = await bounded(db.storage.from('stash-media').remove([path]));
              if ((result as any).error) return false;
              return true;
            },
          });
          const ownedPreview = typeof row.file_path === 'string' &&
            new RegExp(`^${monitorOwner}/previews/preview_[0-9]+\\.(?:jpe?g|png|webp|gif|avif|heic)$`).test(row.file_path);
          // A referenced owned asset stays pending. Missing/remote/non-preview
          // paths were never eligible for removal and need no storage operation.
          if (result.deleted && (result.preview === 'removed' || !ownedPreview)) {
            if (await call('finish_hosted_visual_cleanup', { job_id: row.job_id, expected_file_path: row.file_path }) === true) cleaned++;
            else cleanupPending++;
          } else cleanupPending++;
        }));
      } catch { cleanupPending++; }
    }
    const cleanup = { cleaned, pending: cleanupPending };
    if (env('QUALITY_VISUAL_ENABLED') !== 'true') return json(200, { status: 'disabled', cleanup });

    const scope = [...new Set((env('QUALITY_REPORT_SCOPE_USER_IDS') ?? env('QUALITY_SCOPE_USER_IDS') ?? '')
      .split(',').map(value => value.trim()).filter(Boolean))];
    const supabaseUrl = env('SUPABASE_URL') || '';
    const anonKey = env('SUPABASE_ANON_KEY') || '';
    const email = env('QUALITY_CANARY_EMAIL') || '';
    const password = env('QUALITY_CANARY_PASSWORD') || '';
    if (!UUID.test(monitorOwner) || !supabaseUrl || !anonKey || !env('SUPABASE_SERVICE_ROLE_KEY') ||
        !email || !password || scope.length > 20 || scope.some(value => !UUID.test(value))) {
      return json(503, { error: 'visual_configuration_missing', cleanup });
    }

    let job: Job;
    try {
      await call('enqueue_hosted_visual_jobs', { detail_user_ids: scope });
      const claimed = await call('claim_hosted_visual_job');
      if (!claimed) return json(200, { status: 'idle', cleanup });
      if (!validJob(claimed)) return json(503, { error: 'invalid_visual_job', cleanup });
      job = claimed;
    } catch { return json(503, { error: 'visual_queue_failed', cleanup }); }
    const fence = { job_id: job.id, token: job.lease_token, expected_fence: job.fence };
    const complete = async (inspection: VisualInspection | null, reason: string | null = null) => {
      const recorded = await call('complete_hosted_visual_job', { ...fence, inspection, error_text: reason });
      return json(200, { status: recorded === true ? (reason ? 'failed' : 'completed') : 'superseded',
        ...(recorded === true && reason ? { reason } : {}), cleanup });
    };
    const defer = async (reason: string) => {
      const recorded = await call('defer_hosted_visual_job', { ...fence, reason });
      return json(200, { status: recorded === true ? 'deferred' : 'superseded', cleanup });
    };

    try {
      if (job.kind === 'canary' && (job.owner_id !== monitorOwner || !job.fixture || !job.reference ||
          job.fixture.id !== job.fixture_id || job.fixture.url !== job.checked_url ||
          job.reference.id !== job.fixture_id || job.reference.version !== job.fixture_version)) {
        return await complete(null, 'canary_configuration_mismatch');
      }
      if (job.reference && (!job.fixture || job.reference.id !== job.fixture.id ||
          job.reference.id !== job.fixture_id || job.reference.version !== job.fixture_version)) {
        return await complete(null, 'reference_identity_mismatch');
      }

      if (!job.item_id) {
        if (job.kind !== 'canary' || !job.fixture) return await complete(null, 'item_missing');
        if (now() - Date.parse(job.created_at) >= MAX_SETTLEMENT_MS) return await complete(null, 'capture_timeout');
        const result = await capture({ jobId: job.id, fixture: job.fixture, expectedUserId: monitorOwner,
          email, password, supabaseUrl, anonKey }, {
          auth, fetcher,
          recordItem: async itemId => await call('register_hosted_visual_capture', { ...fence, item_id: itemId }) === true,
        });
        if (result.status === 'captured') return json(200, { status: 'captured', cleanup });
        if (result.status === 'pending') return await defer(result.reason);
        return await complete(null, result.reason);
      }

      const itemResult = await bounded(db.from('items').select(ITEM_COLUMNS).eq('id', job.item_id).eq('user_id', job.owner_id).maybeSingle());
      if ((itemResult as any).error) return await complete(null, 'item_read_failed');
      const item = (itemResult as any).data;
      if (!item) return await complete(null, 'item_missing');
      if (item.id !== job.item_id || item.user_id !== job.owner_id || item.type !== 'link' || item.url !== job.checked_url ||
          (job.kind === 'canary' && item.is_public !== false) || (job.fixture && item.url !== job.fixture.url)) {
        return await complete(null, 'item_identity_mismatch');
      }
      if (job.kind === 'canary' && !['complete', 'partial'].includes(item.attributes?.enrichment?.status)) {
        // Queue age is not enrichment age: time spent waiting before the real
        // save must not shorten its bounded opportunity to finish enrichment.
        const capturedAt = Date.parse(item.created_at);
        if (!Number.isFinite(capturedAt)) return await complete(null, 'item_timestamp_invalid');
        if (now() - capturedAt >= MAX_SETTLEMENT_MS) return await complete(null, 'enrichment_settlement_timeout');
        return await defer('enrichment_pending');
      }

      let inspection: VisualInspection;
      try {
        inspection = await inspect({ item, surfaces: resolveVisualSurfaces(item, supabaseUrl),
          ...(job.reference ? { reference: job.reference } : {}) }, {
          supabaseUrl, apiKey: env('OPENAI_API_KEY'), fetcher,
          loadReference: async path => {
            // inspectVisuals requests only the fixed reference supplied above.
            if (!job.reference || path !== job.reference.image_path) throw new Error('reference_identity_mismatch');
            const result = await bounded(db.storage.from('quality-reference-images').download(path));
            if ((result as any).error || !(result as any).data) throw new Error('reference_unavailable');
            return new Uint8Array(await bounded((result as any).data.arrayBuffer()));
          },
          authorizeModel: async () => await call('authorize_hosted_visual_model', fence) === true,
        });
      } catch { return await complete(null, 'visual_inspection_failed'); }
      return await complete(inspection);
    } catch { return json(503, { error: 'visual_processing_failed', cleanup }); }
  };
}
