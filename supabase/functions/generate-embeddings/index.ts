
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

    // Normalize whitespace but KEEP newlines — the paragraph splitter below
    // depends on blank lines, so collapsing \s+ here would disable it and send
    // every long text through the blind sliding window.
    const cleanedText = textContent
      .trim()
      .replace(/[^\S\n]+/g, ' ')
      .replace(/ ?\n ?/g, '\n')
      .replace(/\n{3,}/g, '\n\n');
    console.log('Cleaned text length:', cleanedText.length);

    // Optimized chunking strategy for personal notes and discrete information
    const SINGLE_CHUNK_MAX = 1200; // most personal notes fit in one chunk
    const chunkSize = 600; // smaller chunks for better granularity
    const overlap = 150; // overlap preserves relationships across window cuts

    const slidingWindow = (text: string): string[] => {
      const out: string[] = [];
      for (let i = 0; i < text.length; i += chunkSize - overlap) {
        const chunk = text.slice(i, i + chunkSize).trim();
        if (chunk.length > 100) out.push(chunk); // only meaningful chunks
      }
      return out;
    };

    const chunks: string[] = [];

    if (cleanedText.length <= SINGLE_CHUNK_MAX) {
      chunks.push(cleanedText);
    } else {
      // Split on natural boundaries, packing small paragraphs together; a
      // wall-of-text paragraph gets windowed instead of becoming one giant chunk.
      const paragraphs = cleanedText.split(/\n\s*\n/).filter((p: string) => p.trim().length > 0);
      let currentChunk = '';
      const flush = () => {
        if (currentChunk.trim()) chunks.push(currentChunk.trim());
        currentChunk = '';
      };

      for (const paragraph of paragraphs) {
        if (paragraph.length > SINGLE_CHUNK_MAX) {
          flush();
          chunks.push(...slidingWindow(paragraph));
        } else if (currentChunk.length + paragraph.length + 2 <= chunkSize) {
          currentChunk += (currentChunk ? '\n\n' : '') + paragraph;
        } else {
          flush();
          currentChunk = paragraph;
        }
      }
      flush();

      if (chunks.length === 0) {
        chunks.push(...slidingWindow(cleanedText));
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
