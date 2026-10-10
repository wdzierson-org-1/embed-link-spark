import { collectLiveEvidence, livePublicUrl } from './liveEvidence.ts';

type Env = (name: string) => string | undefined;
type DB = { rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: any; error: any }> };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const object = (x: any): x is Record<string, any> => !!x && typeof x === 'object' && !Array.isArray(x);
function keys(x: any, allowed: string[]) { if (!object(x) || Object.keys(x).some(k => !allowed.includes(k))) throw new Error('invalid_fields'); }
function text(x: any, max: number, optional = false) { if (optional && x === undefined) return; if (typeof x !== 'string' || !x.trim() || x.length > max) throw new Error('invalid_text'); }
function list(x: any, max: number) { if (!Array.isArray(x) || x.length > max) throw new Error('invalid_list'); }

export async function authorized(actual: string | null, expected?: string): Promise<boolean> {
  if (!expected || !actual || actual.length > 512) return false;
  const digest = async (value: string) => new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  const [a, b] = await Promise.all([digest(actual), digest(expected)]);
  let diff = 0; for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]; return diff === 0;
}
export async function readBody(req: Request, limit = 128_000): Promise<any> {
  const reader = req.body?.getReader(); if (!reader) throw new Error('invalid_json');
  const chunks: Uint8Array[] = []; let length = 0;
  try { while (true) { const { done, value } = await reader.read(); if (done) break; length += value.length;
    if (length > limit) { await reader.cancel(); throw new Error('body_too_large'); } chunks.push(value); }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length); let offset = 0; for (const c of chunks) { bytes.set(c, offset); offset += c.length; }
  try { return JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new Error('invalid_json'); }
}
/** Syntax gate only; this API does not fetch citations. Browser egress is separately constrained. */
export function publicEvidenceUrl(value: unknown): value is string {
  if (typeof value !== 'string' || value.length > 2000) return false;
  try { const u = new URL(value); const h = u.hostname.toLowerCase();
    return u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443') &&
      h.includes('.') && !h.includes(':') && !/^\d+(\.\d+)*$/.test(h) &&
      !/(^|\.)(localhost|local|internal|invalid)$/.test(h);
  } catch { return false; }
}
const normalize = (s: string) => s.replace(/\s+/g, ' ').trim();
export function validateResult(result: any, job: any) {
  keys(result, ['schema_version', 'summary', 'findings', 'proposals', 'uncertainties']);
  if (result.schema_version !== 1) throw new Error('invalid_schema_version');
  text(result.summary, 6000); list(result.findings, 20); list(result.proposals, 5); list(result.uncertainties, 20);
  const items = new Map<string, any>((job.input?.items || []).map((i: any) => [i.id, i]));
  for (const finding of result.findings) {
    keys(finding, ['item_id', 'category', 'severity', 'claim', 'evidence', 'recommendation']);
    if (finding.item_id !== undefined && !items.has(finding.item_id)) throw new Error('item_out_of_scope');
    if (!finding.item_id && finding.category !== 'operations') throw new Error('item_required');
    if (!['identity', 'summary_grounding', 'image_association', 'source_completeness', 'freshness', 'retrieval', 'operations'].includes(finding.category)) throw new Error('invalid_category');
    if (!['info', 'warning', 'error'].includes(finding.severity)) throw new Error('invalid_severity');
    text(finding.claim, 1500); text(finding.recommendation, 1500); list(finding.evidence, 5);
    if (finding.category !== 'operations' && !finding.evidence.length) throw new Error('evidence_required');
    const item = items.get(finding.item_id);
    for (const evidence of finding.evidence) {
      keys(evidence, ['url', 'quote', 'source']); if (!publicEvidenceUrl(evidence.url)) throw new Error('invalid_evidence_url');
      text(evidence.quote, 1000, true);
      if (!item || evidence.url !== item.url) throw new Error('evidence_out_of_scope');
      if (evidence.source !== undefined && !['snapshot', 'live'].includes(evidence.source)) throw new Error('invalid_evidence_source');
      let sourceText = item.page_body || '';
      if (evidence.source === 'live') {
        const observation = job.observation;
        if (job.kind !== 'research' || !observation || observation.outcome !== 'retrieved' || observation.item_id !== item.id || observation.url !== item.url) throw new Error('evidence_out_of_scope');
        sourceText = observation.text;
      }
      if (evidence.quote && !normalize(sourceText).includes(normalize(evidence.quote))) throw new Error('quote_not_in_source');
    }
  }
  for (const proposal of result.proposals) {
    keys(proposal, ['title', 'rationale', 'evidence_urls']); text(proposal.title, 200); text(proposal.rationale, 2000); list(proposal.evidence_urls, 5);
    if (!proposal.evidence_urls.length || proposal.evidence_urls.some((u: any) => !publicEvidenceUrl(u))) throw new Error('invalid_proposal_evidence');
    if (proposal.evidence_urls.some((u: string) => ![...items.values()].some(i => i.url === u))) throw new Error('evidence_out_of_scope');
  }
  result.uncertainties.forEach((x: unknown) => text(x, 1000));
  return result;
}
function validateUsage(usage: any) {
  if (usage === undefined) return {};
  keys(usage, ['model', 'input_tokens', 'output_tokens', 'cost_usd']); text(usage.model, 100, true);
  for (const key of ['input_tokens', 'output_tokens', 'cost_usd']) if (usage[key] !== undefined && usage[key] !== null &&
    (typeof usage[key] !== 'number' || !Number.isFinite(usage[key]) || usage[key] < 0 || usage[key] > (key === 'cost_usd' ? 1000 : 10_000_000) || (key !== 'cost_usd' && !Number.isInteger(usage[key])))) throw new Error('invalid_usage');
  return usage;
}
// Keep this bounded contract identical in the backend and hosted supervisor.
const IMAGE_REASONS: Record<string, string[]> = {
  usable_asset: ['raster_structure_valid'],
  unavailable: ['unsafe_image_url', 'unsupported_image_host', 'image_not_associated', 'image_timeout',
    'image_request_failed', 'image_http_error', 'image_redirect_rejected', 'unsupported_raster_format'],
  invalid: ['image_too_large', 'empty_image', 'non_raster_response', 'image_mime_mismatch',
    'invalid_raster_structure', 'image_too_small', 'image_dimensions_excessive'],
};
function validateImageChecks(observation: any, refused: boolean) {
  if (observation.image_checks === undefined) return;
  list(observation.image_checks, 1);
  if (!observation.image_checks.length) return;
  if (refused || !observation.limitations.includes('image_pixels_not_verified') ||
    !observation.limitations.includes('image_decode_not_verified')) throw new Error('invalid_image_check');
  const first = observation.image_candidates.find((image: any) => image.associated);
  for (const check of observation.image_checks) {
    keys(check, ['url', 'source_url', 'associated', 'strategy', 'outcome', 'reason', 'checked_at', 'duration_ms',
      'mime_type', 'byte_length', 'width', 'height', 'sha256']);
    if (!first || check.url !== first.url || check.source_url !== observation.url || check.associated !== true ||
      !livePublicUrl(check.url) || !livePublicUrl(check.source_url) || check.strategy !== 'public_raster_fetch' ||
      !Object.hasOwn(IMAGE_REASONS, check.outcome) || !IMAGE_REASONS[check.outcome].includes(check.reason) ||
      typeof check.checked_at !== 'string' || check.checked_at.length > 40 || !Number.isFinite(Date.parse(check.checked_at)) ||
      !Number.isInteger(check.duration_ms) || check.duration_ms < 0 || check.duration_ms > 10_000) throw new Error('invalid_image_check');
    if (check.mime_type !== undefined && !['image/jpeg', 'image/png', 'image/webp'].includes(check.mime_type)) throw new Error('invalid_image_check');
    if (check.byte_length !== undefined && (!Number.isInteger(check.byte_length) || check.byte_length < 1 || check.byte_length > 5 * 1024 * 1024)) throw new Error('invalid_image_check');
    for (const field of ['width', 'height']) if (check[field] !== undefined &&
      (!Number.isInteger(check[field]) || check[field] < 0 || check[field] > 0xffffffff)) throw new Error('invalid_image_check');
    if ((check.width === undefined) !== (check.height === undefined)) throw new Error('invalid_image_check');
    if (check.outcome === 'usable_asset') {
      if (check.mime_type === undefined || check.byte_length === undefined || check.width === undefined || check.height === undefined ||
        check.width < 100 || check.height < 60 || check.width > 12000 || check.height > 12000 || check.width * check.height > 20_000_000 ||
        typeof check.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(check.sha256)) throw new Error('invalid_image_check');
    } else if (check.sha256 !== undefined) throw new Error('invalid_image_check');
  }
}

