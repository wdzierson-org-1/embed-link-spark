// capture — the idempotent single entry point for captures (iOS plan 15).
// Contract: docs/PLATFORM_API.md → "POST /capture". Pure logic lives in
// ../_shared/capture.ts (vitest-covered); this file owns the I/O.
//
// Flow: authenticate → parse (JSON meta, or multipart meta + file) →
// reserve a capture_receipts row for (user, capture_id) → [upload the file to
// stash-media/<uid>/<capture_id>.<ext>] → forward to the unchanged add-note /
// add-url / add-file with the caller's own JWT → mark the receipt done with
// the item id (or delete it when the downstream call failed, so a retry can
// proceed). A retry of a finished capture_id answers with the recorded item
// and `duplicate: true` instead of creating another one.
//
// Runs entirely as the caller (anon key + their JWT): RLS on capture_receipts,
// items and storage applies. No service role.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { bearerToken, isAgentToken } from '../_shared/agentToken.ts';
import {
  ONE_SHOT_FILE_LIMIT,
  RECEIPT_HEARTBEAT_MS,
  decideReceipt,
  downstreamBodyFor,
  downstreamPathFor,
  exceedsMultipartBodyLimit,
  fileExtensionFor,
  normalizeDownstreamItem,
  parseCaptureMeta,
  requestBodyKind,
  storedObjectPath,
  type CaptureMeta,
  type ReceiptRow,
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
const tooLarge = () => json(413, { error: 'file_too_large', max_bytes: ONE_SHOT_FILE_LIMIT });

// The gateway buffers the whole request before invoking the function and
// answers a bare 502 when the function responds without reading the body
// (observed 2026-09-27 with a 47 MiB multipart). Every early response to a
// request whose body is still unread goes through here: the body is read and
// discarded chunk by chunk (never buffered), then the real answer is sent.
const DRAIN_CAP_BYTES = 256 * 1024 * 1024;
async function afterDraining(req: Request, response: Response): Promise<Response> {
  if (req.body && !req.bodyUsed) {
    let seen = 0;
    try {
      for await (const chunk of req.body) {
        seen += chunk.byteLength;
        if (seen > DRAIN_CAP_BYTES) break;
      }
    } catch {
      // the client went away — nothing left to answer
    }
  }
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
  | { kind: 'reserved'; tookOver: boolean }
  | { kind: 'duplicate'; itemId: string | null }
  | { kind: 'inProgress' }
  | { kind: 'failed'; message: string };

// Insert-first: the primary key (user_id, capture_id) makes the reservation
// atomic. On a unique violation, read the existing receipt and apply the
// decision rules; a stale pending receipt is claimed with a compare-and-set on
// updated_at so two retries can't both take it over.
async function reserveReceipt(db: SupabaseClient, userId: string, captureId: string): Promise<Reservation> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const { error: insertError } = await db
      .from(RECEIPTS)
      .insert({ user_id: userId, capture_id: captureId, status: 'pending' });
    if (!insertError) return { kind: 'reserved', tookOver: false };
    if (insertError.code !== '23505') return { kind: 'failed', message: insertError.message };

    const { data: existing, error: readError } = await db
      .from(RECEIPTS)
      .select('status, item_id, updated_at')
      .eq('user_id', userId)
      .eq('capture_id', captureId)
      .maybeSingle<ReceiptRow>();
    if (readError) return { kind: 'failed', message: readError.message };

    const decision = decideReceipt(existing, Date.now());
    if (decision.action === 'proceed' || !existing) continue; // released between our insert and read
    if (decision.action === 'duplicate') return { kind: 'duplicate', itemId: decision.itemId };
    if (decision.action === 'inProgress') return { kind: 'inProgress' };

    const { data: claimed, error: claimError } = await db
      .from(RECEIPTS)
      .update({ updated_at: new Date().toISOString() })
      .eq('user_id', userId)
      .eq('capture_id', captureId)
      .eq('status', 'pending')
      .eq('updated_at', existing.updated_at)
      .select('capture_id');
    if (claimError) return { kind: 'failed', message: claimError.message };
    if (claimed && claimed.length > 0) return { kind: 'reserved', tookOver: true };
    // Someone else re-stamped or finished it first — decide again.
  }
  return { kind: 'inProgress' };
}

