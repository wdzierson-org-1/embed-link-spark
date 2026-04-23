import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const MAX_BODY_LENGTH = 50_000;
const MIN_CONTENT_LENGTH = 100;

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

    if (!firecrawlApiKey) {
      console.error('FIRECRAWL_API_KEY not set');
      return new Response(
        JSON.stringify({ success: false, reason: 'FIRECRAWL_API_KEY not configured' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Call Firecrawl API with a 30s timeout
    let markdown: string | null = null;
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 30_000);

      const firecrawlResponse = await fetch('https://api.firecrawl.dev/v1/scrape', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${firecrawlApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          url,
          formats: ['markdown'],
          onlyMainContent: true,
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!firecrawlResponse.ok) {
        const errorText = await firecrawlResponse.text();
        console.error('Firecrawl API error:', firecrawlResponse.status, errorText);
        return new Response(
          JSON.stringify({ success: false, reason: `Firecrawl error: ${firecrawlResponse.status}` }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const firecrawlData = await firecrawlResponse.json();
      markdown = firecrawlData?.data?.markdown ?? null;
    } catch (fetchError) {
      console.error('Firecrawl fetch failed (non-fatal):', fetchError);
      return new Response(
        JSON.stringify({ success: false, reason: 'Firecrawl request failed' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!markdown || markdown.trim().length < MIN_CONTENT_LENGTH) {
      console.log('Firecrawl returned insufficient content (length:', markdown?.length ?? 0, '), skipping update');
      return new Response(
        JSON.stringify({ success: false, reason: 'Insufficient content returned' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Trim to max length
    const trimmedMarkdown = markdown.trim().slice(0, MAX_BODY_LENGTH);
    console.log('Scraped content length:', trimmedMarkdown.length, 'for item:', itemId);

    // Update items row with scraped content
    const { error: updateError } = await supabase
      .from('items')
      .update({ page_body: trimmedMarkdown })
      .eq('id', itemId);

    if (updateError) {
      console.error('Error updating page_body:', updateError);
      return new Response(
        JSON.stringify({ success: false, reason: 'DB update failed' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('page_body updated, generating embeddings for item:', itemId);

    // Fire-and-forget: regenerate embeddings with the richer content
    supabase.functions.invoke('generate-embeddings', {
      body: {
        itemId,
        textContent: trimmedMarkdown,
      },
    }).catch((err: unknown) => {
      console.error('generate-embeddings invocation failed (non-fatal):', err);
    });

    return new Response(
      JSON.stringify({ success: true, contentLength: trimmedMarkdown.length }),
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
