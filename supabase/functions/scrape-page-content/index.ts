import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import {
  CRAWLER_UA,
  fetchHtml,
  fetchViaJinaReader,
  fetchViaWayback,
  htmlToText,
  isBlockedPageTitle,
  looksBlocked,
} from '../_shared/blockedContentFallbacks.ts';
import { deriveTitleFromContent, generateSummary } from '../_shared/summarize.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const MAX_BODY_LENGTH = 50_000;
const MIN_CONTENT_LENGTH = 100;

// Firecrawl (when configured) produces cleaner article extraction; the plain
// fetch fallback keeps page_body working without it.
const scrapeWithFirecrawl = async (url: string, apiKey: string): Promise<string | null> => {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30_000);

  try {
    const response = await fetch('https://api.firecrawl.dev/v1/scrape', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ url, formats: ['markdown'], onlyMainContent: true }),
      signal: controller.signal,
    });

    if (!response.ok) {
      console.error('Firecrawl API error:', response.status, await response.text());
      return null;
    }

    const data = await response.json();
    return data?.data?.markdown ?? null;
  } catch (error) {
    console.error('Firecrawl fetch failed:', error);
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
};

const BROWSER_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const usable = (text: string | null): text is string =>
  Boolean(text && text.length >= MIN_CONTENT_LENGTH && !looksBlocked(text));

// A title that never got past the wall: challenge-page boilerplate, the bare
// hostname, or the raw URL. A user-written title never matches these, so
// replacing one is always an upgrade.
const isRescuableTitle = (title: string | null | undefined, url: string): boolean => {
  const t = (title ?? '').trim();
  if (!t) return true;
  if (isBlockedPageTitle(t)) return true;
  if (t === url) return true;
  try {
    const hostname = new URL(url).hostname.toLowerCase();
    const normalized = t.toLowerCase();
    return normalized === hostname || normalized === hostname.replace(/^www\./, '');
  } catch {
    return false;
  }
};

// Escalating extraction: direct fetch → crawler UA → Jina Reader → Wayback.
// Sites like Medium block the first two; the reader proxy or the archive
// almost always still gets the content.
const scrapeWithCascade = async (url: string): Promise<{ text: string; source: string } | null> => {
  const directHtml = await fetchHtml(url, BROWSER_UA, 15_000);
  if (directHtml) {
    const text = htmlToText(directHtml);
    if (usable(text)) return { text, source: 'direct-fetch' };
  }

  const crawlerHtml = await fetchHtml(url, CRAWLER_UA, 10_000);
  if (crawlerHtml) {
    const text = htmlToText(crawlerHtml);
    if (usable(text)) return { text, source: 'crawler-ua' };
  }

  const jinaResult = await fetchViaJinaReader(url);
  if (jinaResult?.content && usable(jinaResult.content)) {
    return { text: jinaResult.content, source: 'jina-reader' };
  }

  const waybackHtml = await fetchViaWayback(url);
  if (waybackHtml) {
    const text = htmlToText(waybackHtml);
    if (usable(text)) return { text, source: 'wayback-snapshot' };
  }

  return null;
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { itemId, url } = await req.json();
    console.log('scrape-page-content called for item:', itemId, 'url:', url);

    if (!itemId || !url) {
      return new Response(
        JSON.stringify({ error: 'itemId and url are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const firecrawlApiKey = Deno.env.get('FIRECRAWL_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    let content: string | null = null;
    let scrapeSource = 'firecrawl';
    if (firecrawlApiKey) {
      content = await scrapeWithFirecrawl(url, firecrawlApiKey);
    }
    if (!content || content.trim().length < MIN_CONTENT_LENGTH) {
      const cascadeResult = await scrapeWithCascade(url);
      content = cascadeResult?.text ?? null;
      scrapeSource = cascadeResult?.source ?? 'none';
    }

    if (!content || content.trim().length < MIN_CONTENT_LENGTH) {
      console.log('All scrape tiers failed for:', url);
      return new Response(
        JSON.stringify({ success: false, reason: 'Insufficient content returned' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const trimmedContent = content.trim().slice(0, MAX_BODY_LENGTH);
    console.log('Scraped', trimmedContent.length, 'chars via', scrapeSource, 'for item:', itemId);

    const { data: updatedItem, error: updateError } = await supabase
      .from('items')
      .update({ page_body: trimmedContent })
      .eq('id', itemId)
      .select('title, description, content, supplemental_note, url')
      .single();

    // Final review: the scrape got real content, so a title still wearing
    // challenge-page boilerplate ("Client Challenge"), the hostname, or the
    // raw URL can now be replaced with the headline the content itself carries
    let rescuedTitle: string | null = null;
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (openAIApiKey && !updateError && isRescuableTitle(updatedItem?.title, url)) {
      rescuedTitle = await deriveTitleFromContent(openAIApiKey, trimmedContent, url);
      if (rescuedTitle && !isBlockedPageTitle(rescuedTitle)) {
        const { error: titleError } = await supabase
          .from('items')
          .update({ title: rescuedTitle })
          .eq('id', itemId);
        if (titleError) {
          console.error('Error saving rescued title:', titleError);
          rescuedTitle = null;
        } else {
          console.log('Rescued junk title', JSON.stringify(updatedItem?.title), '->', rescuedTitle);
        }
      } else {
        rescuedTitle = null;
      }
    }

    // Summarize the scraped page for the edit panel's Summary tab (non-fatal)
    let summary: string | null = null;
    if (openAIApiKey && !updateError) {
      try {
        summary = await generateSummary(openAIApiKey, {
          sourceText: trimmedContent,
          kind: 'link',
          title: rescuedTitle ?? updatedItem?.title,
          url: updatedItem?.url,
        });
        if (summary) {
          const { error: summaryError } = await supabase
            .from('items')
            .update({ summary })
            .eq('id', itemId);
          if (summaryError) console.error('Error saving link summary:', summaryError);
        }
      } catch (summaryErr) {
        console.error('Link summary generation failed (non-fatal):', summaryErr);
      }
    }

    if (updateError) {
      console.error('Error updating page_body:', updateError);
      return new Response(
        JSON.stringify({ success: false, reason: 'DB update failed' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Re-embed the whole item (title/description/note + scraped body), not just
    // the body — generate-embeddings replaces prior chunks, so the embedding
    // must carry everything searchable
    const textForEmbedding = [
      rescuedTitle ?? updatedItem?.title,
      updatedItem?.description,
      summary,
      updatedItem?.content,
      updatedItem?.supplemental_note,
      updatedItem?.url,
      trimmedContent,
    ].filter(Boolean).join(' ');

    supabase.functions.invoke('generate-embeddings', {
      body: { itemId, textContent: textForEmbedding },
    }).catch((err: unknown) => {
      console.error('generate-embeddings invocation failed (non-fatal):', err);
    });

    return new Response(
      JSON.stringify({ success: true, contentLength: trimmedContent.length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Unexpected error in scrape-page-content:', error);
    return new Response(
      JSON.stringify({ success: false, reason: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
