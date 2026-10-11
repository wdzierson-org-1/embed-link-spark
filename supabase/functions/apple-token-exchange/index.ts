// supabase/functions/apple-token-exchange/index.ts
//
// Sign in with Apple hands the client a one-shot authorization code next to the identity token.
// Supabase never sees it (the id-token flow), so we exchange it here and keep Apple's refresh
// token — the only thing that lets delete-account revoke the person's Sign in with Apple grant
// later (spec §5.3). The code lives five minutes and works once, so clients call this right after
// sign-in; a failure is logged and never blocks the sign-in.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { isAgentToken } from "../_shared/agentToken.ts";
import { appleEnv, makeAppleClientSecret } from "../_shared/appleClientSecret.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_WEB_REDIRECT_URI = "https://www.gostash.it/auth";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: "Missing authorization token" });
  if (isAgentToken(token)) return json(403, { error: "Agent tokens are refused here" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return json(401, { error: "Invalid or expired token" });

  let body: { code?: unknown; client?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "JSON body required" });
  }
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const client = body.client === "web" || body.client === "ios" ? body.client : null;
  if (!code || !client) return json(400, { error: "code and client ('web' | 'ios') are required" });

  const env = appleEnv();
  const clientId = client === "web" ? env.servicesId : env.bundleId;
  const clientSecret = await makeAppleClientSecret({ teamId: env.teamId, keyId: env.keyId, clientId, privateKeyPem: env.privateKeyPem });
  const form = new URLSearchParams({ client_id: clientId, client_secret: clientSecret, code, grant_type: "authorization_code" });
  if (client === "web") form.set("redirect_uri", APPLE_WEB_REDIRECT_URI);

  const res = await fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const data = (await res.json().catch(() => ({}))) as { refresh_token?: unknown; error?: unknown };
  if (!res.ok || typeof data.refresh_token !== "string") {
    console.warn(`[APPLE-TOKEN-EXCHANGE] apple ${res.status} ${JSON.stringify(data).slice(0, 200)}`);
    return json(502, { stored: false, error: typeof data.error === "string" ? data.error : `apple ${res.status}` });
  }

  const { error } = await admin
    .from("apple_sign_in_tokens")
    .upsert({ user_id: user.id, client_id: clientId, refresh_token: data.refresh_token }, { onConflict: "user_id,client_id" });
  if (error) return json(500, { stored: false, error: error.message });
  return json(200, { stored: true });
});
