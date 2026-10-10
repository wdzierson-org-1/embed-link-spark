import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { extractPage } from '../_shared/pageExtraction.ts';
import { requireItemAccess } from '../_shared/enrichmentAuth.ts';
import { applyCandidate, ENRICHMENT_COLUMNS } from '../_shared/enrichmentStore.ts';
import { isPlaceholderMetadata } from '../_shared/enrichmentQuality.ts';
import { deriveTitleFromContent, generateSummary } from '../_shared/summarize.ts';
import { recoverCapturedPreview } from '../_shared/capturedPreview.ts';
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
    // extractOnly writes nothing and returns what each adapter answered, for diagnosis
    const trace: string[] = [];
    const capture = await extractPage(
      url,
      { firecrawl: Deno.env.get('FIRECRAWL_API_KEY'), tiktok: Deno.env.get('TIKTOK_SCRAPE_API_KEY'), reels: Deno.env.get('REELS_SCRAPE_API_KEY') },
      extractOnly ? trace : undefined,
    );
    if (!capture) return json({ success: false, reason: 'No usable source content', ...(extractOnly ? { trace } : {}) });
    if (extractOnly) return json({ success: true, ...capture, trace });
    // Never replace a transcript already recovered by maintenance with a shorter page caption.
    if (item.attributes?.enrichment?.evidence?.transcript) return json({ success: true, reason: 'richer_content_preserved' });
    const patch: Record<string, string> = { page_body: capture.text };
    // A video's transcript is its content (spec 2026-09-05): summarized as a recording, and the
    // video's own description replaces the synthetic "Watch … on YouTube" line.
    const isTranscript = capture.kind === 'transcript';
    if (isTranscript && capture.facts?.description && (isPlaceholderMetadata(item.description, url) || /\bon youtube$/i.test(item.description ?? ''))) {
      patch.description = capture.facts.description;
    }
    const key = Deno.env.get('OPENAI_API_KEY');
    if (key) {
      if (isPlaceholderMetadata(item.title, url)) {
        const title = await deriveTitleFromContent(key, capture.text, url);
        if (title && !isPlaceholderMetadata(title, url)) patch.title = title;
      }
      const summary = await generateSummary(key, { sourceText: capture.text, kind: isTranscript ? 'video' : 'link', title: patch.title || item.title, url });
      if (summary) {
        patch.summary = summary;
        if (!patch.description && isPlaceholderMetadata(item.description, url)) patch.description = summary.slice(0, 350);
      }
    }
    // Finish fallible model work before creating an object to attach. A thrown
    // patch call remains ambiguous; never delete an image it may have saved.
    const recoveredPreview = isTranscript ? null : await recoverCapturedPreview(db, item, capture.text);
    if (recoveredPreview) patch.file_path = recoveredPreview.path;
    // `evidence.transcript` is the one flag every client reads for "page_body is a transcript"
    // (the maintenance loop's social adapter sets the same one)
    const evidence: Record<string, unknown> = { capture_kind: capture.kind };
    if (isTranscript) {
      evidence.transcript = true;
      evidence.transcript_source = capture.source;
      if (capture.facts?.language) evidence.language = capture.facts.language;
      if (capture.facts?.durationS) evidence.duration_s = capture.facts.durationS;
      if (capture.facts?.author) evidence.author = capture.facts.author;
    }
    const applied = await applyCandidate(db, item, patch, capture.source, evidence);
    if (!applied) {
      // Another write won the item snapshot; discard only our new upload.
      if (recoveredPreview) await db.storage.from('stash-media').remove([recoveredPreview.path]);
      return json({ success: false, reason: 'item_changed' });
    }
    const { data, error } = await db.functions.invoke('generate-embeddings', { body: { itemId } });
    return json({ success: !error && data?.success === true, contentLength: capture.text.length, indexed: !error && data?.success === true });
  } catch (error) {
    console.error('scrape-page-content failed', error);
    return json({ success: false, reason: 'Extraction failed' }, 500);
  }
});
