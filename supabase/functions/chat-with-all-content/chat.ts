
import { ContentChunk, SourceItem } from './types.ts';

export function buildPotentialSources(relevantChunks: ContentChunk[]): Map<string, SourceItem> {
  console.log('🏗️ Building potential sources from', relevantChunks.length, 'chunks');
  
  const potentialSources = new Map<string, SourceItem>();
  
  relevantChunks.forEach((chunk, index) => {
    console.log(`📝 Processing chunk ${index + 1}: item_id=${chunk.item_id}, similarity=${chunk.similarity.toFixed(3)}`);
    
    const existingSource = potentialSources.get(chunk.item_id);
    if (!existingSource || chunk.similarity > existingSource.maxSimilarity) {
      potentialSources.set(chunk.item_id, {
        id: chunk.item_id,
        title: chunk.item_title || 'Untitled',
        type: chunk.item_type,
        url: chunk.item_url,
        maxSimilarity: chunk.similarity,
        content: chunk.content
      });
      console.log(`✅ Added/updated source: "${chunk.item_title}" (similarity: ${chunk.similarity.toFixed(3)})`);
    }
  });
  
  console.log(`🎯 Final potential sources count: ${potentialSources.size}`);
  return potentialSources;
}

export function buildContextPrompt(relevantChunks: ContentChunk[], message: string): string {
  console.log('📝 Building context prompt with', relevantChunks.length, 'chunks');
  
  let contentContext = `You are an AI assistant helping the user work with their personal content collection. You have access to their notes, saved articles, recordings, and other personal information.

IMPORTANT: When providing information, be comprehensive and include ALL relevant details you find. Focus on the most relevant content pieces and cite specific information from the user's content.

Here's the relevant content from their collection:

`;

  if (relevantChunks.length > 0) {
    relevantChunks.forEach((chunk, index) => {
      console.log(`📄 Adding chunk ${index + 1} to context: "${chunk.item_title}" (${chunk.content.length} chars)`);
      contentContext += `[Source ${index + 1} - "${chunk.item_title || 'Untitled'}" (${chunk.item_type})]: ${chunk.content}\n\n`;
    });
  } else {
    console.log('⚠️ No relevant content found for context');
    contentContext += "No specific relevant content found in the user's collection.\n\n";
  }

  contentContext += `
Please provide a helpful, comprehensive response based on the relevant information above. If you found relevant information, reference it specifically. If no relevant information was found, be honest about this limitation.

User's question: ${message}`;

  console.log('📊 Final context prompt length:', contentContext.length, 'characters');
  return contentContext;
}

export async function generateChatResponse(
  contextPrompt: string,
  conversationHistory: Array<{ role: string; content: string }>,
  message: string,
  openAIApiKey: string
): Promise<string> {
  console.log('🤖 Generating chat response with OpenAI');
  console.log('📝 Context prompt length:', contextPrompt.length);
  console.log('🗣️ Conversation history length:', conversationHistory.length);

  const messages = [
    { role: 'system', content: contextPrompt },
    ...conversationHistory,
    { role: 'user', content: message }
  ];

  console.log('📤 Sending to OpenAI with', messages.length, 'messages');

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages,
      max_tokens: 1500,
      temperature: 0.3,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error('❌ OpenAI API error:', response.status, errorText);
    throw new Error(`OpenAI API error: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  
  if (!data.choices?.[0]?.message?.content) {
    console.error('❌ Invalid OpenAI response structure:', data);
    throw new Error('No response generated from OpenAI');
  }

  const aiResponse = data.choices[0].message.content.trim();
  console.log('✅ OpenAI response generated, length:', aiResponse.length);
  console.log('🎯 Response preview:', aiResponse.substring(0, 200) + '...');
  
  return aiResponse;
}
