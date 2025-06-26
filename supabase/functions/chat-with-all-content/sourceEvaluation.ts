
import { SourceItem } from './types.ts';

export async function evaluateSourceRelevance(
  message: string,
  potentialSources: Map<string, SourceItem>,
  openAIApiKey: string
): Promise<SourceItem[]> {
  if (potentialSources.size === 0) {
    return [];
  }

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
        model: 'gpt-4.1-2025-04-14',
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
        
        return relevantSourceIds
          .map((id: string) => potentialSources.get(id))
          .filter((source: SourceItem | undefined) => source)
          .slice(0, 3);
          
      } catch (parseError) {
        console.error('Failed to parse LLM source evaluation:', parseError);
        return getFallbackSources(potentialSources);
      }
    }
  } catch (sourceEvalError) {
    console.error('Source evaluation failed:', sourceEvalError);
  }
  
  return getFallbackSources(potentialSources);
}

function getFallbackSources(potentialSources: Map<string, SourceItem>): SourceItem[] {
  return Array.from(potentialSources.values())
    .sort((a, b) => b.maxSimilarity - a.maxSimilarity)
    .slice(0, 3);
}
