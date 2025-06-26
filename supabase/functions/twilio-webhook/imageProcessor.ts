
export async function processImage(imageUrl: string, openaiApiKey: string): Promise<string> {
  if (!openaiApiKey) return '';

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
            role: 'user',
            content: [
              { 
                type: 'text', 
                text: 'Describe what you see in this image. Extract any text if present. Be concise but thorough.'
              },
              {
                type: 'image_url',
                image_url: { url: imageUrl }
              }
            ]
          }
        ],
        max_tokens: 300
      }),
    });

    const data = await response.json();
    return data.choices[0]?.message?.content || '';
  } catch (error) {
    console.error('Error processing image:', error);
    return 'Image received but could not be processed.';
  }
}
