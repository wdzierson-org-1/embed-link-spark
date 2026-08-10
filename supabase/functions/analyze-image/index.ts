
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const parseVisionResponse = (text: string): { description: string; detected_text: string; tags: string[] } => {
  const lines = text.split('\n').map((l) => l.trim()).filter(Boolean);

  let description = '';
  let detected_text = 'none';
  let tags: string[] = [];

  for (const line of lines) {
    if (line.startsWith('DESCRIPTION:')) {
      description = line.replace('DESCRIPTION:', '').trim();
    } else if (line.startsWith('TEXT:')) {
      detected_text = line.replace('TEXT:', '').trim();
    } else if (line.startsWith('TAGS:')) {
      tags = line
        .replace('TAGS:', '')
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean);
    }
  }

  // Fallback: if structured parsing fails, use the full text as description
  if (!description) {
    description = text.trim();
  }

  return { description, detected_text, tags };
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { itemId, imageUrl } = await req.json();

    if (!itemId || !imageUrl) {
      return new Response(JSON.stringify({ success: false, error: 'itemId and imageUrl are required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }
    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Missing Supabase configuration');
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    console.log('Starting Vision analysis for item:', itemId, 'image:', imageUrl);

    // Call OpenAI Vision
    const visionResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'image_url',
                image_url: { url: imageUrl, detail: 'high' },
              },
              {
                type: 'text',
                text: 'Analyze this image and provide:\n1. DESCRIPTION: A 2-3 sentence description of what this image shows, stated directly with no preamble or meta-commentary (never "Certainly", "Here is", "This image shows...it appears" style filler)\n2. TEXT: Any text visible in the image (verbatim, or \'none\' if no text)\n3. TAGS: 3-5 relevant topic tags as comma-separated words\n\nRespond with ONLY these three lines, formatted exactly as:\nDESCRIPTION: <description>\nTEXT: <detected text or \'none\'>\nTAGS: <tag1>, <tag2>, <tag3>',
              },
            ],
          },
        ],
        max_tokens: 500,
      }),
    });

    if (!visionResponse.ok) {
      const errData = await visionResponse.json();
      throw new Error(`OpenAI Vision error: ${errData.error?.message || 'Unknown error'}`);
    }

    const visionData = await visionResponse.json();
    const rawContent = visionData.choices?.[0]?.message?.content;

    if (!rawContent) {
      throw new Error('No content returned from Vision API');
    }

    console.log('Vision API raw response:', rawContent);

    const { description, detected_text, tags } = parseVisionResponse(rawContent);

    console.log('Parsed — description:', description, '| detected_text:', detected_text, '| tags:', tags);

    // Build the update payload; try page_body first, fall back to content
    const hasOcrText = detected_text.toLowerCase() !== 'none' && detected_text.trim().length > 0;

    const { data: updatedItem, error: updateError } = await supabase
      .from('items')
      .update({ description, page_body: hasOcrText ? detected_text : null })
      .eq('id', itemId)
      .select('title, supplemental_note')
      .single();

    if (updateError) {
      console.error('Error updating item after Vision analysis:', updateError);
    } else {
      console.log('Item updated successfully with Vision analysis');
    }

    // Re-embed the full item: generate-embeddings replaces prior chunks, so the
    // text must carry the title/note too, not just the Vision output
    const textContent = [
      updatedItem?.title,
      description,
      hasOcrText ? detected_text : null,
      updatedItem?.supplemental_note,
    ].filter(Boolean).join(' ');

    // Invoke generate-embeddings
    const { error: embeddingError } = await supabase.functions.invoke('generate-embeddings', {
      body: { itemId, textContent },
    });

    if (embeddingError) {
      console.error('Failed to generate embeddings after Vision analysis:', embeddingError);
    } else {
      console.log('Embeddings generated successfully after Vision analysis');
    }

    return new Response(
      JSON.stringify({ success: true, description, detected_text, tags }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in analyze-image:', error);
    // Return 200 with success: false so the caller treats this as non-fatal
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'Unknown error' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
