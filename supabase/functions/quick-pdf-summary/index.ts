import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { fileUrl, itemId, fileName } = await req.json();
    console.log('Quick PDF summary request:', { itemId, fileName });

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    // Generate quick title from filename
    const quickTitle = fileName
      ?.replace(/\.[^/.]+$/, '') // Remove extension
      .replace(/[_-]/g, ' ') // Replace underscores and hyphens with spaces
      .replace(/\s+/g, ' ') // Normalize spaces
      .trim() || 'Document';

    // Call OpenAI to generate a better summary (quick, just first page analysis)
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
            content: 'You are a document analyzer. Generate a concise title (5-10 words) and a brief one-sentence description for documents. Be specific and descriptive.'
          },
          {
            role: 'user',
            content: `Based on the filename "${fileName}", generate a title and description. Title should be clear and descriptive. Description should be one sentence explaining what this document likely contains.`
          }
        ],
        max_tokens: 150,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      console.error('OpenAI API error:', response.status, await response.text());
      // Fallback to filename-based title
      return new Response(
        JSON.stringify({
          title: quickTitle,
          description: 'Document uploaded - analyzing content...',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const data = await response.json();
    const aiResponse = data.choices[0].message.content;
    
    // Parse AI response to extract title and description
    let title = quickTitle;
    let description = 'Document uploaded - analyzing content...';
    
    try {
      // Try to parse structured response
      const lines = aiResponse.split('\n').filter((l: string) => l.trim());
      if (lines.length >= 2) {
        title = lines[0].replace(/^(Title:|##\s*)/i, '').trim();
        description = lines[1].replace(/^(Description:|Summary:)/i, '').trim();
      } else if (lines.length === 1) {
        title = lines[0].trim();
      }
    } catch (e) {
      console.error('Error parsing AI response:', e);
    }

    // Update the item with quick summary
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { error: updateError } = await supabase
      .from('items')
      .update({
        title,
        description,
      })
      .eq('id', itemId);

    if (updateError) {
      console.error('Error updating item with quick summary:', updateError);
    } else {
      console.log('Quick summary updated successfully:', { itemId, title });
    }

    return new Response(
      JSON.stringify({ title, description }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in quick-pdf-summary:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});
