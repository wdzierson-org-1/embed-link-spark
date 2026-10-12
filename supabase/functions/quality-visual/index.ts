import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { createVisualHandler } from './handler.ts';

const options = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };
const url = Deno.env.get('SUPABASE_URL')!;
// Service operations and password-authenticated captures never share a client.
const db = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, options);
const captureClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, options);
serve(createVisualHandler({ db, auth: captureClient.auth, env: name => Deno.env.get(name) }));
