
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
    const { message, conversationHistory } = await req.json();
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY');

    if (!openAIApiKey) {
      throw new Error('OpenAI API key not configured');
    }

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Supabase configuration missing');
    }

    // Get authorization header
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('No authorization header');
    }

    // Create Supabase client with user's auth token
    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      }
    });

    // Set the auth header for this request
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    
    if (userError || !user) {
      console.error('Authentication error:', userError);
      throw new Error('Authentication failed');
    }

    // Fetch all user's items using the authenticated client
    const { data: items, error: itemsError } = await supabase
      .from('items')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false });

    if (itemsError) {
      console.error('Items fetch error:', itemsError);
      throw new Error('Failed to fetch user items');
    }

    // Prepare context about all content
    let contentContext = `You are an AI assistant helping the user work with their personal content collection. The user has ${items.length} items in their stash.

Here's a summary of their content:

`;

    items.forEach((item, index) => {
      contentContext += `${index + 1}. Type: ${item.type}`;
      if (item.title) contentContext += `, Title: "${item.title}"`;
      if (item.content) contentContext += `, Content: "${item.content.substring(0, 200)}${item.content.length > 200 ? '...' : ''}"`;
      if (item.description) contentContext += `, AI Description: "${item.description.substring(0, 100)}${item.description.length > 100 ? '...' : ''}"`;
      contentContext += '\n';
    });

    contentContext += `
You can help the user:
- Search and find specific content
- Summarize their collection
- Answer questions about any items
- Help organize or categorize their content
- Provide insights across their entire collection
- Compare different items
- Suggest connections between items

Be helpful and conversational while working with their entire content collection.`;

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
    console.error('Error in chat-with-all-content function:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
