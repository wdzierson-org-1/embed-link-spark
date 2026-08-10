// Shared summary generation for captured content (links, documents).
//
// Every prompt here enforces "no editorialization": the model's output is
// stored verbatim as product copy, so conversational preambles ("Certainly!",
// "Here's a summary...") must never appear in it.

export const NO_PREAMBLE_RULES =
  'Write the output text itself and nothing else. Never open with a conversational preamble ' +
  '("Certainly!", "Sure!", "Of course", "Here is..."), never refer to yourself, the user, or the task, ' +
  'and never add closing remarks. Do not wrap the output in quotes.';

// Safety net for model slips: drop a leading "Certainly! Here's ..." style
// line, but only when it is unmistakably a preamble.
export const stripPreamble = (text: string): string =>
  text
    .replace(/^(?:certainly|sure|of course|absolutely|got it|here(?:'s| is)[^\n]{0,60}?)[:!.,]\s*/i, '')
    .trim();

interface SummaryInput {
  sourceText: string;
  kind: 'link' | 'document';
  title?: string | null;
  url?: string | null;
}

const MAX_SOURCE_CHARS = 48_000;

export const generateSummary = async (
  openAIApiKey: string,
  { sourceText, kind, title, url }: SummaryInput,
): Promise<string | null> => {
  const sourceLabel = kind === 'link' ? 'a saved web page' : 'a saved document';
  const context = [
    title ? `Title: ${title}` : null,
    url ? `URL: ${url}` : null,
  ].filter(Boolean).join('\n');

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content:
            `You summarize ${sourceLabel} for the user's personal library. ` +
            'Produce a faithful, well-organized summary of the source: main points, key details, ' +
            'and conclusions, in plain direct prose (short paragraphs; use "-" bullets only when the ' +
            'source is list-like). Length proportional to the source, at most ~250 words. ' +
            NO_PREAMBLE_RULES,
        },
        {
          role: 'user',
          content: `${context ? context + '\n\n' : ''}Source content:\n\n${sourceText.slice(0, MAX_SOURCE_CHARS)}`,
        },
      ],
      max_tokens: 600,
      temperature: 0.2,
    }),
  });

  if (!response.ok) {
    console.error('Summary generation failed:', response.status, await response.text());
    return null;
  }

  const data = await response.json();
  const summary = data.choices?.[0]?.message?.content?.trim();
  return summary ? stripPreamble(summary) : null;
};
