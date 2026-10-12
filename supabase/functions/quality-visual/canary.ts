import { decodeJwtPayload, isAgentToken } from '../_shared/agentToken.ts';
import { isPublicPreviewUrl } from '../_shared/previewUrl.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const AUTH_TIMEOUT_MS = 10_000;
const CAPTURE_TIMEOUT_MS = 40_000;
const STORE_TIMEOUT_MS = 8_000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

/** Server-only input. The coordinator must read fixture from its approved
 * baseline registry and identity/credentials from server configuration, never
 * from request JSON. jobId is the durable job's UUID, reused on every wake. */
export interface CanaryCaptureInput {
  jobId: string;
  fixture: { id: string; url: string };
  expectedUserId: string;
  email: string;
  password: string;
  supabaseUrl: string;
  anonKey: string;
}

export interface CanaryAuth {
  signInWithPassword(credentials: { email: string; password: string }): PromiseLike<{
    data: {
      user: { id: string } | null;
      session: { access_token: string; user: { id: string } } | null;
    };
    error: unknown;
  }>;
}

export interface CanaryCaptureDeps {
  /** Supabase auth client configured with persistSession/autoRefreshToken false. */
  auth: CanaryAuth;
  fetcher?: typeof fetch;
  /** Fenced, durable registration of this item on the same job. Success must
   * mean that the next wake can retrieve it, including after a worker crash. */
  recordItem(itemId: string): Promise<boolean>;
}

export type CanaryCaptureResult =
  | { status: 'captured'; capture_id: string; item_id: string; duplicate: boolean }
  | { status: 'pending'; capture_id: string; reason: 'capture_in_progress' | 'request_unconfirmed' | 'registration_failed'; item_id?: string }
  | { status: 'failed'; capture_id: string; reason: 'invalid_configuration' | 'authentication_failed' | 'identity_mismatch' | 'capture_refused' | 'capture_identity_mismatch' | 'capture_missing'; http_status?: number };

async function bounded<T>(operation: PromiseLike<T>, timeoutMs: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error('operation_timeout')), timeoutMs);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

function projectOrigin(value: string): string | null {
  try {
    const parsed = new URL(value);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
        parsed.search || parsed.hash || parsed.pathname !== '/' ||
        !/^[a-z0-9-]+\.supabase\.co$/.test(parsed.hostname)) return null;
    return parsed.origin;
  } catch { return null; }
}

async function readJson(response: Response): Promise<Record<string, unknown> | null> {
  const length = Number(response.headers.get('Content-Length'));
  if (length > MAX_RESPONSE_BYTES || !response.body) {
    await response.body?.cancel().catch(() => {});
    return null;
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let total = 0;
  let text = '';
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_RESPONSE_BYTES) {
        await reader.cancel().catch(() => {});
        return null;
      }
      text += decoder.decode(value, { stream: true });
    }
    const parsed = JSON.parse(text + decoder.decode());
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : null;
  } finally { reader.releaseLock(); }
}

/** A real private save, through capture -> add-url with the monitor's own
 * password-authenticated user JWT. The normal entitlement and RLS checks run.
 * There are no inline retries or enrichment polls. An uncertain response is
 * retried by the next wake with the SAME capture receipt, not another save. */
