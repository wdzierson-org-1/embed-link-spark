import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { isAgentToken } from './agentToken.ts';

export const AGENT_TOKEN_REJECTED = 'Authentication failed: agent tokens are only accepted by the MCP endpoint';

// Agent (OAuth-client) tokens may only enter through the mcp function, where
// grants, scopes, rate limits and the activity log apply. Every other
// endpoint refuses them — the second half of the "answers, never copies"
// fence (the first half is the RLS policies in the 20260905120000 migration).
// Accepts either a raw token or a full "Bearer …" header.
export function assertNotAgentToken(tokenOrHeader: string | null | undefined): void {
  const token = tokenOrHeader?.replace(/^Bearer\s+/i, '').trim();
  if (token && isAgentToken(token)) {
    throw new Error(AGENT_TOKEN_REJECTED);
  }
}

// Verify the caller's Supabase JWT, then hand back a service-role client.
// Tenancy is enforced by the edge function passing the verified user.id into
// user-scoped queries/RPCs — never by trusting ids from the request body.
export async function authenticateUser(authHeader: string | null) {
  if (!authHeader) {
    throw new Error('No authorization header');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Supabase configuration missing');
  }

  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
  const token = authHeader.replace('Bearer ', '');

  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);

  if (userError || !user) {
    console.error('Authentication error:', userError);
    throw new Error('Authentication failed');
  }

  assertNotAgentToken(token);

  return { user, supabaseAdmin };
}
