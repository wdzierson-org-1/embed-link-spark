// supabase/functions/_shared/agentAuth.ts
//
// Authentication for the mcp function only. Order matters:
//   1. bearer token present
//   2. Supabase verifies it (signature, expiry, session still alive — a grant
//      revoked through Supabase kills the session, so revoked tokens die here)
//   3. token carries client_id (issued through the OAuth server, not a
//      person's session — every agent request must be attributable)
//   4. our agent_grants row for (user, client) exists and is not revoked
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { agentClientId, bearerToken } from './agentToken.ts';

export interface AgentGrant {
  id: string;
  user_id: string;
  client_id: string;
  client_name: string;
  scopes: string[];
  revoked_at: string | null;
}

export type AgentAuthResult =
  | { ok: true; user: { id: string; email?: string }; grant: AgentGrant; supabaseAdmin: ReturnType<typeof createClient> }
  | { ok: false; status: 401 | 403; error: string; description: string };

export async function authenticateAgent(authHeader: string | null): Promise<AgentAuthResult> {
  const token = bearerToken(authHeader);
  if (!token) {
    return { ok: false, status: 401, error: 'missing_token', description: 'Missing bearer token' };
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) throw new Error('Supabase configuration missing');
  const supabaseAdmin = createClient(supabaseUrl, serviceKey);

  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) {
    return { ok: false, status: 401, error: 'invalid_token', description: 'Token is invalid, expired, or revoked' };
  }

  const clientId = agentClientId(token);
  if (!clientId) {
    return {
      ok: false, status: 401, error: 'invalid_token',
      description: 'Stash MCP accepts only tokens issued through Connect an agent (OAuth), not session tokens',
    };
  }

  const { data: grant, error: grantError } = await supabaseAdmin
    .from('agent_grants')
    .select('id, user_id, client_id, client_name, scopes, revoked_at')
    .eq('user_id', user.id)
    .eq('client_id', clientId)
    .maybeSingle();
  if (grantError) {
    console.error('agent_grants lookup failed:', grantError);
    throw new Error('Grant lookup failed');
  }
  if (!grant || grant.revoked_at) {
    return {
      ok: false, status: 403, error: 'insufficient_scope',
      description: "This agent's access to your stash was revoked or never granted. Reconnect it from Settings → Connected agents at gostash.it.",
    };
  }

  return { ok: true, user: { id: user.id, email: user.email ?? undefined }, grant: grant as AgentGrant, supabaseAdmin };
}
