
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
    
    console.log('=== RELEVANT TAGS DEBUG ===');
    console.log('Input data:', { 
      contentLength: content?.length || 0, 
      title, 
      descriptionLength: description?.length || 0,
      availableTagsCount: availableTags?.length || 0,
      availableTags: availableTags
    });
    
    if (!availableTags || availableTags.length === 0) {
      console.log('No available tags provided, returning empty array');
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
    console.log('Combined text for analysis:', itemText);
    
    const prompt = `Given the following content and list of available tags, return only the tags that are most relevant to the content. Return them as a JSON array of strings, maximum 5 tags. If no tags are relevant, return an empty array.

Content: "${itemText}"

Available tags: ${availableTags.join(', ')}

Return ONLY a valid JSON array, no other text or formatting. Example: ["tag1", "tag2", "tag3"]`;

    console.log('Sending prompt to OpenAI:', prompt);

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: 'You are a helpful assistant that analyzes content and suggests relevant tags. Always return a valid JSON array of strings, no markdown formatting, no code blocks, just the raw JSON array.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.1,
      }),
    });

    const data = await response.json();
    console.log('OpenAI response data:', data);
    
    const aiResponse = data.choices[0].message.content;
    console.log('Raw AI response:', aiResponse);
    
    let relevantTags = [];
    try {
      // Clean the response by removing markdown code blocks if present
      let cleanedResponse = aiResponse.trim();
      if (cleanedResponse.startsWith('```json')) {
        cleanedResponse = cleanedResponse.replace(/```json\s*/, '').replace(/\s*```$/, '');
      } else if (cleanedResponse.startsWith('```')) {
        cleanedResponse = cleanedResponse.replace(/```\s*/, '').replace(/\s*```$/, '');
      }
      
      console.log('Cleaned response for parsing:', cleanedResponse);
      
      relevantTags = JSON.parse(cleanedResponse);
      console.log('Parsed tags:', relevantTags);
      
      // Ensure it's an array and filter out any tags not in the available list
      if (Array.isArray(relevantTags)) {
        const filteredTags = relevantTags.filter(tag => availableTags.includes(tag));
        console.log('Filtered tags (only available ones):', filteredTags);
        relevantTags = filteredTags;
      } else {
        console.log('Parsed result is not an array, setting to empty array');
        relevantTags = [];
      }
    } catch (parseError) {
      console.error('Error parsing AI response:', parseError);
      console.error('Response that failed to parse:', aiResponse);
      relevantTags = [];
    }

    console.log('Final relevant tags to return:', relevantTags);
    console.log('=== END DEBUG ===');

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
