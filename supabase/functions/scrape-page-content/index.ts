import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { extractPage } from '../_shared/pageExtraction.ts';
import { requireItemAccess } from '../_shared/enrichmentAuth.ts';
import { applyCandidate, ENRICHMENT_COLUMNS } from '../_shared/enrichmentStore.ts';
import { isPlaceholderMetadata } from '../_shared/enrichmentQuality.ts';
import { deriveTitleFromContent, generateSummary } from '../_shared/summarize.ts';
import { recoverCapturedPreview } from '../_shared/capturedPreview.ts';
import { isTikTokVideoUrl, resolveTikTokLink } from '../_shared/tiktok.ts';
import { creatorEvidence } from '../_shared/socialEnrichment.ts';
import { isPlaceCandidate, runPlaceStep } from '../_shared/placeEnrichment.ts';

const TIKTOK_SHORT_LINK = /tiktok\.com\/t\/|\/\/(vm|vt)\.tiktok\.com\//i;
const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Content-Type': 'application/json' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
  try {
    // `caption`: the video's own words as the saver already knew them (add-url's oEmbed caption,
    // which sat in page_body until the transcript takes that place)
    const { itemId, url, extractOnly = false, caption } = await req.json();
    if (!itemId || !url) return json({ error: 'itemId and url required' }, 400);
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let item;
    try { item = await requireItemAccess(req, db, itemId, ENRICHMENT_COLUMNS); }
    catch { return json({ error: 'Item not found or access denied' }, 403); }
    if (item.url !== url || item.type !== 'link') return json({ error: 'Source does not match item' }, 400);
    // A map-provider address, or a listing page with coordinates, is a place: after the
    // body is captured (or found missing) the place step keeps its facts and renders its map.
    // It runs under its own fresh snapshot, so it always goes last. Never fatal to the scrape.
    // Its outcome rides on the response as `place`, for diagnosis (never the facts themselves)
    let placeOutcome: Record<string, unknown> | null = null;
    const placeStep = async () => {
      if (extractOnly || !isPlaceCandidate(url, item.attributes)) return;
      try {
        const outcome = await runPlaceStep(db, itemId, url, { mapboxToken: Deno.env.get('MAPBOX_ACCESS_TOKEN'), firecrawlKey: Deno.env.get('FIRECRAWL_API_KEY') });
        placeOutcome = 'skipped' in outcome
          ? { skipped: outcome.skipped, ...(outcome.detail ?? {}) }
          : { kept: true, map: outcome.map ?? null, method: outcome.place.evidence.method, resolved: outcome.place.provider.url, hours: outcome.place.hours?.length ?? 0 };
        console.log('place step', itemId, JSON.stringify(placeOutcome));
      } catch (error) {
        placeOutcome = { error: error instanceof Error ? error.message : String(error) };
        console.error('place step failed', itemId, error);
      }
    };
    // extractOnly writes nothing and returns what each adapter answered, for diagnosis
    const trace: string[] = [];
    const capture = await extractPage(
      url,
      { firecrawl: Deno.env.get('FIRECRAWL_API_KEY'), tiktok: Deno.env.get('TIKTOK_SCRAPE_API_KEY'), reels: Deno.env.get('REELS_SCRAPE_API_KEY') },
      extractOnly ? trace : undefined,
    );
    // A TikTok share short link carries no video id: record the address it resolves to, so the
    // panel can frame the video. add-url writes the same fact as link.canonical_url for API
    // saves; web saves only pass through here, and enrichment can only add evidence.
    // Preserve the explicit creator fields from that same lookup with no extra request.
    const resolvedEvidence: Record<string, unknown> = {};
    if (!extractOnly && isTikTokVideoUrl(url) && TIKTOK_SHORT_LINK.test(url) && !item.attributes?.link?.canonical_url && !item.attributes?.enrichment?.evidence?.canonical_url) {
      try {
        const resolved = await resolveTikTokLink(url);
        if (resolved) {
          if (resolved.canonicalUrl && resolved.canonicalUrl !== url) resolvedEvidence.canonical_url = resolved.canonicalUrl;
          Object.assign(resolvedEvidence, creatorEvidence('tiktok', {
            name: resolved.authorName, handle: resolved.authorHandle, url: resolved.authorUrl,
          }));
        }
      } catch (error) {
        console.warn('tiktok canonical resolution failed', url, error);
      }
    }
    if (!capture) {
      if (Object.keys(resolvedEvidence).length && !await applyCandidate(db, item, {}, 'tiktok-canonical', resolvedEvidence)) {
        return json({ success: false, reason: 'item_changed' });
      }
      // A map provider's page often yields no body worth keeping; the place itself still does
      await placeStep();
      return json({ success: false, reason: 'No usable source content', ...(extractOnly ? { trace } : {}), ...(placeOutcome ? { place: placeOutcome } : {}) });
    }
    if (extractOnly) return json({ success: true, ...capture, trace });
    // Never replace a transcript already recovered by maintenance with a shorter page caption.
    if (item.attributes?.enrichment?.evidence?.transcript) {
      if (Object.keys(resolvedEvidence).length && !await applyCandidate(db, item, {}, 'tiktok-canonical', resolvedEvidence)) {
        return json({ success: false, reason: 'item_changed' });
      }
      await placeStep();
      return json({ success: true, reason: 'richer_content_preserved', ...(placeOutcome ? { place: placeOutcome } : {}) });
    }
    const patch: Record<string, string> = { page_body: capture.text };
    // A video's transcript is its content (spec 2026-09-05): summarized as a recording, and the
    // video's own description replaces the synthetic "Watch … on YouTube" line.
    const isTranscript = capture.kind === 'transcript';
    const synthetic = isPlaceholderMetadata(item.description, url) || /\bon youtube$/i.test(item.description ?? '');
    if (isTranscript && synthetic) {
      const own = capture.facts?.description || (typeof caption === 'string' ? caption.replace(/\s+/g, ' ').trim().slice(0, 350) : '');
      if (own) patch.description = own;
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
    // Merge creator and body evidence in one write: changing attributes first
    // would invalidate the original item snapshot used by applyCandidate.
    const evidence: Record<string, unknown> = { ...resolvedEvidence, capture_kind: capture.kind };
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
    await placeStep();
    const { data, error } = await db.functions.invoke('generate-embeddings', { body: { itemId } });
    return json({ success: !error && data?.success === true, contentLength: capture.text.length, indexed: !error && data?.success === true, ...(placeOutcome ? { place: placeOutcome } : {}) });
  } catch (error) {
    console.error('scrape-page-content failed', error);
    return json({ success: false, reason: 'Extraction failed' }, 500);
  }
});
