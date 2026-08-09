
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

    // Clean and prepare text content
    const cleanedText = textContent.trim().replace(/\s+/g, ' ');
    console.log('Cleaned text length:', cleanedText.length);

    // Optimized chunking strategy for personal notes and discrete information
    const chunks = [];
    
    if (cleanedText.length <= 1200) {
      // For shorter content (most personal notes), use as single chunk
      chunks.push(cleanedText);
    } else {
      // For longer content, use smaller chunks with more overlap to preserve context
      const chunkSize = 600; // Smaller chunks for better granularity
      const overlap = 150; // More overlap to preserve relationships
      
      // Try to split on natural boundaries first (paragraphs, sentences)
      const paragraphs = cleanedText.split(/\n\s*\n/).filter((p: string) => p.trim().length > 0);
      
      if (paragraphs.length > 1) {
        // Process paragraph by paragraph, combining small ones
        let currentChunk = '';
        
        for (const paragraph of paragraphs) {
          if (currentChunk.length + paragraph.length + 2 <= chunkSize) {
            currentChunk += (currentChunk ? '\n\n' : '') + paragraph;
          } else {
            if (currentChunk.trim()) {
              chunks.push(currentChunk.trim());
            }
            currentChunk = paragraph;
          }
        }
        
        if (currentChunk.trim()) {
          chunks.push(currentChunk.trim());
        }
      } else {
        // Fall back to sliding window for very long single paragraphs
        for (let i = 0; i < cleanedText.length; i += chunkSize - overlap) {
          const chunk = cleanedText.slice(i, i + chunkSize);
          if (chunk.trim().length > 100) { // Only add meaningful chunks
            chunks.push(chunk.trim());
          }
        }
      }
    }

    console.log('Created', chunks.length, 'chunks for embedding');

    // Replace any existing embeddings for this item so re-embeds (link enrichment,
    // image analysis, PDF extraction, edits) never accumulate stale duplicate chunks
    const { error: deleteError } = await supabase
      .from('embeddings')
      .delete()
      .eq('item_id', itemId);

    if (deleteError) {
      console.error('Error clearing old embeddings:', deleteError);
      throw deleteError;
    }

    // Generate embeddings in batches (one API call per batch instead of per chunk)
    const BATCH_SIZE = 100;
    for (let batchStart = 0; batchStart < chunks.length; batchStart += BATCH_SIZE) {
      const batch = chunks.slice(batchStart, batchStart + BATCH_SIZE);
      console.log(`Embedding chunks ${batchStart + 1}-${batchStart + batch.length} of ${chunks.length}`);

      const embeddingResponse = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openAIApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'text-embedding-3-small',
          input: batch,
        }),
      });

      if (!embeddingResponse.ok) {
        const errorText = await embeddingResponse.text();
        console.error('OpenAI API error:', embeddingResponse.status, errorText);
        throw new Error(`OpenAI API error: ${embeddingResponse.status} ${errorText}`);
      }

      const embeddingData = await embeddingResponse.json();

      if (!Array.isArray(embeddingData.data) || embeddingData.data.length !== batch.length) {
        console.error('Invalid embedding response:', embeddingData);
        throw new Error('Failed to generate embeddings - invalid response');
      }

      const rows = embeddingData.data.map((entry: { index: number; embedding: number[] }, i: number) => ({
        item_id: itemId,
        content_chunk: batch[i],
        chunk_index: batchStart + i,
        embedding: JSON.stringify(entry.embedding),
      }));

      const { error } = await supabase.from('embeddings').insert(rows);

      if (error) {
        console.error('Error storing embeddings:', error);
        throw error;
      }
    }

    console.log('Successfully processed', chunks.length, 'chunks for item:', itemId);

    return new Response(JSON.stringify({ success: true, chunksProcessed: chunks.length }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error generating embeddings:', error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