async function releaseReceipt(db: SupabaseClient, userId: string, captureId: string) {
  try {
    const { error } = await db
      .from(RECEIPTS)
      .delete()
      .eq('user_id', userId)
      .eq('capture_id', captureId)
      .eq('status', 'pending');
    if (error) console.error('capture: releasing the receipt failed', { capture_id: captureId, message: error.message });
  } catch (e) {
    console.error('capture: releasing the receipt failed', { capture_id: captureId, message: errorMessage(e) });
  }
}

async function finalizeReceipt(db: SupabaseClient, userId: string, captureId: string, itemId: string | null) {
  let recordedItem = itemId;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const { error } = await db
        .from(RECEIPTS)
        .update({ status: 'done', item_id: recordedItem, updated_at: new Date().toISOString() })
        .eq('user_id', userId)
        .eq('capture_id', captureId);
      if (!error) return;
      if (error.code === '23503') {
        // The item was deleted before we could record it — the capture still happened.
        recordedItem = null;
        continue;
      }
      console.error('capture: finalizing the receipt failed', { capture_id: captureId, attempt, message: error.message });
    } catch (e) {
      console.error('capture: finalizing the receipt failed', { capture_id: captureId, attempt, message: errorMessage(e) });
    }
    await new Promise((resolve) => setTimeout(resolve, 250 * attempt));
  }
}

