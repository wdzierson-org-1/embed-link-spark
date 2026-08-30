import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { capTitle, isPlaceholderTitle } from '../_shared/titlePolicy.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { fileUrl, itemId, fileName, snippet } = await req.json();
    console.log('Quick PDF summary request:', { itemId, fileName, hasSnippet: Boolean(snippet) });

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    // Generate quick title from filename
    const quickTitle = fileName
      ?.replace(/\.[^/.]+$/, '') // Remove extension
      .replace(/[_-]/g, ' ') // Replace underscores and hyphens with spaces
      .replace(/\s+/g, ' ') // Normalize spaces
      .trim() || 'Document';

    // Call OpenAI to generate a better summary (quick, just first page analysis)
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'You are a document analyzer. Generate a concise title (5-10 words) and a brief one-sentence description for documents. Be specific and descriptive. Respond with exactly two lines — the title line then the description line — and nothing else: no preamble, no labels, no commentary.'
          },
          {
            role: 'user',
            content: snippet && String(snippet).trim().length > 0
              ? `Here is the beginning of a document named "${fileName}":\n"""${String(snippet).slice(0, 1500)}"""\n\nBased on this text, generate a title and a one-sentence description of what this document contains.`
              : `Based on the filename "${fileName}", generate a title and description. Title should be clear and descriptive. Description should be one sentence explaining what this document likely contains.`
          }
        ],
        max_tokens: 150,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      console.error('OpenAI API error:', response.status, await response.text());
      // Fallback to filename-based title
      return new Response(
        JSON.stringify({
          title: quickTitle,
          description: 'Document uploaded - analyzing content...',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const data = await response.json();
    const aiResponse = data.choices[0].message.content;
    
    // Parse AI response to extract title and description
    let title = quickTitle;
    let description = 'Document uploaded - analyzing content...';
    
    try {
      // Try to parse structured response
      const lines = aiResponse.split('\n').filter((l: string) => l.trim());
      if (lines.length >= 2) {
        title = lines[0].replace(/^(Title:|##\s*)/i, '').trim();
        description = lines[1].replace(/^(Description:|Summary:)/i, '').trim();
      } else if (lines.length === 1) {
        title = lines[0].trim();
      }
    } catch (e) {
      console.error('Error parsing AI response:', e);
    }

    // Update the item with quick summary (chip-time calls carry no itemId and
    // just want the {title, description} back)
    if (itemId) {
      const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
      const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
      const supabase = createClient(supabaseUrl, supabaseKey);

      // Title policy (_shared/titlePolicy.ts): clients always pre-write the
      // filename as the title, so "any title exists" is the wrong guard — a
      // filename-shaped (or empty) title is a placeholder we replace with the
      // AI title; a real user title is never touched. Fetch the current state
      // first; if the fetch itself fails, be conservative and skip the title
      // write rather than risk overwriting something better.
      const { data: existingItem, error: fetchError } = await supabase
        .from('items')
        .select('title, file_path')
        .eq('id', itemId)
        .single();

      if (fetchError) {
        console.error('Error fetching item before quick summary update (skipping title write):', fetchError);
      }

      const shouldWriteTitle =
        !fetchError && isPlaceholderTitle(existingItem?.title, existingItem?.file_path);

      const updates: Record<string, string> = { description };
      if (shouldWriteTitle) {
        updates.title = capTitle(title);
      }

      // Only apply the filename-based guess while full extraction hasn't landed yet
      // (extract-pdf-text sets page_body); never overwrite real content-based results
      const { error: updateError } = await supabase
        .from('items')
        .update(updates)
        .eq('id', itemId)
        .is('page_body', null);

      if (updateError) {
        console.error('Error updating item with quick summary:', updateError);
      } else {
        console.log('Quick summary updated successfully:', { itemId, title: shouldWriteTitle ? title : '(kept existing title)' });
      }
    }

    return new Response(
      JSON.stringify({ title, description }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in quick-pdf-summary:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});
