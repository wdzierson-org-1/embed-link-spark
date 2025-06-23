
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
    const { content, type, url, fileData, ogData } = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    let messages = [];
    
    if (type === 'image' && fileData) {
      // For images, use GPT-4 Vision
      messages = [
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: 'Please provide a detailed but concise description of this image. Focus on the main subjects, actions, and important visual elements.'
            },
            {
              type: 'image_url',
              image_url: {
                url: fileData,
                detail: 'high'
              }
            }
          ]
        }
      ];
    } else {
      // For text, links, and other content
      let contentToAnalyze = content || url || 'Unknown content';
      let prompt = '';
      
      switch (type) {
        case 'text':
          prompt = `Please provide a brief summary or description of this text content: "${contentToAnalyze}"`;
          break;
        case 'link':
          if (ogData) {
            const ogContext = `Title: ${ogData.title || 'N/A'}, Description: ${ogData.description || 'N/A'}, Site: ${ogData.siteName || 'N/A'}`;
            prompt = `Based on this link and its Open Graph data, provide a brief description: URL: "${contentToAnalyze}", Open Graph: ${ogContext}`;
          } else {
            prompt = `Based on this URL, provide a brief description of what this link might contain: "${contentToAnalyze}"`;
          }
          break;
        case 'audio':
          prompt = 'This is an audio file. Please provide a generic description for audio content.';
          break;
        case 'video':
          prompt = 'This is a video file. Please provide a generic description for video content.';
          break;
        default:
          prompt = `Please provide a brief description of this content: "${contentToAnalyze}"`;
      }
      
      messages = [
        {
          role: 'system',
          content: 'You are a helpful assistant that creates concise, informative descriptions of content. Keep descriptions under 100 words.'
        },
        {
          role: 'user',
          content: prompt
        }
      ];
    }

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: type === 'image' ? 'gpt-4o' : 'gpt-4o-mini',
        messages,
        max_tokens: 200,
        temperature: 0.7,
      }),
    });

    const data = await response.json();
    
    if (!data.choices?.[0]?.message?.content) {
      throw new Error('No description generated');
    }

    const description = data.choices[0].message.content.trim();

    return new Response(JSON.stringify({ description }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error generating description:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
