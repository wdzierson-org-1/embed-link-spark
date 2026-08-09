import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  console.log('Add note function called');

  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { 
          status: 405, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    // The item owner is always derived from a verified JWT, never from the request body
    const authHeader = req.headers.get('Authorization');
    const token = authHeader?.replace(/^Bearer\s+/i, '').trim();
    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization token' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired token' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    const body = await req.json();
    console.log('Request body:', body);

    const { content, title, is_public = false } = body;

    if (!content) {
      return new Response(
        JSON.stringify({ error: 'Content is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    const targetUserId = user.id;

    // Generate a title if not provided
    const noteTitle = title || (content.length > 50 ? content.substring(0, 47) + '...' : content);

    // Insert the note into the items table
    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: targetUserId,
        type: 'text',
        content: content,
        title: noteTitle,
        description: null,
        is_public: is_public,
        visibility: is_public ? 'public' : 'private'
      })
      .select()
      .single();

    if (error) {
      console.error('Error creating note:', error);
      return new Response(
        JSON.stringify({ error: 'Failed to create note', details: error.message }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }

    console.log('Note created successfully:', item.id);

    // Generate embeddings for the content
    if (content.trim()) {
      try {
        await supabase.functions.invoke('generate-embeddings', {
          body: {
            itemId: item.id,
            textContent: content
          }
        });
        console.log('Embeddings generated for note:', item.id);
      } catch (embeddingError) {
        console.error('Error generating embeddings:', embeddingError);
        // Don't fail the request if embeddings fail
      }
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        note: item,
        message: 'Note added successfully' 
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error instanceof Error ? error.message : 'Unknown error' }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});