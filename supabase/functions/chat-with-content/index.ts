
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { message, item, conversationHistory } = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    // Prepare context about the content item
    let contentContext = `You are an AI assistant helping the user understand and work with their saved content.

Content Details:
- Type: ${item.type}
- Title: ${item.title || 'Untitled'}
`;

    if (item.content) {
      contentContext += `- Content: ${item.content}\n`;
    }

    if (item.description) {
      contentContext += `- AI Description: ${item.description}\n`;
    }

    contentContext += `
Please provide helpful, informative responses about this content. You can:
- Answer questions about the content
- Summarize or explain parts of it
- Help the user understand key concepts
- Suggest related topics or questions
- Help with analysis or interpretation

Be conversational and helpful while staying focused on the content provided.`;

    // Prepare messages for OpenAI
    const messages = [
      {
        role: 'system',
        content: contentContext
      },
      ...conversationHistory,
      {
        role: 'user',
        content: message
      }
    ];

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages,
        max_tokens: 1000,
        temperature: 0.7,
      }),
    });

    const data = await response.json();
    
    if (!data.choices?.[0]?.message?.content) {
      throw new Error('No response generated');
    }

    const aiResponse = data.choices[0].message.content.trim();

    return new Response(JSON.stringify({ response: aiResponse }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in chat-with-content function:', error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
