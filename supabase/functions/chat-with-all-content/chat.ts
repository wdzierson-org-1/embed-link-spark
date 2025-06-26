
import { ContentChunk, SourceItem } from './types.ts';

export function buildPotentialSources(relevantChunks: ContentChunk[]): Map<string, SourceItem> {
  const potentialSources = new Map<string, SourceItem>();
  
  relevantChunks.forEach(chunk => {
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
    }
  });
  
  return potentialSources;
}

export function buildContextPrompt(relevantChunks: ContentChunk[], message: string): string {
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

  return contentContext;
}

export async function generateChatResponse(
  contextPrompt: string,
  conversationHistory: Array<{ role: string; content: string }>,
  message: string,
  openAIApiKey: string
): Promise<string> {
  const messages = [
    { role: 'system', content: contextPrompt },
    ...conversationHistory,
    { role: 'user', content: message }
  ];

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4.1-2025-04-14',
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

  return data.choices[0].message.content.trim();
}
