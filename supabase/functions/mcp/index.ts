// supabase/functions/mcp/index.ts — TEMPORARY spike stub (Task 1). Replaced in Task 6.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  const url = new URL(req.url);
  const body = req.method === 'POST' ? await req.text() : null;
  return new Response(JSON.stringify({
    spike: true,
    method: req.method,
    path: url.pathname,
    hasAuthorization: req.headers.has('authorization'),
    contentType: req.headers.get('content-type'),
    body,
  }), { status: 200, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
});
