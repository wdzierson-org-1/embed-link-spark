import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { authenticateUser } from '../_shared/auth.ts';
import { ADMIN_ITEM_COLUMNS, parseAdminRequest } from '../_shared/adminDashboard.ts';

// Admin dashboard backend. All actions verify a JWT and current admin membership.
//
// Every call: verify the JWT, require an admin_users row for that user, then
// serve the account/library views and a bounded enrichment quality view:
//   { action: 'users' }                 → every account with sign-in + saving stats
//   { action: 'items', user_id: uuid }  → that member's library, as the grid loads it
//   { action: 'enrichment', ... }       → fleet metrics, failures and proposals
//   { action: 'review_proposal', ... }  → append a triage note with revision CAS
// Enrichment RPCs also check admin membership inside their transaction. Review
// writes never change worker evidence or publish an enrichment strategy.
// Each admin read is logged (who looked at whom). Switch the feature off with
// `DELETE FROM public.admin_users;` — this function then answers 403 to everyone.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });

async function boundedBody(req: Request): Promise<unknown> {
  const reader = req.body?.getReader();
  if (!reader) throw new Error('invalid_json');
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > 16_384) { await reader.cancel(); throw new Error('body_too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

// Log only a constrained error code. PostgREST messages/details can include SQL
// arguments or private source text and must not reach responses or edge logs.
function databaseFailure(operation: string, error: { code?: string } | null) {
  const code = typeof error?.code === 'string' && /^[A-Z0-9]{5}$/.test(error.code) ? error.code : 'unknown';
  console.error('[ADMIN-STATS] database request failed', { operation, code });
  if (code === '42501') return json(403, { error: 'Not an admin' });
  if (code === '22023') return json(400, { error: 'Invalid request' });
  return json(500, { error: 'Admin request failed' });
}

async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  let user, supabaseAdmin;
  try {
    ({ user, supabaseAdmin } = await authenticateUser(req.headers.get('Authorization')));
  } catch {
    return json(401, { error: 'Authentication failed' });
  }

  const { data: adminRow, error: adminError } = await supabaseAdmin
    .from('admin_users')
    .select('user_id')
    .eq('user_id', user.id)
    .maybeSingle();
  if (adminError) {
    console.error('[ADMIN-STATS] admin check failed');
    return json(500, { error: 'Admin check failed' });
  }
  if (!adminRow) {
    console.warn('[ADMIN-STATS] refused non-admin', { userId: user.id });
    return json(403, { error: 'Not an admin' });
  }

  let body: unknown = null;
  try {
    body = await boundedBody(req);
  } catch (error) {
    if (error instanceof Error && error.message === 'body_too_large') return json(413, { error: 'Request too large' });
    // no/invalid JSON body — parseAdminRequest reports "unknown action"
  }
  const request = parseAdminRequest(body);
  if ('error' in request) return json(400, { error: request.error });

  if (request.action === 'enrichment') {
    const { data, error } = await supabaseAdmin.rpc('admin_enrichment_quality', {
      actor_user_id: user.id,
      lookback_hours: request.lookbackHours,
      proposal_status: request.proposalStatus,
      proposal_limit: request.proposalLimit,
    });
    if (error) return databaseFailure('admin_enrichment_quality', error);
    if (!data || typeof data !== 'object' || Array.isArray(data)) return databaseFailure('admin_enrichment_quality', null);
    console.log('[ADMIN-STATS] enrichment', { admin: user.id, lookbackHours: request.lookbackHours });
    return json(200, data);
  }

  if (request.action === 'review_proposal') {
    const { data, error } = await supabaseAdmin.rpc('review_hosted_quality_proposal', {
      actor_user_id: user.id,
      target_id: request.proposalId,
      expected_revision: request.expectedRevision,
      new_status: request.newStatus,
      review_note: request.reviewNote,
      request_id: request.requestId,
    });
    if (error) return databaseFailure('review_hosted_quality_proposal', error);
    if (data?.ok === true) {
      console.log('[ADMIN-STATS] review_proposal', { admin: user.id, proposal: request.proposalId, status: request.newStatus });
      return json(200, data);
    }
    if (data?.ok === false && data.error === 'not_found') return json(404, data);
    if (data?.ok === false && ['version_conflict', 'request_conflict'].includes(data.error)) return json(409, data);
    return databaseFailure('review_hosted_quality_proposal', null);
  }

  if (request.action === 'users') {
    const { data, error } = await supabaseAdmin.rpc('admin_user_stats');
    if (error) {
      return databaseFailure('admin_user_stats', error);
    }
    console.log('[ADMIN-STATS] users', { admin: user.id, rows: data?.length ?? 0 });
    return json(200, { users: data ?? [] });
  }

  const { data: target, error: targetError } = await supabaseAdmin.auth.admin.getUserById(request.userId);
  if (targetError || !target?.user) return json(404, { error: 'No such user' });

  const { data: profile } = await supabaseAdmin
    .from('user_profiles')
    .select('username, display_name')
    .eq('id', request.userId)
    .maybeSingle();

  const { data: items, error: itemsError } = await supabaseAdmin
    .from('items')
    .select(ADMIN_ITEM_COLUMNS.join(','))
    .eq('user_id', request.userId)
    .order('created_at', { ascending: false });
  if (itemsError) {
    return databaseFailure('items', itemsError);
  }

  console.log('[ADMIN-STATS] items', { admin: user.id, target: request.userId, rows: items?.length ?? 0 });
  return json(200, {
    user: {
      user_id: target.user.id,
      email: target.user.email ?? null,
      username: profile?.username ?? null,
      display_name: profile?.display_name ?? null,
      created_at: target.user.created_at,
    },
    items: items ?? [],
  });
}

serve((req) => handle(req).catch(() => {
  console.error('[ADMIN-STATS] unexpected request failure');
  return json(500, { error: 'Admin request failed' });
}));
