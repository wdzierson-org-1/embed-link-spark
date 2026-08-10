import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { generateSummary } from '../_shared/summarize.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// On-demand summary generation: used by the edit panel's "Generate summary"
// button for items captured before summaries existed (or whose pipeline
// summary failed). New captures get their summary during ingestion.
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { itemId } = await req.json();
    if (!itemId) {
      return json({ success: false, reason: 'itemId is required' }, 400);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openAIApiKey) {
      return json({ success: false, reason: 'OpenAI API key not configured' }, 500);
    }

    // Resolve the caller from the JWT so users can only summarize their own items
    const authHeader = req.headers.get('Authorization') ?? '';
    const authedClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await authedClient.auth.getUser();
    if (!user) {
      return json({ success: false, reason: 'Not authenticated' }, 401);
    }

    const supabase = createClient(supabaseUrl, serviceKey);
    const { data: item, error: itemError } = await supabase
      .from('items')
      .select('id, user_id, type, title, url, page_body, description, content, supplemental_note')
      .eq('id', itemId)
      .single();

    if (itemError || !item) {
      return json({ success: false, reason: 'Item not found' }, 404);
    }
    if (item.user_id !== user.id) {
      return json({ success: false, reason: 'Not allowed' }, 403);
    }
    if (item.type !== 'link' && item.type !== 'document') {
      return json({ success: false, reason: 'Summaries are only generated for links and documents' });
    }
    if (!item.page_body || item.page_body.trim().length < 50) {
      return json({ success: false, reason: 'no_source_content' });
    }

    const summary = await generateSummary(openAIApiKey, {
      sourceText: item.page_body,
      kind: item.type,
      title: item.title,
      url: item.url,
    });

    if (!summary) {
      return json({ success: false, reason: 'Summary generation failed' });
    }

    const { error: updateError } = await supabase
      .from('items')
      .update({ summary })
      .eq('id', itemId);

    if (updateError) {
      console.error('Error saving summary:', updateError);
      return json({ success: false, reason: 'Failed to save summary' });
    }

    // Refresh embeddings so the summary is searchable alongside everything else
    const textForEmbedding = [
      item.title,
      item.description,
      summary,
      item.content,
      item.supplemental_note,
      item.url,
      item.page_body,
    ].filter(Boolean).join(' ');

    supabase.functions.invoke('generate-embeddings', {
      body: { itemId, textContent: textForEmbedding },
    }).catch((err: unknown) => {
      console.error('generate-embeddings invocation failed (non-fatal):', err);
    });

    return json({ success: true, summary });
  } catch (error) {
    console.error('Unexpected error in summarize-content:', error);
    return json(
      { success: false, reason: error instanceof Error ? error.message : 'Unknown error' },
      500,
    );
  }
});
