
import { processImage } from './imageProcessor.ts';
import { processAudio } from './audioProcessor.ts';
import { successMessages } from './constants.ts';

export async function handleNoteIntent(
  message: string, 
  mediaUrl: string | null, 
  mediaContentType: string | null, 
  userId: string,
  supabase: any,
  openaiApiKey: string
): Promise<string> {
  try {
    let contentToSave = message || '';
    let processedMedia = '';

    // Handle media if present
    if (mediaUrl && mediaContentType) {
      if (mediaContentType.startsWith('image/')) {
        processedMedia = await processImage(mediaUrl, openaiApiKey);
      } else if (mediaContentType.startsWith('audio/')) {
        processedMedia = await processAudio(mediaUrl, openaiApiKey);
      }
      
      if (processedMedia) {
        contentToSave = contentToSave ? `${contentToSave}\n\n${processedMedia}` : processedMedia;
      }
    }

    // Save to items table using the existing content processor pattern
    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: userId,
        type: 'text',
        content: contentToSave,
        title: generateTitleFromContent(contentToSave),
        file_path: mediaUrl || null,
        mime_type: mediaContentType || null
      })
      .select()
      .single();

    if (error) throw error;

    // Generate embeddings for the content
    if (contentToSave.trim()) {
      try {
        await supabase.functions.invoke('generate-embeddings', {
          body: {
            itemId: item.id,
            textContent: contentToSave
          }
        });
      } catch (embeddingError) {
        console.error('Error generating embeddings:', embeddingError);
      }
    }

    const randomMessage = successMessages[Math.floor(Math.random() * successMessages.length)];
    return processedMedia ? `${randomMessage} ${processedMedia.substring(0, 100)}...` : randomMessage;

  } catch (error) {
    console.error('Error handling note intent:', error);
    return 'Sorry, I couldn\'t save that note. Please try again.';
  }
}

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

    // Search for similar content chunks using the embedding
    const { data: chunks, error: searchError } = await supabase
      .rpc('search_content_chunks', {
        query_embedding: queryEmbedding,
        match_threshold: 0.3,
        match_count: 5,
        user_id_param: userId
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
      `Title: ${chunk.item_title}\nContent: ${chunk.content}\n`
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

export async function handleCommandIntent(
  message: string, 
  userId: string,
  supabase: any,
  openaiApiKey: string
): Promise<string> {
  const lowerMessage = message.toLowerCase();

  if (lowerMessage.includes('help')) {
    return `Hi! I can help you save notes and answer questions about your saved content.

💾 To save: Just tell me what to remember
❓ To search: Ask me questions about your saved content
📱 I can also process images and audio you send!

Try saying "remember to call mom" or "what did I save about meetings?"`;
  }

  if (lowerMessage.includes('delete') || lowerMessage.includes('remove')) {
    return 'I can\'t delete specific items via SMS yet, but you can manage your content in the web app.';
  }

  // Default: treat unclear commands as notes
  return await handleNoteIntent(message, null, null, userId, supabase, openaiApiKey);
}

function generateTitleFromContent(content: string): string {
  if (!content) return 'SMS Note';
  
  // Take first 50 characters and clean up
  const title = content.substring(0, 50).replace(/\n/g, ' ').trim();
  return title + (content.length > 50 ? '...' : '');
}
