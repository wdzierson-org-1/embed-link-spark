import { parseLeasePath, prepareModelRequest } from './policy.mjs';

const json = (status: number, error: string) => new Response(JSON.stringify({ error: { message: error, type: 'quality_proxy_error' } }), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

// This credential is one expiring job lease, never a deployment or provider key.
// The model provider key remains inside Stash's existing Supabase project.
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, 'method_not_allowed');
  if (Deno.env.get('QUALITY_ENABLED') !== 'true') return json(503, 'quality_disabled');
  const lease = parseLeasePath(new URL(req.url).pathname);
  const token = req.headers.get('authorization')?.match(/^Bearer ([0-9a-f-]{36})$/i)?.[1];
  if (!lease || !token) return json(401, 'invalid_lease');
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!apiKey || !supabaseUrl || !serviceKey) return json(503, 'provider_unconfigured');
  try {
    const reader = req.body?.getReader();
    if (!reader) return json(400, 'body_required');
    const chunks: Uint8Array[] = [];
    let bytes = 0;
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.length;
      if (bytes > 131072) { await reader.cancel(); return json(413, 'body_too_large'); }
      chunks.push(value);
    }
    const buffer = new Uint8Array(bytes);
    let offset = 0;
    for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.length; }
    let body;
    try { body = prepareModelRequest(JSON.parse(new TextDecoder().decode(buffer)), 'gpt-4.1'); }
    catch { return json(400, 'invalid_model_request'); }
    const authorization = await fetch(`${supabaseUrl}/rest/v1/rpc/quality_authorize_model`, {
      method: 'POST', headers: { authorization: `Bearer ${serviceKey}`, apikey: serviceKey, 'content-type': 'application/json' },
      body: JSON.stringify({ target_id: lease.id, token, expected_fence: lease.fence }), signal: AbortSignal.timeout(5000),
    });
    if (!authorization.ok) return json(503, 'lease_check_unavailable');
    const budget = await authorization.json();
    if (!budget.ok) return json(budget.error === 'model_budget_exhausted' ? 429 : 409, budget.error === 'model_budget_exhausted' ? 'model_budget_exhausted' : 'lease_lost');
    const provider = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST', headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify(body), signal: AbortSignal.any([req.signal, AbortSignal.timeout(45000)]),
    });
    if (!provider.ok) {
      await provider.body?.cancel();
      return json(provider.status === 429 ? 429 : 502, 'model_provider_failed');
    }
    return new Response(provider.body, { headers: { 'content-type': body.stream ? 'text/event-stream' : 'application/json', 'cache-control': 'no-store' } });
  } catch {
    return json(502, 'model_request_failed');
  }
});
