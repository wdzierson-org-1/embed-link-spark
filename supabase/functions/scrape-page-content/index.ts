import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

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

const decodeEntities = (text: string): string =>
  text
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'");

const scrapeWithPlainFetch = async (url: string): Promise<string | null> => {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15_000);

  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    });

    if (!response.ok) {
      console.error('Plain fetch failed:', response.status);
      return null;
    }

    const html = await response.text();

    // Strip non-content blocks, then all tags, then normalize
    const text = html
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ')
      .replace(/<(nav|footer|header|aside|form)[\s\S]*?<\/\1>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<[^>]+>/g, ' ');

    return decodeEntities(text).replace(/\s+/g, ' ').trim();
  } catch (error) {
    console.error('Plain fetch scrape failed:', error);
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
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
    if (firecrawlApiKey) {
      content = await scrapeWithFirecrawl(url, firecrawlApiKey);
    }
    if (!content || content.trim().length < MIN_CONTENT_LENGTH) {
      content = await scrapeWithPlainFetch(url);
    }

    if (!content || content.trim().length < MIN_CONTENT_LENGTH) {
      console.log('Scrape produced insufficient content, skipping update');
      return new Response(
        JSON.stringify({ success: false, reason: 'Insufficient content returned' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const trimmedContent = content.trim().slice(0, MAX_BODY_LENGTH);
    console.log('Scraped content length:', trimmedContent.length, 'for item:', itemId);

    const { data: updatedItem, error: updateError } = await supabase
      .from('items')
      .update({ page_body: trimmedContent })
      .eq('id', itemId)
      .select('title, description, content, supplemental_note, url')
      .single();

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
      updatedItem?.title,
      updatedItem?.description,
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
