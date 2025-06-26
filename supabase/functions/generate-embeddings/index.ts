
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
    console.log('Generate embeddings called for item:', itemId, 'with text length:', textContent?.length);
    
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!openAIApiKey || !supabaseUrl || !supabaseKey) {
      throw new Error('Missing required environment variables');
    }

    if (!textContent || !textContent.trim()) {
      console.log('No text content provided, skipping embedding generation');
      return new Response(JSON.stringify({ success: true, chunksProcessed: 0 }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseKey);

    // Clean and prepare text content - remove extra whitespace and normalize
    const cleanedText = textContent.trim().replace(/\s+/g, ' ');
    console.log('Cleaned text length:', cleanedText.length);

    // Split text into chunks for embedding (smaller chunks for better retrieval)
    const chunkSize = 800; // Reduced chunk size for better granularity
    const chunks = [];
    
    if (cleanedText.length <= chunkSize) {
      // If text is small enough, use as single chunk
      chunks.push(cleanedText);
    } else {
      // Split into overlapping chunks
      const overlap = 100;
      for (let i = 0; i < cleanedText.length; i += chunkSize - overlap) {
        const chunk = cleanedText.slice(i, i + chunkSize);
        if (chunk.trim().length > 50) { // Only add chunks with meaningful content
          chunks.push(chunk.trim());
        }
      }
    }

    console.log('Created', chunks.length, 'chunks for embedding');

    // Generate embeddings for each chunk
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      console.log(`Processing chunk ${i + 1}/${chunks.length}, length: ${chunk.length}`);
      
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

      if (!embeddingResponse.ok) {
        const errorText = await embeddingResponse.text();
        console.error('OpenAI API error:', embeddingResponse.status, errorText);
        throw new Error(`OpenAI API error: ${embeddingResponse.status} ${errorText}`);
      }

      const embeddingData = await embeddingResponse.json();
      
      if (!embeddingData.data?.[0]?.embedding) {
        console.error('Invalid embedding response:', embeddingData);
        throw new Error('Failed to generate embedding - invalid response');
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

    console.log('Successfully processed', chunks.length, 'chunks for item:', itemId);

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
