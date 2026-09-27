// capture — the idempotent single entry point for captures (iOS plan 15).
// Contract: docs/PLATFORM_API.md → "POST /capture". Pure logic lives in
// ../_shared/capture.ts (vitest-covered); this file owns the I/O.
//
// Flow: authenticate → parse (JSON meta, or multipart meta + file) →
// reserve a capture_receipts row for (user, capture_id) under a fresh
// attempt_id → [upload the file to stash-media/<uid>/<capture_id>.<ext>] →
// forward to the unchanged add-note / add-url / add-file with the caller's own
// JWT → mark the receipt done with the item id (or release it when the
// downstream call failed, so a retry can proceed). A retry of a finished
// capture_id answers with the recorded item and `duplicate: true`.
//
// Every receipt write after the reservation is fenced by this attempt's
// attempt_id: an attempt that stalled and was taken over can no longer touch
// its successor's row, and if it finishes anyway it deletes the duplicate item
// it created and answers 409 (settleSuccess / settleFailure in _shared).
//
// Runs entirely as the caller (anon key + their JWT): RLS on capture_receipts,
// items and storage applies. No service role.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { bearerToken, isAgentToken } from '../_shared/agentToken.ts';
import {
  META_BYTES_LIMIT,
  ONE_SHOT_FILE_LIMIT,
  RECEIPT_HEARTBEAT_MS,
  decideReceipt,
  downstreamBodyFor,
  downstreamPathFor,
  drainStream,
  exceedsDeclaredLength,
  exceedsMultipartBodyLimit,
  fileExtensionFor,
  interpretFencedWrite,
  normalizeDownstreamItem,
  parseCaptureMeta,
  readCappedBytes,
  requestBodyKind,
  settleFailure,
  settleSuccess,
  storedObjectPath,
  type AttemptStore,
  type CaptureMeta,
  type ReceiptRow,
  type WriteResult,
} from '../_shared/capture.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const invalid = (message: string) => json(400, { error: 'invalid_request', message });
const fileTooLarge = () => json(413, { error: 'file_too_large', max_bytes: ONE_SHOT_FILE_LIMIT });
const metaTooLarge = () => json(413, { error: 'meta_too_large', max_bytes: META_BYTES_LIMIT });
const inProgress = () => json(409, { error: 'capture_in_progress' });

// The gateway buffers the whole request before invoking the function and
// answers a bare 502 when the function responds without reading the body
// (observed 2026-09-27 with a 47 MiB multipart). Every early response to a
// request whose body may still be unread goes through here: the body is read
// and discarded chunk by chunk (never buffered), then the real answer is sent.
const DRAIN_CAP_BYTES = 256 * 1024 * 1024;
async function afterDraining(req: Request, response: Response): Promise<Response> {
  if (!req.bodyUsed) await drainStream(req.body, DRAIN_CAP_BYTES);
  return response;
}

// Isolate memory (MB) — the multipart path holds the upload in memory, and the
// worker limit is 256 MB; logged so the one-shot headroom stays visible.
const memoryMb = (): Record<string, number> => {
  try {
    const { heapUsed, external } = Deno.memoryUsage();
    return { heap_mb: Math.round(heapUsed / 1048576), external_mb: Math.round(external / 1048576) };
  } catch {
    return {};
  }
};

const RECEIPTS = 'capture_receipts';
const BUCKET = 'stash-media';

type LogContext = { user_id: string; capture_id: string; kind: string };

const errorMessage = (e: unknown) => (e instanceof Error ? e.message : String(e));

type Reservation =
  | { kind: 'reserved'; attemptId: string; tookOver: boolean }
  | { kind: 'duplicate'; itemId: string | null }
  | { kind: 'inProgress' }
  | { kind: 'failed'; message: string };