// Keeps a live attempt's receipt fresh so a slow downstream call (add-url's
// page fetch has no timeout) is never taken over by a retry.
function startHeartbeat(db: SupabaseClient, userId: string, captureId: string): () => void {
  const timer = setInterval(async () => {
    try {
      const { error } = await db
        .from(RECEIPTS)
        .update({ updated_at: new Date().toISOString() })
        .eq('user_id', userId)
        .eq('capture_id', captureId)
        .eq('status', 'pending');
      if (error) console.warn('capture: heartbeat failed', { capture_id: captureId, message: error.message });
    } catch (e) {
      console.warn('capture: heartbeat failed', { capture_id: captureId, message: errorMessage(e) });
    }
  }, RECEIPT_HEARTBEAT_MS);
  return () => clearInterval(timer);
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

async function removeUpload(db: SupabaseClient, path: string, log: LogContext) {
  try {
    const { error } = await db.storage.from(BUCKET).remove([path]);
    if (error) console.warn('capture: removing the orphaned upload failed', { ...log, message: error.message });
  } catch (e) {
    console.warn('capture: removing the orphaned upload failed', { ...log, message: errorMessage(e) });
  }
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

    let raw: unknown;
    let file: File | null = null;
    let parseMemory: Record<string, number> | undefined;
    if (bodyKind === 'multipart') {
      const declaredLength = req.headers.get('Content-Length');
      if (exceedsMultipartBodyLimit(declaredLength)) {
        // 413 without parsing: the body is drained, never held in memory.
        console.warn('capture: multipart body over the one-shot limit', { user_id: user.id, content_length: declaredLength });
        return await afterDraining(req, tooLarge());
      }
      let form: FormData;
      try {
        form = await req.formData();
      } catch {
        return invalid('malformed multipart body');
      }
      parseMemory = memoryMb();
      const metaPart = form.get('meta');
      if (metaPart === null) return invalid('a multipart body needs a "meta" part');
      try {
        raw = JSON.parse(typeof metaPart === 'string' ? metaPart : await metaPart.text());
      } catch {
        return invalid('the "meta" part must be JSON');
      }
      const filePart = form.get('file');
      if (filePart !== null) {
        // Parts without a filename arrive as (lossily decoded) strings.
        if (typeof filePart === 'string') return invalid('the "file" part must carry a filename');
        if (filePart.size > ONE_SHOT_FILE_LIMIT) return tooLarge();
        if (filePart.size === 0) return invalid('the "file" part is empty');
        file = filePart;
      }
    } else {
      try {
        raw = await req.json();
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
      return json(409, { error: 'capture_in_progress' });
    }
    if (reservation.kind === 'duplicate') {
      const item = await currentItem(db, reservation.itemId, log);
      console.log('capture: duplicate', { ...log, item_id: reservation.itemId, item_found: item !== null, ms: Date.now() - started });
      return json(200, { item, duplicate: true });
    }
    if (reservation.tookOver) console.warn('capture: took over a stale pending receipt', log);

    // ---- the capture ----
    const stopHeartbeat = startHeartbeat(db, user.id, meta.capture_id);
    let settled = false; // receipt finalized or released
    let created = false; // downstream answered 2xx — the item exists
    try {
      let storedPath: string | undefined;
      let forwardMeta: CaptureMeta = meta;
      if (file) {
        storedPath = storedObjectPath(user.id, meta.capture_id, fileExtensionFor(meta.file_name, meta.mime_type));
        // Re-typed so the stored object's content type is mime_type whatever the part said.
        const { error: uploadError } = await db.storage
          .from(BUCKET)
          .upload(storedPath, new Blob([file], { type: meta.mime_type }), { upsert: true, contentType: meta.mime_type });
        if (uploadError) {
          await releaseReceipt(db, user.id, meta.capture_id);
          settled = true;
          console.error('capture: storage upload failed', { ...log, message: uploadError.message });
          return json(502, { error: 'storage_upload_failed', message: uploadError.message });
        }
        forwardMeta = { ...meta, file_size: meta.file_size ?? file.size };
      }

      const path = downstreamPathFor(meta.kind);
      let res: Response;
      try {
        res = await fetch(`${supabaseUrl}/functions/v1/${path}`, {
          method: 'POST',
          headers: { Authorization: authorization, apikey: anonKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(downstreamBodyFor(forwardMeta, storedPath)),
        });
      } catch (e) {
        await releaseReceipt(db, user.id, meta.capture_id);
        settled = true;
        console.error('capture: downstream unreachable', { ...log, path, message: errorMessage(e) });
        return json(502, { error: 'downstream_unreachable', message: errorMessage(e) });
      }

      if (!res.ok) {
        const text = await res.text().catch(() => '');
        await releaseReceipt(db, user.id, meta.capture_id);
        settled = true;
        if (storedPath) await removeUpload(db, storedPath, log);
        console.warn('capture: downstream refused', { ...log, path, status: res.status, ms: Date.now() - started });
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
        console.error('capture: unreadable downstream body', { ...log, path, message: errorMessage(e) });
      }
      const item = normalizeDownstreamItem(body);
      const itemId = typeof item?.id === 'string' ? item.id : null;
      if (!itemId) console.error('capture: downstream answered 2xx without an item id', { ...log, path, status: res.status });
      await finalizeReceipt(db, user.id, meta.capture_id, itemId);
      settled = true;
      console.log('capture: saved', {
        ...log,
        item_id: itemId,
        bytes: file?.size ?? null,
        ms: Date.now() - started,
        ...(parseMemory ? { memory_after_parse: parseMemory } : {}),
      });
      return json(200, { item, duplicate: false });
    } catch (e) {
      if (!settled) {
        // Before the downstream answered: nothing was created, so let a retry
        // proceed. After: the item exists — record the capture as done.
        if (created) await finalizeReceipt(db, user.id, meta.capture_id, null);
        else await releaseReceipt(db, user.id, meta.capture_id);
      }
      throw e;
    } finally {
      stopHeartbeat();
    }
  } catch (e) {
    console.error('capture: unexpected error', errorMessage(e));
    return await afterDraining(req, json(500, { error: 'Internal server error' }));
  }
});
