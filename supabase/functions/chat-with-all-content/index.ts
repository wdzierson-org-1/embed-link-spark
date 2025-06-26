
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

    // Semantic search with stricter filtering
    let relevantChunks = [];
    let potentialSources = new Map(); // Track potential source items
    
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

        // Search for similar content chunks with higher threshold and fewer results
        const { data: similarChunks, error: searchError } = await supabaseAdmin.rpc('search_similar_content', {
          query_embedding: queryEmbedding,
          match_threshold: 0.75, // Higher threshold for more relevant matches
          match_count: 10, // Fewer results to focus on quality
          user_id: user.id
        });

        if (!searchError && similarChunks && similarChunks.length > 0) {
          console.log(`Found ${similarChunks.length} high-confidence chunks via semantic search`);
          
          // Sort by similarity score (highest first) and take top chunks
          const topChunks = similarChunks
            .sort((a, b) => b.similarity - a.similarity)
            .slice(0, 8); // Take only top 8 chunks
          
          relevantChunks = topChunks.map(chunk => ({
            content: chunk.content_chunk,
            similarity: chunk.similarity,
            item_id: chunk.item_id,
            item_title: chunk.item_title,
            item_type: chunk.item_type,
            item_url: chunk.item_url
          }));

          // Track potential sources with their highest similarity scores
          topChunks.forEach(chunk => {
            const existingSource = potentialSources.get(chunk.item_id);
            if (!existingSource || chunk.similarity > existingSource.maxSimilarity) {
              potentialSources.set(chunk.item_id, {
                id: chunk.item_id,
                title: chunk.item_title || 'Untitled',
                type: chunk.item_type,
                url: chunk.item_url,
                maxSimilarity: chunk.similarity,
                content: chunk.content_chunk
              });
            }
          });
        }
      }
    } catch (embeddingError) {
      console.error('Embedding search failed:', embeddingError);
    }

    // If we don't have enough high-quality semantic matches, supplement with recent items
    if (relevantChunks.length < 3) {
      console.log('Supplementing with recent user items for broader context');
      const { data: items, error: itemsError } = await supabaseAdmin
        .from('items')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(10);

      if (!itemsError && items) {
        const itemChunks = items.map(item => ({
          content: `${item.title || ''} ${item.description || ''} ${item.content || ''}`.trim(),
          item_id: item.id,
          item_title: item.title,
          item_type: item.type,
          item_url: item.url,
          similarity: 0.5 // Lower similarity for fallback items
        })).filter(chunk => chunk.content.length > 0);
        
        relevantChunks = [...relevantChunks, ...itemChunks];

        // Add fallback items to potential sources
        items.forEach(item => {
          if (!potentialSources.has(item.id)) {
            potentialSources.set(item.id, {
              id: item.id,
              title: item.title || 'Untitled',
              type: item.type,
              url: item.url,
              maxSimilarity: 0.5,
              content: `${item.title || ''} ${item.description || ''} ${item.content || ''}`.trim()
            });
          }
        });
      }
    }

    console.log(`Total chunks for context: ${relevantChunks.length}`);
    console.log(`Potential sources identified: ${potentialSources.size}`);

    // Use LLM to determine most relevant sources
    let finalSources = [];
    if (potentialSources.size > 0) {
      const sourceEvaluationPrompt = `Given the user's question: "${message}"

Here are the potential sources with their content snippets:
${Array.from(potentialSources.values()).map((source, index) => 
  `${index + 1}. ID: ${source.id}, Title: "${source.title}", Content snippet: "${source.content.substring(0, 200)}..."`
).join('\n')}

Please identify the 1-3 most relevant sources that directly relate to answering the user's question. Return only the source IDs in a JSON array format, ordered by relevance (most relevant first).

For example: ["id1", "id2", "id3"]

Be selective - only include sources that directly help answer the question. If no sources are truly relevant, return an empty array.`;

      try {
        const sourceEvalResponse = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${openAIApiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model: 'gpt-4-turbo-2024-04-09',
            messages: [
              { role: 'system', content: 'You are a precise source evaluator. Return only a JSON array of the most relevant source IDs.' },
              { role: 'user', content: sourceEvaluationPrompt }
            ],
            max_tokens: 200,
            temperature: 0.1,
          }),
        });

        if (sourceEvalResponse.ok) {
          const evalData = await sourceEvalResponse.json();
          const evalContent = evalData.choices[0].message.content.trim();
          
          try {
            const relevantSourceIds = JSON.parse(evalContent);
            console.log('LLM selected source IDs:', relevantSourceIds);
            
            // Build final sources list based on LLM selection
            finalSources = relevantSourceIds
              .map(id => potentialSources.get(id))
              .filter(source => source)
              .slice(0, 3); // Maximum 3 sources
              
          } catch (parseError) {
            console.error('Failed to parse LLM source evaluation:', parseError);
            // Fallback: use top 3 sources by similarity
            finalSources = Array.from(potentialSources.values())
              .sort((a, b) => b.maxSimilarity - a.maxSimilarity)
              .slice(0, 3);
          }
        }
      } catch (sourceEvalError) {
        console.error('Source evaluation failed:', sourceEvalError);
        // Fallback: use top 3 sources by similarity
        finalSources = Array.from(potentialSources.values())
          .sort((a, b) => b.maxSimilarity - a.maxSimilarity)
          .slice(0, 3);
      }
    }

    // Prepare enhanced context for the main LLM
    let contentContext = `You are an AI assistant helping the user work with their personal content collection. You have access to their notes, saved articles, recordings, and other personal information.

IMPORTANT: When providing information, be comprehensive and include ALL relevant details you find. Focus on the most relevant content pieces.

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
Please provide a helpful, comprehensive response based on the relevant information above. Be conversational and helpful while being thorough.

User's question: ${message}`;

    console.log('Sending request to OpenAI GPT-4.1 with context for', relevantChunks.length, 'chunks');

    // Prepare messages for OpenAI
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
        model: 'gpt-4-turbo-2024-04-09',
        messages,
        max_tokens: 1500,
        temperature: 0.3,
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
    console.log(`Returning ${finalSources.length} curated sources`);

    // Return response with curated source information
    return new Response(JSON.stringify({ 
      response: aiResponse,
      sources: finalSources.map(source => ({
        id: source.id,
        title: source.title,
        type: source.type,
        url: source.url
      }))
    }), {
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
