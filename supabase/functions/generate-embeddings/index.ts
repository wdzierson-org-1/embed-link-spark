import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { requireItemAccess } from '../_shared/enrichmentAuth.ts';
import { ENRICHMENT_COLUMNS } from '../_shared/enrichmentStore.ts';
import { rebuildItemIndex } from '../_shared/enrichmentIndex.ts';
const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json' };
serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return new Response('POST only', { status: 405, headers });
  try {
    const { itemId } = await req.json();
    if (typeof itemId !== 'string') return new Response(JSON.stringify({ error: 'itemId required' }), { status: 400, headers });
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let item;
    try { item = await requireItemAccess(req, db, itemId, ENRICHMENT_COLUMNS); }
    catch { return new Response(JSON.stringify({ error: 'Item not found or access denied' }), { status: 403, headers }); }
    const key = Deno.env.get('OPENAI_API_KEY');
    if (!key) throw new Error('Embedding provider not configured');
    // Legacy textContent is accepted but ignored: always embed the current, validated saved object.
    const result = await rebuildItemIndex(db, item, key);
    // `{ success: false, reason: 'item_changed' }` is not a failure: the row changed while it was
    // being embedded and whoever changed it re-indexes. It used to answer 409, which every
    // browser logs in red on each racing save (2026-10-09); the body carries the outcome.
    return new Response(JSON.stringify(result), { status: 200, headers });
  } catch (error) {
    console.error('generate-embeddings failed', error);
    return new Response(JSON.stringify({ error: 'Embedding generation failed' }), { status: 500, headers });
  }
});
