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
import { appleReadiness } from "../_shared/appleRevocation.ts";

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
  if (req.method !== "POST" && req.method !== "GET") return json(405, { error: "GET or POST only" });

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
  // A try-stash guest has no Apple grant of its own to keep: a successful Apple sign-in replaces
  // that session before any client calls this.
  if ((user as { is_anonymous?: boolean }).is_anonymous) return json(403, { error: "anonymous" });

  // Readiness (2026-10-12, AS-APPLE-REVOCATION): will deletion have anything to revoke? Native
  // calls this before delete-account and re-authorizes with Apple first when
  // `apple_identity && !stored`. Reports audiences and dates only — never a token.
  if (req.method === "GET") {
    const { data, error } = await admin.from("apple_sign_in_tokens").select("client_id, created_at").eq("user_id", user.id);
    if (error) return json(503, { error: "apple_tokens_unavailable", retryable: true });
    const identities = (user as { identities?: Array<{ provider?: string }> }).identities;
    return json(200, appleReadiness((data ?? []) as Array<{ client_id: string; created_at: string }>, identities, Deno.env.get("APPLE_BUNDLE_ID") ?? null));
  }

  // Unparseable JSON and a JSON null both arrive as {}, so they meet the same 400 below
  const body = ((await req.json().catch(() => null)) ?? {}) as { code?: unknown; client?: unknown };
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const client = body.client === "web" || body.client === "ios" ? body.client : null;
  if (!code || !client) return json(400, { error: "code and client ('web' | 'ios') are required" });

  // From here on anything can throw (a missing Apple secret, an unusable key, Apple unreachable).
  // Answer with JSON and the CORS headers, like delete-account, not the runtime's bare 500.
  try {
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
      // Never log Apple's body: on a 2xx without a refresh token it carries access and id tokens.
      const reason = typeof data.error === "string" ? data.error : null;
      console.warn(`[APPLE-TOKEN-EXCHANGE] apple ${res.status} ${reason ?? "no refresh_token"}`);
      return json(502, { stored: false, error: reason ?? `apple ${res.status}` });
    }

    const { error } = await admin
      .from("apple_sign_in_tokens")
      .upsert({ user_id: user.id, client_id: clientId, refresh_token: data.refresh_token }, { onConflict: "user_id,client_id" });
    if (error) {
      console.warn("[APPLE-TOKEN-EXCHANGE] store failed", error.message); // the message only: the row holds the refresh token
      return json(500, { stored: false, error: error.message });
    }
    return json(200, { stored: true });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.warn("[APPLE-TOKEN-EXCHANGE] failed", message);
    return json(500, { stored: false, error: message });
  }
});
