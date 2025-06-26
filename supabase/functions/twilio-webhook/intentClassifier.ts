
export async function classifyIntent(message: string, openaiApiKey: string): Promise<string> {
  if (!message || !openaiApiKey) return 'note';

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
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
            content: `You are an intent classifier for a personal knowledge management system. Classify the user's message into one of these categories:

- "note": User wants to save information (e.g., "remember to call Dr. Green", "buy milk tomorrow", "meeting at 3pm")
- "question": User is asking about previously saved information (e.g., "what did I say about the meeting?", "when is my appointment?")
- "command": User wants to perform an action (e.g., "delete my last note", "show me my tasks")

Respond with only the category name: note, question, or command.`
          },
          {
            role: 'user',
            content: message
          }
        ],
        max_tokens: 10,
        temperature: 0.1
      }),
    });

    const data = await response.json();
    const intent = data.choices[0]?.message?.content?.trim().toLowerCase();
    
    return ['note', 'question', 'command'].includes(intent) ? intent : 'note';
  } catch (error) {
    console.error('Error classifying intent:', error);
    return 'note'; // Default to note if classification fails
  }
}