// Insert-first: the primary key (user_id, capture_id) makes the reservation
// atomic. On a unique violation, read the existing receipt and apply the
// decision rules. A stale pending receipt is claimed with a compare-and-set on
// the (updated_at, attempt_id) we read, stamping our own fresh attempt_id — so
// only one contender wins, and the dead attempt's later writes (fenced by its
// old id) match nothing.
async function reserveReceipt(db: SupabaseClient, userId: string, captureId: string): Promise<Reservation> {
  for (let round = 0; round < 3; round++) {
    const attemptId = crypto.randomUUID();
    const { error: insertError } = await db
      .from(RECEIPTS)
      .insert({ user_id: userId, capture_id: captureId, status: 'pending', attempt_id: attemptId });
    if (!insertError) return { kind: 'reserved', attemptId, tookOver: false };
    if (insertError.code !== '23505') return { kind: 'failed', message: insertError.message };

    const { data: existing, error: readError } = await db
      .from(RECEIPTS)
      .select('status, item_id, updated_at, attempt_id')
      .eq('user_id', userId)
      .eq('capture_id', captureId)
      .maybeSingle<ReceiptRow>();
    if (readError) return { kind: 'failed', message: readError.message };

    const decision = decideReceipt(existing, Date.now());
    if (decision.action === 'proceed' || !existing) continue; // released between our insert and read
    if (decision.action === 'duplicate') return { kind: 'duplicate', itemId: decision.itemId };
    if (decision.action === 'inProgress') return { kind: 'inProgress' };

    let claim = db
      .from(RECEIPTS)
      .update({ updated_at: new Date().toISOString(), attempt_id: attemptId })
      .eq('user_id', userId)
      .eq('capture_id', captureId)
      .eq('status', 'pending')
      .eq('updated_at', existing.updated_at);
    claim = existing.attempt_id ? claim.eq('attempt_id', existing.attempt_id) : claim.is('attempt_id', null);
    const { data: claimed, error: claimError } = await claim.select('capture_id');
    if (claimError) return { kind: 'failed', message: claimError.message };
    if (claimed && claimed.length > 0) return { kind: 'reserved', attemptId, tookOver: true };
    // Someone else re-stamped, claimed or finished it first — decide again.
  }
  return { kind: 'inProgress' };
}

type Rows = { data: unknown[] | null; error: { code?: string; message: string } | null };
const toWrite = ({ data, error }: Rows): WriteResult =>
  error ? { ok: false, code: error.code, message: error.message } : { ok: true, rows: data?.length ?? 0 };

// The receipt writes this attempt may make, each filtered by its attempt_id.
function attemptStore(db: SupabaseClient, userId: string, captureId: string, attemptId: string, log: LogContext): AttemptStore {
  const receipt = () => db.from(RECEIPTS);
  return {
    finalize: async (itemId) =>
      toWrite(
        await receipt()
          .update({ status: 'done', item_id: itemId, updated_at: new Date().toISOString() })
          .eq('user_id', userId)
          .eq('capture_id', captureId)
          .eq('attempt_id', attemptId)
          .select('capture_id'),
      ),
    release: async () =>
      toWrite(
        await receipt()
          .delete()
          .eq('user_id', userId)
          .eq('capture_id', captureId)
          .eq('attempt_id', attemptId)
          .eq('status', 'pending')
          .select('capture_id'),
      ),
    touch: async () =>
      toWrite(
        await receipt()
          .update({ updated_at: new Date().toISOString() })
          .eq('user_id', userId)
          .eq('capture_id', captureId)
          .eq('attempt_id', attemptId)
          .eq('status', 'pending')
          .select('capture_id'),
      ),
    deleteItem: async (itemId) => toWrite(await db.from('items').delete().eq('id', itemId).select('id')),
    removeObject: async (path) => {
      const { data, error } = await db.storage.from(BUCKET).remove([path]);
      return error ? { ok: false, message: error.message } : { ok: true, rows: data?.length ?? 0 };
    },
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    log: (level, message, fields) => console[level](message, { ...log, ...fields }),
  };
}

type Heartbeat = { stop: () => void; readonly superseded: boolean };

// Keeps a live attempt's receipt fresh so a slow downstream call (add-url's
// page fetch has no timeout) is never taken over by a retry. Fenced like every
// other write: finding the receipt taken over stops it.
function startHeartbeat(store: AttemptStore): Heartbeat {
  let stopped = false;
  let superseded = false;
  const timer = setInterval(async () => {
    let result: WriteResult;
    try {
      result = await store.touch();
    } catch (e) {
      result = { ok: false, message: errorMessage(e) };
    }
    if (stopped) return;
    const verdict = interpretFencedWrite(result);
    if (verdict === 'superseded') {
      superseded = true;
      stopped = true;
      clearInterval(timer);
      store.log('warn', 'capture: heartbeat found the receipt taken over');
    } else if (!result.ok) {
      store.log('warn', 'capture: heartbeat failed', { message: result.message });
    }
  }, RECEIPT_HEARTBEAT_MS);
  return {
    stop: () => {
      stopped = true;
      clearInterval(timer);
    },
    get superseded() {
      return superseded;
    },
  };
}

