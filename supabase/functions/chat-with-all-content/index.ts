
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
    const { message, conversationHistory } = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase configuration missing');
    }

    // Get authorization header
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('No authorization header');
    }

    // Create Supabase client with service role key for admin access
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // Extract and verify the JWT token
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);
    
    if (userError || !user) {
      console.error('Authentication error:', userError);
      throw new Error('Authentication failed');
    }

    console.log('Authenticated user:', user.id);

    // First, try semantic search using vector embeddings if we have a specific query
    let relevantChunks = [];
    
    try {
      // Generate embedding for the user's query
      const queryEmbeddingResponse = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openAIApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'text-embedding-3-small',
          input: message,
        }),
      });

      if (queryEmbeddingResponse.ok) {
        const queryEmbeddingData = await queryEmbeddingResponse.json();
        const queryEmbedding = queryEmbeddingData.data[0].embedding;

        // Search for similar content chunks with optimized parameters
        const { data: similarChunks, error: searchError } = await supabaseAdmin.rpc('search_similar_content', {
          query_embedding: queryEmbedding,
          match_threshold: 0.6, // Lower threshold for more inclusive results
          match_count: 20, // More results to capture comprehensive information
          user_id: user.id
        });

        if (!searchError && similarChunks && similarChunks.length > 0) {
          console.log(`Found ${similarChunks.length} relevant chunks via semantic search`);
          relevantChunks = similarChunks.map(chunk => ({
            content: chunk.content_chunk,
            similarity: chunk.similarity,
            item_id: chunk.item_id
          }));
        }
      }
    } catch (embeddingError) {
      console.error('Embedding search failed, falling back to basic search:', embeddingError);
    }

    // If semantic search didn't work or returned few results, fall back to fetching user's items
    if (relevantChunks.length < 5) {
      console.log('Supplementing with user items for broader context');
      const { data: items, error: itemsError } = await supabaseAdmin
        .from('items')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(30); // Get more recent items for context

      if (!itemsError && items) {
        const itemChunks = items.map(item => ({
          content: `${item.title || ''} ${item.description || ''} ${item.content || ''}`.trim(),
          item_id: item.id,
          type: item.type
        })).filter(chunk => chunk.content.length > 0);
        
        relevantChunks = [...relevantChunks, ...itemChunks];
      }
    }

    console.log(`Total chunks for context: ${relevantChunks.length}`);

    // Prepare enhanced context for the LLM
    let contentContext = `You are an AI assistant helping the user work with their personal content collection. You have access to their notes, saved articles, recordings, and other personal information.

IMPORTANT: When providing information, be comprehensive and include ALL relevant details you find. If there are multiple pieces of information about the same topic (like pricing from different stores), include ALL of them.

Here's the relevant content from their collection:

`;

    if (relevantChunks.length > 0) {
      relevantChunks.forEach((chunk, index) => {
        contentContext += `[${index + 1}] ${chunk.content}\n\n`;
      });
    } else {
      contentContext += "No specific relevant content found in the user's collection.\n\n";
    }

    contentContext += `
Please provide a helpful, comprehensive response based on ALL the relevant information above. If you find multiple related pieces of information (like different prices, different sources, etc.), make sure to include all of them in your response. Be conversational and helpful while being thorough.

User's question: ${message}`;

    console.log('Sending request to OpenAI GPT-4.1 with context for', relevantChunks.length, 'chunks');

    // Prepare messages for OpenAI with the most advanced model
    const messages = [
      {
        role: 'system',
        content: contentContext
      },
      ...conversationHistory,
      {
        role: 'user',
        content: message
      }
    ];

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4.1-2025-04-14', // Most advanced model for best RAG performance
        messages,
        max_tokens: 1500, // Increased for more comprehensive responses
        temperature: 0.3, // Lower temperature for more factual, consistent responses
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    
    if (!data.choices?.[0]?.message?.content) {
      throw new Error('No response generated from OpenAI');
    }

    const aiResponse = data.choices[0].message.content.trim();
    console.log('OpenAI response generated successfully');

    return new Response(JSON.stringify({ response: aiResponse }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in chat-with-all-content function:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
