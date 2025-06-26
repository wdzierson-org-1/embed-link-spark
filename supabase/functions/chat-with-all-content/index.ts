
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { ChatRequest, ChatResponse, ContentChunk } from './types.ts';
import { authenticateUser } from './auth.ts';
import { generateQueryEmbedding, searchSimilarContent, getRecentItems } from './embedding.ts';
import { evaluateSourceRelevance } from './sourceEvaluation.ts';
import { buildPotentialSources, buildContextPrompt, generateChatResponse } from './chat.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { message, conversationHistory }: ChatRequest = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    console.log('Processing chat request for message:', message.substring(0, 100) + '...');

    // Authenticate user
    const authHeader = req.headers.get('Authorization');
    const { user, supabaseAdmin } = await authenticateUser(authHeader);

    // Semantic search with multiple fallback strategies
    let relevantChunks: ContentChunk[] = [];
    
    try {
      console.log('Starting semantic search...');
      // Generate embedding for the user's query
      const queryEmbedding = await generateQueryEmbedding(message, openAIApiKey);
      console.log('Query embedding generated successfully');
      
      // Search for similar content chunks
      relevantChunks = await searchSimilarContent(queryEmbedding, user.id, supabaseAdmin);
      console.log(`Semantic search returned ${relevantChunks.length} chunks`);
    } catch (embeddingError) {
      console.error('Embedding search failed:', embeddingError);
    }

    // If we don't have enough semantic matches, get recent items
    if (relevantChunks.length < 5) {
      console.log(`Only ${relevantChunks.length} semantic matches found, supplementing with recent items`);
      const recentItems = await getRecentItems(user.id, supabaseAdmin);
      console.log(`Retrieved ${recentItems.length} recent items`);
      
      // Combine and deduplicate based on item_id
      const itemIds = new Set(relevantChunks.map(chunk => chunk.item_id));
      const newRecentItems = recentItems.filter(item => !itemIds.has(item.item_id));
      
      relevantChunks = [...relevantChunks, ...newRecentItems];
    }

    console.log(`Total chunks for context: ${relevantChunks.length}`);

    // Build potential sources and evaluate relevance
    const potentialSources = buildPotentialSources(relevantChunks);
    console.log(`Potential sources identified: ${potentialSources.size}`);

    const finalSources = await evaluateSourceRelevance(message, potentialSources, openAIApiKey);
    console.log(`LLM selected ${finalSources.length} relevant sources`);

    // Generate AI response
    const contentContext = buildContextPrompt(relevantChunks, message);
    console.log('Sending request to OpenAI with context for', relevantChunks.length, 'chunks');

    const aiResponse = await generateChatResponse(contentContext, conversationHistory, message, openAIApiKey);
    console.log('OpenAI response generated successfully');

    // Return response with curated source information
    const response: ChatResponse = {
      response: aiResponse,
      sources: finalSources.map(source => ({
        id: source.id,
        title: source.title,
        type: source.type,
        url: source.url
      }))
    };

    console.log(`Returning response with ${finalSources.length} curated sources`);
    return new Response(JSON.stringify(response), {
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
