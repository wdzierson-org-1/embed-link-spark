
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { content } = await req.json();

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
            content: 'You are a helpful assistant that generates concise, descriptive titles for notes. The title should be 3-8 words and capture the main topic or theme of the content. Return only the title, nothing else.' 
          },
          { role: 'user', content: `Generate a short title for this note content: ${content}` }
        ],
        max_tokens: 50,
        temperature: 0.7,
      }),
    });

    const data = await response.json();
    const title = data.choices[0].message.content.trim();

    return new Response(JSON.stringify({ title }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error generating title:', error);
    return new Response(JSON.stringify({ title: 'Untitled Note' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
