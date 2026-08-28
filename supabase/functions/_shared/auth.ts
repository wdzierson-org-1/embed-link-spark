import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

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

  return { user, supabaseAdmin };
}