async function currentItem(db: SupabaseClient, itemId: string | null, log: LogContext) {
  if (!itemId) return null;
  const { data, error } = await db.from('items').select('*').eq('id', itemId).maybeSingle();
  if (error) {
    console.error('capture: reading the recorded item failed', { ...log, item_id: itemId, message: error.message });
    return null;
  }
  return data ?? null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return await afterDraining(req, json(405, { error: 'Method not allowed' }));

  const started = Date.now();
  try {
    const token = bearerToken(req.headers.get('Authorization'));
    if (!token) return await afterDraining(req, json(401, { error: 'Missing authorization token' }));
    const authorization = `Bearer ${token}`;
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const db = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    const { data: { user }, error: authError } = await db.auth.getUser(token);
    if (authError || !user) return await afterDraining(req, json(401, { error: 'Invalid or expired token' }));
    if (isAgentToken(token)) {
      return await afterDraining(req, json(403, { error: 'Agent tokens are only accepted by the MCP endpoint' }));
    }

    // ---- body ----
    const bodyKind = requestBodyKind(req.headers.get('Content-Type'));
    if (!bodyKind) {
      return await afterDraining(req, invalid('Content-Type must be application/json or multipart/form-data'));
    }
    const declaredLength = req.headers.get('Content-Length');

    let raw: unknown;
    let file: File | null = null;
    let parseMemory: Record<string, number> | undefined;
    if (bodyKind === 'multipart') {
      if (exceedsMultipartBodyLimit(declaredLength)) {
        // 413 without parsing: the body is drained, never held in memory.
        console.warn('capture: multipart body over the one-shot limit', { user_id: user.id, content_length: declaredLength });
        return await afterDraining(req, fileTooLarge());
      }
      let form: FormData;
      try {
        form = await req.formData();
      } catch {
        return await afterDraining(req, invalid('malformed multipart body'));
      }
      parseMemory = memoryMb();
      const metaPart = form.get('meta');
      if (metaPart === null) return invalid('a multipart body needs a "meta" part');
      if ((typeof metaPart === 'string' ? metaPart.length : metaPart.size) > META_BYTES_LIMIT) return metaTooLarge();
      try {
        raw = JSON.parse(typeof metaPart === 'string' ? metaPart : await metaPart.text());
      } catch {
        return invalid('the "meta" part must be JSON');
      }
      const filePart = form.get('file');
      if (filePart !== null) {
        // Parts without a filename arrive as (lossily decoded) strings.
        if (typeof filePart === 'string') return invalid('the "file" part must carry a filename');
        if (filePart.size > ONE_SHOT_FILE_LIMIT) return fileTooLarge();
        if (filePart.size === 0) return invalid('the "file" part is empty');
        file = filePart;
      }
    } else {
      if (exceedsDeclaredLength(declaredLength, META_BYTES_LIMIT)) {
        console.warn('capture: JSON body over the meta limit', { user_id: user.id, content_length: declaredLength });
        return await afterDraining(req, metaTooLarge());
      }
      // Undeclared or understated lengths are capped while reading.
      const read = await readCappedBytes(req.body, META_BYTES_LIMIT, DRAIN_CAP_BYTES);
      if (read.kind === 'tooLarge') return metaTooLarge();
      if (read.kind === 'failed') return invalid('the body could not be read');
      try {
        raw = JSON.parse(new TextDecoder().decode(read.bytes));
      } catch {
        return invalid('body must be JSON');
      }
    }

    const parsed = parseCaptureMeta(raw, { userId: user.id, hasFile: file !== null });
    if (!parsed.ok) {
      console.warn('capture: rejected', { user_id: user.id, reason: parsed.error });
      return invalid(parsed.error);
    }
    const meta = parsed.meta;
    const log: LogContext = { user_id: user.id, capture_id: meta.capture_id, kind: meta.kind };
    if (parsed.warnings.length > 0) console.warn('capture: ignored fields', { ...log, warnings: parsed.warnings });

    // ---- idempotency receipt ----
    const reservation = await reserveReceipt(db, user.id, meta.capture_id);
    if (reservation.kind === 'failed') {
      console.error('capture: receipt unavailable', { ...log, message: reservation.message });
      return json(500, { error: 'receipt_failed', message: reservation.message });
    }
    if (reservation.kind === 'inProgress') {
      console.log('capture: in progress elsewhere', log);
      return inProgress();
    }
    if (reservation.kind === 'duplicate') {
      const item = await currentItem(db, reservation.itemId, log);
      console.log('capture: duplicate', { ...log, item_id: reservation.itemId, item_found: item !== null, ms: Date.now() - started });
      return json(200, { item, duplicate: true });
    }
    if (reservation.tookOver) console.warn('capture: took over a stale pending receipt', log);

    // ---- the capture (every receipt write from here on is fenced) ----
    const store = attemptStore(db, user.id, meta.capture_id, reservation.attemptId, log);
    const heartbeat = startHeartbeat(store);
    let settled = false; // this attempt's receipt outcome has been decided
    let created = false; // downstream answered 2xx — the item exists
    let storedPath: string | undefined;
    try {
      let forwardMeta: CaptureMeta = meta;
      if (file) {
        const path = storedObjectPath(user.id, meta.capture_id, fileExtensionFor(meta.file_name, meta.mime_type));
        // Re-typed so the stored object's content type is mime_type whatever the part said.
        const { error: uploadError } = await db.storage
          .from(BUCKET)
          .upload(path, new Blob([file], { type: meta.mime_type }), { upsert: true, contentType: meta.mime_type });
        if (uploadError) {
          heartbeat.stop();
          await settleFailure(store);
          settled = true;
          store.log('error', 'capture: storage upload failed', { message: uploadError.message });
          return json(502, { error: 'storage_upload_failed', message: uploadError.message });
        }
        storedPath = path;
        forwardMeta = { ...meta, file_size: meta.file_size ?? file.size };
      }

      if (heartbeat.superseded) {
        // Taken over while we were uploading: the successor owns this capture.
        heartbeat.stop();
        settled = true;
        store.log('warn', 'capture: superseded before forwarding; standing down');
        return inProgress();
      }

      const downstream = downstreamPathFor(meta.kind);
      let res: Response;
      try {
        res = await fetch(`${supabaseUrl}/functions/v1/${downstream}`, {
          method: 'POST',
          headers: { Authorization: authorization, apikey: anonKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(downstreamBodyFor(forwardMeta, storedPath)),
        });
      } catch (e) {
        heartbeat.stop();
        await settleFailure(store); // keep any upload: the item may exist after all
        settled = true;
        store.log('error', 'capture: downstream unreachable', { path: downstream, message: errorMessage(e) });
        return json(502, { error: 'downstream_unreachable', message: errorMessage(e) });
      }

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        heartbeat.stop();
        await settleFailure(store, storedPath);
        settled = true;
        store.log('warn', 'capture: downstream refused', { path: downstream, status: res.status, ms: Date.now() - started });
        return new Response(text, {
          status: res.status,
          headers: { ...corsHeaders, 'Content-Type': res.headers.get('Content-Type') ?? 'application/json' },
        });
      }

      created = true;
      let body: unknown = null;
      try {
        body = JSON.parse(await res.text());
      } catch (e) {
        store.log('error', 'capture: unreadable downstream body', { path: downstream, message: errorMessage(e) });
      }
      const item = normalizeDownstreamItem(body);
      const itemId = typeof item?.id === 'string' ? item.id : null;
      if (!itemId) store.log('error', 'capture: downstream answered 2xx without an item id', { path: downstream, status: res.status });

      heartbeat.stop();
      const settlement = await settleSuccess(store, itemId);
      settled = true;
      if (settlement.outcome === 'superseded') return inProgress();
      if (settlement.outcome === 'unrecorded') store.log('error', 'capture: saved, but the receipt could not be recorded', { item_id: itemId });
      store.log('log', 'capture: saved', {
        item_id: itemId,
        bytes: file?.size ?? null,
        ms: Date.now() - started,
        ...(parseMemory ? { memory_after_parse: parseMemory } : {}),
      });
      return json(200, { item, duplicate: false });
    } catch (e) {
      heartbeat.stop();
      if (!settled) {
        // Before the downstream answered nothing was created: release. After a
        // 2xx the item exists: record the capture (id unknown here).
        if (created) await settleSuccess(store, null);
        else await settleFailure(store, storedPath);
      }
      throw e;
    } finally {
      heartbeat.stop();
    }
  } catch (e) {
    console.error('capture: unexpected error', errorMessage(e));
    return await afterDraining(req, json(500, { error: 'Internal server error' }));
  }
});
