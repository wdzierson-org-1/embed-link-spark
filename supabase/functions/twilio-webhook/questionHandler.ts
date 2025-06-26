
export async function handleQuestionIntent(message: string, userId: string, supabase: any, openaiApiKey: string): Promise<string> {
  try {
    console.log('Handling question intent for user:', userId);
    
    // Generate embedding for the user's query
    let queryEmbedding;
    try {
      const embeddingResponse = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${openaiApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'text-embedding-3-small',
          input: message,
        }),
      });

      if (!embeddingResponse.ok) {
        throw new Error(`Embedding API error: ${embeddingResponse.status}`);
      }

      const embeddingData = await embeddingResponse.json();
      queryEmbedding = embeddingData.data[0].embedding;
    } catch (embeddingError) {
      console.error('Error generating query embedding:', embeddingError);
      // Fall back to keyword search without embeddings
      return await performKeywordSearch(message, userId, supabase, openaiApiKey);
    }

    // Search for similar content chunks using the correct function name
    const { data: chunks, error: searchError } = await supabase
      .rpc('search_similar_content', {
        query_embedding: queryEmbedding,
        match_threshold: 0.3,
        match_count: 5,
        target_user_id: userId
      });

    if (searchError) {
      console.error('Error searching content chunks:', searchError);
      return await performKeywordSearch(message, userId, supabase, openaiApiKey);
    }

    console.log(`Found ${chunks?.length || 0} relevant chunks`);

    if (!chunks || chunks.length === 0) {
      return "I couldn't find any relevant information in your saved content to answer that question.";
    }

    // Build context from the chunks
    const contextItems = chunks.map((chunk: any) => 
      `Title: ${chunk.item_title}\nContent: ${chunk.content_chunk}\n`
    ).join('\n---\n');

    // Generate response using OpenAI
    const chatResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are a helpful assistant that answers questions based on the user's saved content. Use the provided context to answer their question. If the context doesn't contain enough information to answer the question, say so politely.

Context:
${contextItems}`
          },
          {
            role: 'user',
            content: message
          }
        ],
        max_tokens: 500,
        temperature: 0.7
      }),
    });

    if (!chatResponse.ok) {
      throw new Error(`Chat API error: ${chatResponse.status}`);
    }

    const chatData = await chatResponse.json();
    return chatData.choices[0]?.message?.content || "I couldn't generate a response to your question.";

  } catch (error) {
    console.error('Error handling question intent:', error);
    return 'Sorry, I couldn\'t search your content right now. Please try again later.';
  }
}

async function performKeywordSearch(message: string, userId: string, supabase: any, openaiApiKey: string): Promise<string> {
  try {
    // Simple keyword search as fallback
    const keywords = message.toLowerCase().split(' ').filter(word => word.length > 3);
    
    if (keywords.length === 0) {
      return "I couldn't understand your question. Please try rephrasing it.";
    }

    // Search in items table using basic text search
    const { data: items, error } = await supabase
      .from('items')
      .select('id, title, content, description')
      .eq('user_id', userId)
      .or(
        keywords.map(keyword => 
          `title.ilike.%${keyword}%,content.ilike.%${keyword}%,description.ilike.%${keyword}%`
        ).join(',')
      )
      .limit(3);

    if (error) {
      console.error('Error in keyword search:', error);
      return "I encountered an error while searching your content.";
    }

    if (!items || items.length === 0) {
      return "I couldn't find any relevant information in your saved content to answer that question.";
    }

    // Build context from found items
    const contextItems = items.map((item: any) => 
      `Title: ${item.title}\nContent: ${item.content || item.description || ''}\n`
    ).join('\n---\n');

    // Generate response using OpenAI
    const chatResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are a helpful assistant that answers questions based on the user's saved content. Use the provided context to answer their question. If the context doesn't contain enough information to answer the question, say so politely.

Context:
${contextItems}`
          },
          {
            role: 'user',
            content: message
          }
        ],
        max_tokens: 500,
        temperature: 0.7
      }),
    });

    if (!chatResponse.ok) {
      throw new Error(`Chat API error: ${chatResponse.status}`);
    }

    const chatData = await chatResponse.json();
    return chatData.choices[0]?.message?.content || "I couldn't generate a response to your question.";

  } catch (error) {
    console.error('Error in keyword search fallback:', error);
    return 'Sorry, I couldn\'t search your content right now. Please try again later.';
  }
}
