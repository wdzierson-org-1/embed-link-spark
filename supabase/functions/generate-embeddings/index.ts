
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { itemId, textContent } = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!openAIApiKey || !supabaseUrl || !supabaseKey) {
      throw new Error('Missing required environment variables');
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Split text into chunks for embedding
    const chunkSize = 1000;
    const chunks = [];
    for (let i = 0; i < textContent.length; i += chunkSize) {
      chunks.push(textContent.slice(i, i + chunkSize));
    }

    // Generate embeddings for each chunk
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      
      const embeddingResponse = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openAIApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'text-embedding-3-small',
          input: chunk,
        }),
      });

      const embeddingData = await embeddingResponse.json();
      
      if (!embeddingData.data?.[0]?.embedding) {
        throw new Error('Failed to generate embedding');
      }

      const embedding = embeddingData.data[0].embedding;

      // Store the embedding in the database
      const { error } = await supabase.from('embeddings').insert({
        item_id: itemId,
        content_chunk: chunk,
        chunk_index: i,
        embedding: JSON.stringify(embedding),
      });

      if (error) {
        console.error('Error storing embedding:', error);
        throw error;
      }
    }

    return new Response(JSON.stringify({ success: true, chunksProcessed: chunks.length }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error generating embeddings:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
