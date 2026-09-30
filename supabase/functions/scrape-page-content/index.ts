import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { extractPage } from '../_shared/pageExtraction.ts';
import { requireItemAccess } from '../_shared/enrichmentAuth.ts';
import { applyCandidate, ENRICHMENT_COLUMNS } from '../_shared/enrichmentStore.ts';
import { isPlaceholderMetadata } from '../_shared/enrichmentQuality.ts';
import { deriveTitleFromContent, generateSummary } from '../_shared/summarize.ts';
const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
  try {
    const { itemId, url, extractOnly = false } = await req.json();
    if (!itemId || !url) return json({ error: 'itemId and url required' }, 400);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let item;
    try { item = await requireItemAccess(req, db, itemId, ENRICHMENT_COLUMNS); }
    catch { return json({ error: 'Item not found or access denied' }, 403); }
    if (item.url !== url || item.type !== 'link') return json({ error: 'Source does not match item' }, 400);
    const capture = await extractPage(url, Deno.env.get('FIRECRAWL_API_KEY'));
    if (!capture) return json({ success: false, reason: 'No usable source content' });
    if (extractOnly) return json({ success: true, ...capture });
    // Never replace a transcript already recovered by maintenance with a shorter page caption.
    if (item.attributes?.enrichment?.evidence?.transcript) return json({ success: true, reason: 'richer_content_preserved' });
    const patch: Record<string, string> = { page_body: capture.text };
    const key = Deno.env.get('OPENAI_API_KEY');
    if (key) {
      if (isPlaceholderMetadata(item.title, url)) {
        const title = await deriveTitleFromContent(key, capture.text, url);
        if (title && !isPlaceholderMetadata(title, url)) patch.title = title;
      }
      const summary = await generateSummary(key, { sourceText: capture.text, kind: 'link', title: patch.title || item.title, url });
      if (summary) {
        patch.summary = summary;
        if (isPlaceholderMetadata(item.description, url)) patch.description = summary.slice(0, 350);
      }
    }
    const applied = await applyCandidate(db, item, patch, capture.source, { capture_kind: capture.kind });
    if (!applied) return json({ success: false, reason: 'item_changed' });
    const { data, error } = await db.functions.invoke('generate-embeddings', { body: { itemId } });
    return json({ success: !error && data?.success === true, contentLength: capture.text.length, indexed: !error && data?.success === true });
  } catch (error) {
    console.error('scrape-page-content failed', error);
    return json({ success: false, reason: 'Extraction failed' }, 500);
  }
});
