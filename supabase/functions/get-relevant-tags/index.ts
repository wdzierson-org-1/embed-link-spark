
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { content, title, description, availableTags } = await req.json();
    
    if (!availableTags || availableTags.length === 0) {
      return new Response(JSON.stringify({ relevantTags: [] }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openAIApiKey) {
      console.error('OpenAI API key not found');
      return new Response(JSON.stringify({ relevantTags: [] }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const itemText = [title, content, description].filter(Boolean).join(' ');
    
    const prompt = `Given the following content and list of available tags, return only the tags that are most relevant to the content. Return them as a JSON array of strings, maximum 5 tags. If no tags are relevant, return an empty array.

Content: "${itemText}"

Available tags: ${availableTags.join(', ')}

Return format: ["tag1", "tag2", "tag3"]`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: 'You are a helpful assistant that analyzes content and suggests relevant tags. Always return a valid JSON array.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.3,
      }),
    });

    const data = await response.json();
    const aiResponse = data.choices[0].message.content;
    
    let relevantTags = [];
    try {
      relevantTags = JSON.parse(aiResponse);
      // Ensure it's an array and filter out any tags not in the available list
      if (Array.isArray(relevantTags)) {
        relevantTags = relevantTags.filter(tag => availableTags.includes(tag));
      } else {
        relevantTags = [];
      }
    } catch (parseError) {
      console.error('Error parsing AI response:', parseError);
      relevantTags = [];
    }

    return new Response(JSON.stringify({ relevantTags }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in get-relevant-tags function:', error);
    return new Response(JSON.stringify({ relevantTags: [] }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