function validateObservation(observation: any, item: any) {
  keys(observation, ['schema_version', 'item_id', 'url', 'captured_at', 'outcome', 'title', 'text', 'source_truncated', 'image_candidates', 'image_checks', 'attempts', 'limitations']);
  const refused = observation.outcome === 'unavailable' && observation.title === '' && observation.text === '' && observation.source_truncated === false &&
    Array.isArray(observation.image_candidates) && observation.image_candidates.length === 0 && Array.isArray(observation.attempts) && observation.attempts.length === 1 &&
    observation.attempts[0]?.strategy === 'firecrawl_rendered' && observation.attempts[0]?.outcome === 'unavailable' &&
    observation.attempts[0]?.reason === 'unsafe_url' && observation.attempts[0]?.duration_ms === 0;
  if (Array.isArray(observation.attempts) && observation.attempts.some((a: any) => a?.reason === 'unsafe_url') && !refused) throw new Error('invalid_observation');
  // A refusal retains exact service-owned identity for telemetry, with no retrieved content.
  // The supervisor removes its URL and sampled item before constructing any model prompt.
  if (observation.schema_version !== 1 || observation.item_id !== item.id || observation.url !== item.url || (!livePublicUrl(observation.url) && !refused)) throw new Error('observation_out_of_scope');
  if (new TextEncoder().encode(JSON.stringify(observation)).length > 32_000 || typeof observation.captured_at !== 'string' || observation.captured_at.length > 40 || !Number.isFinite(Date.parse(observation.captured_at)) || !['retrieved', 'blocked', 'unavailable', 'mismatch'].includes(observation.outcome) || typeof observation.source_truncated !== 'boolean') throw new Error('invalid_observation');
  for (const [field, max] of [['title', 400], ['text', 6000]] as const) if (typeof observation[field] !== 'string' || observation[field].length > max) throw new Error('invalid_observation');
  list(observation.image_candidates, 5); list(observation.attempts, 3); list(observation.limitations, 10);
  for (const candidate of observation.image_candidates) {
    keys(candidate, ['url', 'associated']);
    if (!livePublicUrl(candidate.url) || typeof candidate.associated !== 'boolean') throw new Error('invalid_observation');
  }
  if (!observation.attempts.length) throw new Error('invalid_observation');
  for (const attempt of observation.attempts) {
    keys(attempt, ['strategy', 'outcome', 'reason', 'duration_ms']);
    for (const field of ['strategy', 'outcome', 'reason']) if (typeof attempt[field] !== 'string' || !/^[a-z0-9_]{1,80}$/.test(attempt[field])) throw new Error('invalid_observation');
    if (!['firecrawl_rendered', 'jina_reader', 'medium_public_feed'].includes(attempt.strategy) || !['retrieved', 'blocked', 'unavailable', 'mismatch'].includes(attempt.outcome)) throw new Error('invalid_observation');
    if (!Number.isInteger(attempt.duration_ms) || attempt.duration_ms < 0 || attempt.duration_ms > 30_000) throw new Error('invalid_observation');
  }
  observation.limitations.forEach((value: unknown) => text(value, 1000));
  validateImageChecks(observation, refused);
  return observation;
}