export async function captureCanary(input: CanaryCaptureInput, deps: CanaryCaptureDeps): Promise<CanaryCaptureResult> {
  const capture_id = input.jobId.toLowerCase();
  const origin = projectOrigin(input.supabaseUrl);
  if (!UUID.test(capture_id) || !UUID.test(input.expectedUserId) || !origin ||
      !input.fixture.id || !isPublicPreviewUrl(input.fixture.url) ||
      !input.email.includes('@') || !input.password || !input.anonKey) {
    return { status: 'failed', capture_id, reason: 'invalid_configuration' };
  }

  let signedIn: Awaited<ReturnType<CanaryAuth['signInWithPassword']>>;
  try {
    signedIn = await bounded(deps.auth.signInWithPassword({ email: input.email, password: input.password }), AUTH_TIMEOUT_MS);
  } catch {
    return { status: 'failed', capture_id, reason: 'authentication_failed' };
  }
  const session = signedIn.data?.session;
  if (signedIn.error || !session?.access_token || !signedIn.data.user) {
    return { status: 'failed', capture_id, reason: 'authentication_failed' };
  }
  // This is a claim sanity check on the token just issued by trusted Auth,
  // not an attempt to verify an arbitrary bearer token supplied by a caller.
  const claims = decodeJwtPayload(session.access_token);
  if (signedIn.data.user.id !== input.expectedUserId || session.user.id !== input.expectedUserId ||
      claims?.sub !== input.expectedUserId || claims?.role !== 'authenticated' || isAgentToken(session.access_token)) {
    return { status: 'failed', capture_id, reason: 'identity_mismatch' };
  }

  const controller = new AbortController();
  let response: Response;
  let body: Record<string, unknown> | null;
  try {
    ({ response, body } = await bounded((async () => {
      const response = await (deps.fetcher ?? fetch)(`${origin}/functions/v1/capture`, {
        method: 'POST', redirect: 'error', signal: controller.signal,
        headers: { Authorization: `Bearer ${session.access_token}`, apikey: input.anonKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({ capture_id, kind: 'url', url: input.fixture.url, is_public: false }),
      });
      // No raw response/error text or credentials are returned to reporting.
      return { response, body: response.ok ? await readJson(response) : null };
    })(), CAPTURE_TIMEOUT_MS));
  } catch {
    return { status: 'pending', capture_id, reason: 'request_unconfirmed' };
  } finally { controller.abort(); }

  if (response.status === 409) return { status: 'pending', capture_id, reason: 'capture_in_progress' };
  if (response.status >= 500 || (response.ok && !body)) {
    return { status: 'pending', capture_id, reason: 'request_unconfirmed' };
  }
  if (!response.ok) return { status: 'failed', capture_id, reason: 'capture_refused', http_status: response.status };
  if (body?.duplicate === true && body.item === null) return { status: 'failed', capture_id, reason: 'capture_missing' };

  const item = body?.item as Record<string, unknown> | undefined;
  if (!item || typeof item.id !== 'string' || !UUID.test(item.id) || item.user_id !== input.expectedUserId ||
      item.is_public !== false || item.url !== input.fixture.url) {
    return { status: 'failed', capture_id, reason: 'capture_identity_mismatch' };
  }
  let registered = false;
  try { registered = await bounded(deps.recordItem(item.id), STORE_TIMEOUT_MS); } catch { /* retry same receipt */ }
  if (!registered) return { status: 'pending', capture_id, reason: 'registration_failed', item_id: item.id };
  return { status: 'captured', capture_id, item_id: item.id, duplicate: body?.duplicate === true };
}

export interface RegisteredCanary {
  item_id: string;
  user_id: string;
  is_public: boolean;
  settled: boolean;
  file_path: string | null;
}

export interface CanaryCleanupDeps {
  /** Read from server-owned job registration, not a caller-supplied item id. */
  registeredItem(jobId: string): Promise<RegisteredCanary | null>;
  /** Atomic deletion must recheck job registration, owner, private visibility,
   * settlement and expectedFilePath to fence changes after the above read. */
  deleteItem(input: { jobId: string; itemId: string; userId: string; expectedFilePath: string | null }): Promise<boolean>;
  /** Include approved baseline assets as well as remaining item references. */
  isPreviewReferenced(path: string): Promise<boolean>;
  removePreview(path: string): Promise<boolean>;
}

/** Deliberately has no arbitrary item-id or path argument. Cleanup cannot
 * delete normal user content, remote media or approved known-good assets. */
export async function cleanupCanary(
  input: { jobId: string; expectedUserId: string }, deps: CanaryCleanupDeps,
): Promise<{ deleted: boolean; preview: 'removed' | 'kept' }> {
  if (!UUID.test(input.jobId) || !UUID.test(input.expectedUserId)) return { deleted: false, preview: 'kept' };
  let item: RegisteredCanary | null;
  try { item = await bounded(deps.registeredItem(input.jobId), STORE_TIMEOUT_MS); } catch { return { deleted: false, preview: 'kept' }; }
  if (!item || !UUID.test(item.item_id) || item.user_id !== input.expectedUserId || item.is_public !== false || item.settled !== true) {
    return { deleted: false, preview: 'kept' };
  }
  let deleted = false;
  try {
    deleted = await bounded(deps.deleteItem({
      jobId: input.jobId, itemId: item.item_id, userId: input.expectedUserId, expectedFilePath: item.file_path,
    }), STORE_TIMEOUT_MS);
  } catch { /* keep media when deletion is uncertain */ }
  if (!deleted) return { deleted: false, preview: 'kept' };

  const path = item.file_path;
  const ownedPreview = new RegExp(`^${input.expectedUserId}/previews/preview_[0-9]+\\.(?:jpe?g|png|webp|gif|avif|heic)$`);
  if (!path || !ownedPreview.test(path)) return { deleted: true, preview: 'kept' };
  try {
    if (await bounded(deps.isPreviewReferenced(path), STORE_TIMEOUT_MS)) return { deleted: true, preview: 'kept' };
    return { deleted: true, preview: await bounded(deps.removePreview(path), STORE_TIMEOUT_MS) ? 'removed' : 'kept' };
  } catch { return { deleted: true, preview: 'kept' }; }
}
