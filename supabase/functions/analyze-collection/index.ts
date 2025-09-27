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
    const { attachments, userText } = await req.json();

    console.log('Analyzing collection with', attachments.length, 'attachments');

    // Build a description of the attachments for AI analysis
    let attachmentDescriptions = [];
    
    for (const attachment of attachments) {
      if (attachment.type === 'link') {
        attachmentDescriptions.push(
          `Link: ${attachment.title || attachment.url} (${attachment.siteName || 'Unknown site'})${
            attachment.description ? ' - ' + attachment.description : ''
          }`
        );
      } else {
        attachmentDescriptions.push(
          `${attachment.type.charAt(0).toUpperCase() + attachment.type.slice(1)} file: ${attachment.name || 'Unnamed file'}`
        );
      }
    }

    const attachmentContext = attachmentDescriptions.join('\n');

    const systemPrompt = `You are helping to create a title and description for a collection of items that a user is saving. The user may have provided some text content, and they have attached various links, images, videos, or other files.

Your task is to create:
1. A concise, descriptive title (max 60 characters)
2. A brief description (max 200 characters) that summarizes what this collection contains

Be creative but accurate. Focus on the content and purpose rather than being overly technical.`;

    const userPrompt = `Please analyze this collection and provide a title and description:

${userText ? `User's text content: "${userText}"` : 'No text content provided.'}

Attached items:
${attachmentContext}

Return your response as JSON with "title" and "description" fields.`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt }
        ],
        max_tokens: 200,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status}`);
    }

    const data = await response.json();
    const aiResponse = data.choices[0].message.content;

    let result;
    try {
      result = JSON.parse(aiResponse);
    } catch (parseError) {
      console.error('Failed to parse AI response:', aiResponse);
      // Fallback if AI doesn't return valid JSON
      result = {
        title: userText ? userText.substring(0, 50) + '...' : 'Mixed Collection',
        description: `Collection with ${attachments.length} items including ${attachmentDescriptions.slice(0, 2).join(', ')}`
      };
    }

    console.log('Generated collection analysis:', result);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in analyze-collection function:', error);
    return new Response(JSON.stringify({ 
      error: error instanceof Error ? error.message : 'Unknown error',
      title: 'Collection',
      description: 'Mixed content collection'
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});