export function createWorkerHandler({ db, env, collect = collectLiveEvidence, fetcher = fetch }: { db: DB; env: Env; collect?: typeof collectLiveEvidence; fetcher?: typeof fetch }) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== 'POST') return json(405, { error: 'post_only' });
    const workerToken = env('QUALITY_WORKER_TOKEN');
    if (!workerToken || workerToken.length < 32 || !await authorized(req.headers.get('authorization'), `Bearer ${workerToken}`)) return json(401, { error: 'unauthorized' });
    try {
      const body = await readBody(req);
      const call = async (name: string, args: Record<string, unknown>) => { const r = await db.rpc(name, args); if (r.error) throw new Error('database_error'); return r.data; };
      if (body?.action === 'claim') {
        keys(body, ['action']);
        if (env('QUALITY_ENABLED') !== 'true') return json(200, { job: null, disabled: true });
        return json(200, { job: await call('claim_hosted_quality_job', {}) });
      }
      if (!['heartbeat', 'complete', 'fail', 'investigate'].includes(body?.action)) throw new Error('invalid_action');
      keys(body, ['action', 'job_id', 'lease_token', 'fence', ...(body.action === 'complete' ? ['result', 'usage'] : body.action === 'fail' ? ['reason'] : [])]);
      if (!uuid.test(body.job_id) || !uuid.test(body.lease_token) || !Number.isSafeInteger(body.fence) || body.fence < 1) throw new Error('invalid_lease');
      const args = { target_id: body.job_id, token: body.lease_token, expected_fence: body.fence };
      let result;
      if (body.action === 'investigate') {
        if (env('QUALITY_ENABLED') !== 'true' || env('QUALITY_RESEARCH_ENABLED') !== 'true') return json(503, { error: 'research_disabled' });
        const apiKey = env('FIRECRAWL_API_KEY');
        if (!apiKey) return json(503, { error: 'retrieval_unconfigured' });
        const reservation = await call('reserve_hosted_quality_investigation', args);
        if (!reservation?.ok) return json(409, reservation || { error: 'lease_lost' });
        if (reservation.observation) return json(200, { ok: true, observation: reservation.observation });
        if (!reservation.item || !uuid.test(reservation.attempt_token)) throw new Error('invalid_reservation');
        const observation = validateObservation(await collect(reservation.item, { apiKey, jinaApiKey: env('JINA_API_KEY'), fetcher }), reservation.item);
        result = await call('finish_hosted_quality_investigation', { ...args, attempt_token: reservation.attempt_token, observation_payload: observation });
      } else if (body.action === 'complete') {
        const usage = validateUsage(body.usage);
        const job = await call('hosted_quality_job_context', args);
        if (!job) return json(409, { error: 'lease_lost' });
        validateResult(body.result, job);
        result = await call('complete_hosted_quality_job', { ...args, result_payload: body.result, usage_payload: usage });
      } else if (body.action === 'fail') {
        text(body.reason, 500);
        // Persist error codes/short messages, never credentials or request payloads.
        result = await call('fail_hosted_quality_job', { ...args, failure_reason: body.reason.replace(/https?:\/\/\S+/g, '[url]').replace(/Bearer\s+\S+/gi, '[credential]') });
      } else result = await call('heartbeat_hosted_quality_job', args);
      return json(result?.ok ? 200 : 409, result || { error: 'lease_lost' });
    } catch (e) {
      const error = e instanceof Error ? e.message : 'invalid_request';
      if (error === 'database_error') return json(503, { error });
      return json(error === 'body_too_large' ? 413 : 400, { error });
    }
  };
}
