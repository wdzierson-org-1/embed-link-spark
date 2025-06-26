
import { ContentChunk } from './types.ts';

export async function generateQueryEmbedding(message: string, openAIApiKey: string): Promise<number[]> {
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
    throw new Error('Failed to generate query embedding');
  }

  const queryEmbeddingData = await queryEmbeddingResponse.json();
  return queryEmbeddingData.data[0].embedding;
}

export async function searchSimilarContent(
  queryEmbedding: number[],
  userId: string,
  supabaseAdmin: any
): Promise<ContentChunk[]> {
  const { data: similarChunks, error: searchError } = await supabaseAdmin.rpc('search_similar_content', {
    query_embedding: queryEmbedding,
    match_threshold: 0.75,
    match_count: 10,
    user_id: userId
  });

  if (searchError || !similarChunks || similarChunks.length === 0) {
    return [];
  }

  console.log(`Found ${similarChunks.length} high-confidence chunks via semantic search`);
  
  const topChunks = similarChunks
    .sort((a: any, b: any) => b.similarity - a.similarity)
    .slice(0, 8);
  
  return topChunks.map((chunk: any) => ({
    content: chunk.content_chunk,
    similarity: chunk.similarity,
    item_id: chunk.item_id,
    item_title: chunk.item_title,
    item_type: chunk.item_type,
    item_url: chunk.item_url
  }));
}

export async function getRecentItems(userId: string, supabaseAdmin: any): Promise<ContentChunk[]> {
  const { data: items, error: itemsError } = await supabaseAdmin
    .from('items')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(10);

  if (itemsError || !items) {
    return [];
  }

  return items.map((item: any) => ({
    content: `${item.title || ''} ${item.description || ''} ${item.content || ''}`.trim(),
    item_id: item.id,
    item_title: item.title,
    item_type: item.type,
    item_url: item.url,
    similarity: 0.5
  })).filter((chunk: ContentChunk) => chunk.content.length > 0);
}
