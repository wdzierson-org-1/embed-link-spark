import { bearerToken, decodeJwtPayload, isAgentToken } from '../_shared/agentToken.ts';
import {
  buildObjectIntelligenceSource, objectIntelligenceFingerprint, readObjectIntelligence,
  type ObjectIntelligence, type ObjectIntelligenceItem,
} from '../_shared/objectIntelligence.ts';
import type { ObjectDraftAction, ObjectInteractionDraft } from '../_shared/objectInteractionDraft.ts';

export const objectInteractionsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};

type User = { id: string; email?: string | null };
type Query = {
  eq(column: string, value: string): Query;
  maybeSingle(): PromiseLike<{ data: unknown; error: unknown }>;
};
type Database = {
  auth: { getUser(token: string): PromiseLike<{ data: { user: User | null }; error: unknown }> };
  from(table: string): { select(columns: string): Query };
};
type Dependencies = {
  db: Database;
  requireEntitlement(user: User): Promise<Response | null>;
  buildDraft(intelligence: ObjectIntelligence, action: ObjectDraftAction, sourceItemId: string): ObjectInteractionDraft | undefined;
};
type Input = { operation: 'inspect'; item_id: string } | {
  operation: 'draft'; item_id: string; action: ObjectDraftAction; source_fingerprint: string;
};

const MAX_BODY_BYTES = 8_192;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FINGERPRINT = /^[0-9a-f]{64}$/;
const ACTIONS: readonly string[] = ['shopping_list', 'recipe_card', 'itinerary'];
const ITEM_COLUMNS = 'id,user_id,type,url,file_path,mime_type,page_body,content,attributes';
const record = (value: unknown): Record<string, unknown> | undefined => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
const json = (status: number, body: unknown, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), {
  status, headers: { ...objectInteractionsHeaders, 'Content-Type': 'application/json', ...headers },
});

class InvalidBody extends Error {
  constructor(readonly status: 400 | 413, readonly code: 'invalid_request' | 'request_too_large') { super(code); }
}

async function readInput(req: Request): Promise<Input> {
  const announced = Number(req.headers.get('content-length'));
  if (announced > MAX_BODY_BYTES) {
    await req.body?.cancel().catch(() => undefined);
    throw new InvalidBody(413, 'request_too_large');
  }
  const reader = req.body?.getReader();
  if (!reader) throw new InvalidBody(400, 'invalid_request');
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_BODY_BYTES) {
        await reader.cancel().catch(() => undefined);
        throw new InvalidBody(413, 'request_too_large');
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const buffer = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.byteLength; }
  let parsed: unknown;
  try { parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(buffer)); }
  catch { throw new InvalidBody(400, 'invalid_request'); }
  const body = record(parsed);
  if (!body || typeof body.item_id !== 'string' || !UUID.test(body.item_id)) throw new InvalidBody(400, 'invalid_request');
  // Postgres returns UUIDs in canonical lowercase regardless of input case.
  const itemId = body.item_id.toLowerCase();
  if (body.operation === 'inspect' && Object.keys(body).every(key => ['operation', 'item_id'].includes(key))) {
    return { operation: 'inspect', item_id: itemId };
  }
  if (body.operation === 'draft' && Object.keys(body).every(key => ['operation', 'item_id', 'action', 'source_fingerprint'].includes(key))
    && typeof body.action === 'string' && ACTIONS.includes(body.action)
    && typeof body.source_fingerprint === 'string' && FINGERPRINT.test(body.source_fingerprint)) {
    return { operation: 'draft', item_id: itemId, action: body.action as ObjectDraftAction, source_fingerprint: body.source_fingerprint };
  }
  throw new InvalidBody(400, 'invalid_request');
}

/** Read-only projection of current owner data; drafts never persist or call a model. */
export function createObjectInteractionsHandler({ db, requireEntitlement, buildDraft }: Dependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: objectInteractionsHeaders });
    if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' }, { Allow: 'POST, OPTIONS' });
    const token = bearerToken(req.headers.get('Authorization'));
    if (!token) return json(401, { error: 'unauthorized' });
    let user: User;
    try {
      const result = await db.auth.getUser(token);
      if (result.error || !result.data.user) return json(401, { error: 'unauthorized' });
      user = result.data.user;
    } catch { return json(401, { error: 'unauthorized' }); }
    // Claims are read only after getUser verification. Service credentials are
    // never an alternate route into this owner-only endpoint.
    if (isAgentToken(token) || decodeJwtPayload(token)?.role === 'service_role') return json(403, { error: 'session_required' });
    if (req.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return json(415, { error: 'json_required' });
    let input: Input;
    try { input = await readInput(req); }
    catch (error) { return error instanceof InvalidBody ? json(error.status, { error: error.code }) : json(400, { error: 'invalid_request' }); }

    try {
      // A service client is necessary for queue metadata, so ownership remains
      // explicit even when the saved object itself is marked public.
      const selected = await db.from('items').select(ITEM_COLUMNS).eq('id', input.item_id).eq('user_id', user.id).maybeSingle();
      if (selected.error) throw new Error('item_read_failed');
      const item = record(selected.data);
      if (!item || item.id !== input.item_id || item.user_id !== user.id) return json(404, { error: 'item_not_found' });
      const source = buildObjectIntelligenceSource(item as ObjectIntelligenceItem);
      const fingerprint = source ? await objectIntelligenceFingerprint(source) : undefined;
      const intelligence = source && fingerprint ? readObjectIntelligence(record(item.attributes)?.object_intelligence, source, fingerprint) : undefined;
      if (input.operation === 'inspect') {
        if (intelligence) return json(200, { status: 'ready', intelligence });
        if (!source) return json(200, { status: 'unavailable' });
        // Only inspect the queue after the owner-scoped item lookup succeeds.
        // No enqueue or model invocation happens when a person opens a card.
        const queued = await db.from('object_intelligence_jobs').select('status').eq('item_id', input.item_id).maybeSingle();
        if (queued.error) throw new Error('queue_read_failed');
        const status = record(queued.data)?.status;
        return json(200, { status: status === 'queued' || status === 'processing' ? 'pending' : 'unavailable' });
      }
      if (fingerprint && input.source_fingerprint !== fingerprint) return json(409, { error: 'source_changed' });
      if (!intelligence) return json(409, { error: 'intelligence_unavailable' });
      const capability = intelligence.capabilities.find(candidate => candidate.id === input.action);
      if (!capability || capability.status !== 'source_ready' || capability.effect !== 'draft' || capability.prerequisites.length || capability.requires_confirmation) {
        return json(409, { error: 'action_unavailable' });
      }
      const denied = await requireEntitlement(user);
      if (denied) {
        const headers = new Headers(denied.headers);
        for (const [key, value] of Object.entries(objectInteractionsHeaders)) headers.set(key, value);
        headers.set('Content-Type', 'application/json');
        return new Response(denied.body, { status: denied.status, headers });
      }
      const draft = buildDraft(intelligence, input.action, input.item_id);
      if (!draft) return json(409, { error: 'action_unavailable' });
      return json(200, { draft });
    } catch {
      // Do not include provider, database, source text, IDs or auth details.
      return json(503, { error: 'object_interactions_unavailable' });
    }
  };
}
