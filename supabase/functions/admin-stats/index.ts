import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { authenticateUser } from '../_shared/auth.ts';
import { ADMIN_ITEM_COLUMNS, parseAdminRequest } from '../_shared/adminDashboard.ts';

// Temporary admin dashboard backend
// (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
//
// Every call: verify the JWT, require an admin_users row for that user, then
// serve one of two read-only views with the service role:
//   { action: 'users' }                 → every account with sign-in + saving stats
//   { action: 'items', user_id: uuid }  → that member's library, as the grid loads it
// Each admin read is logged (who looked at whom). Switch the feature off with
// `DELETE FROM public.admin_users;` — this function then answers 403 to everyone.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'POST only' });

  let user, supabaseAdmin;
  try {
    ({ user, supabaseAdmin } = await authenticateUser(req.headers.get('Authorization')));
  } catch (error) {
    return json(401, { error: error instanceof Error ? error.message : 'Authentication failed' });
  }

  const { data: adminRow, error: adminError } = await supabaseAdmin
    .from('admin_users')
    .select('user_id')
    .eq('user_id', user.id)
    .maybeSingle();
  if (adminError) {
    console.error('[ADMIN-STATS] admin check failed', adminError);
    return json(500, { error: 'Admin check failed' });
  }
  if (!adminRow) {
    console.warn('[ADMIN-STATS] refused non-admin', { userId: user.id });
    return json(403, { error: 'Not an admin' });
  }

  let body: unknown = null;
  try {
    body = await req.json();
  } catch {
    // no/invalid JSON body — parseAdminRequest reports "unknown action"
  }
  const request = parseAdminRequest(body);
  if ('error' in request) return json(400, { error: request.error });

  if (request.action === 'users') {
    const { data, error } = await supabaseAdmin.rpc('admin_user_stats');
    if (error) {
      console.error('[ADMIN-STATS] admin_user_stats failed', error);
      return json(500, { error: error.message });
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
    console.error('[ADMIN-STATS] items failed', itemsError);
    return json(500, { error: itemsError.message });
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
});
