
import { ContentChunk } from './types.ts';

export async function generateQueryEmbedding(message: string, openAIApiKey: string): Promise<number[]> {
  console.log('🔍 Generating embedding for query:', message.substring(0, 100) + '...');
  
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

  if (!queryEmbeddingResponse.ok) {
    const errorText = await queryEmbeddingResponse.text();
    console.error('❌ OpenAI embedding API error:', queryEmbeddingResponse.status, errorText);
    throw new Error('Failed to generate query embedding');
  }

  const queryEmbeddingData = await queryEmbeddingResponse.json();
  const embedding = queryEmbeddingData.data[0].embedding;
  console.log('✅ Query embedding generated, dimensions:', embedding.length);
  return embedding;
}

export async function searchSimilarContent(
  queryEmbedding: number[],
  userId: string,
  supabaseAdmin: any
): Promise<ContentChunk[]> {
  console.log('🔍 Starting semantic search for user:', userId);
  console.log('📊 Query embedding dimensions:', queryEmbedding.length);
  
  // First, let's check if we have any embeddings at all for this user
  const { data: embeddingsCount, error: countError } = await supabaseAdmin
    .from('embeddings')
    .select('count', { count: 'exact' })
    .eq('item_id', supabaseAdmin.from('items').select('id').eq('user_id', userId));
  
  if (countError) {
    console.error('❌ Error checking embeddings count:', countError);
  } else {
    console.log('📈 Total embeddings in database for user:', embeddingsCount);
  }

  // Check if the search function exists and works
  try {
    console.log('🔍 Attempting semantic search with threshold 0.5 and count 15');
    const { data: similarChunks, error: searchError } = await supabaseAdmin.rpc('search_similar_content', {
      query_embedding: queryEmbedding,
      match_threshold: 0.5, // Lower threshold for better recall
      match_count: 15,
      target_user_id: userId  // Note: using target_user_id as per the function signature
    });

    if (searchError) {
      console.error('❌ Semantic search error:', searchError);
      console.log('🔄 Falling back to recent items due to search error');
      return [];
    }

    if (!similarChunks || similarChunks.length === 0) {
      console.log('⚠️ No chunks found with threshold 0.5, trying with threshold 0.3');
      
      const { data: lowerThresholdChunks, error: lowerError } = await supabaseAdmin.rpc('search_similar_content', {
        query_embedding: queryEmbedding,
        match_threshold: 0.3, // Even lower threshold
        match_count: 20,
        target_user_id: userId
      });

      if (lowerError) {
        console.error('❌ Lower threshold search error:', lowerError);
        return [];
      }

      if (!lowerThresholdChunks || lowerThresholdChunks.length === 0) {
        console.log('❌ No chunks found even with threshold 0.3');
        return [];
      }

      console.log(`✅ Found ${lowerThresholdChunks.length} chunks with lower threshold`);
      const topChunks = lowerThresholdChunks
        .sort((a: any, b: any) => b.similarity - a.similarity)
        .slice(0, 10);
      
      topChunks.forEach((chunk: any, index: number) => {
        console.log(`📄 Chunk ${index + 1}: similarity=${chunk.similarity.toFixed(3)}, title="${chunk.item_title}", content="${chunk.content_chunk.substring(0, 100)}..."`);
      });
      
      return topChunks.map((chunk: any) => ({
        content: chunk.content_chunk,
        similarity: chunk.similarity,
        item_id: chunk.item_id,
        item_title: chunk.item_title,
        item_type: chunk.item_type,
        item_url: chunk.item_url
      }));
    }

    console.log(`✅ Found ${similarChunks.length} high-confidence chunks via semantic search`);
    
    const topChunks = similarChunks
      .sort((a: any, b: any) => b.similarity - a.similarity)
      .slice(0, 10);
    
    topChunks.forEach((chunk: any, index: number) => {
      console.log(`📄 Chunk ${index + 1}: similarity=${chunk.similarity.toFixed(3)}, title="${chunk.item_title}", content="${chunk.content_chunk.substring(0, 100)}..."`);
    });
    
    return topChunks.map((chunk: any) => ({
      content: chunk.content_chunk,
      similarity: chunk.similarity,
      item_id: chunk.item_id,
      item_title: chunk.item_title,
      item_type: chunk.item_type,
      item_url: chunk.item_url
    }));
  } catch (error) {
    console.error('❌ Unexpected error in semantic search:', error);
    return [];
  }
}

export async function getRecentItems(userId: string, supabaseAdmin: any): Promise<ContentChunk[]> {
  console.log('🔄 Fetching recent items as fallback for user:', userId);
  
  const { data: items, error: itemsError } = await supabaseAdmin
    .from('items')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(10);

  if (itemsError) {
    console.error('❌ Error fetching recent items:', itemsError);
    return [];
  }

  if (!items || items.length === 0) {
    console.log('⚠️ No items found for user');
    return [];
  }

  console.log(`✅ Retrieved ${items.length} recent items as fallback`);
  
  items.forEach((item: any, index: number) => {
    const content = `${item.title || ''} ${item.description || ''} ${item.content || ''}`.trim();
    console.log(`📄 Recent item ${index + 1}: title="${item.title}", type="${item.type}", content="${content.substring(0, 100)}..."`);
  });
  
  return items.map((item: any) => ({
    content: `${item.title || ''} ${item.description || ''} ${item.content || ''}`.trim(),
    item_id: item.id,
    item_title: item.title,
    item_type: item.type,
    item_url: item.url,
    similarity: 0.2 // Lower similarity score to indicate these are fallback matches
  })).filter((chunk: ContentChunk) => chunk.content.length > 0);
}
