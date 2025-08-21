import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authorization required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader }
        }
      }
    );

    // Get the authenticated user
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const { itemId, content, parentCommentId } = await req.json();

    if (!itemId || !content) {
      return new Response(
        JSON.stringify({ error: 'Item ID and content are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Creating comment for item ${itemId} by user ${user.id}`);

    // Verify the item exists, is public, and has comments enabled
    const { data: item, error: itemError } = await supabase
      .from('items')
      .select('id, is_public, comments_enabled')
      .eq('id', itemId)
      .eq('is_public', true)
      .eq('comments_enabled', true)
      .single();

    if (itemError || !item) {
      return new Response(
        JSON.stringify({ error: 'Item not found, not public, or comments disabled' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create the comment
    const { data: comment, error: commentError } = await supabase
      .from('comments')
      .insert({
        item_id: itemId,
        user_id: user.id,
        content: content.trim(),
        parent_comment_id: parentCommentId || null
      })
      .select(`
        id,
        content,
        created_at,
        updated_at,
        parent_comment_id,
        user_id,
        user_profiles (
          username,
          display_name,
          avatar_url
        )
      `)
      .single();

    if (commentError) {
      console.error('Error creating comment:', commentError);
      return new Response(
        JSON.stringify({ error: 'Failed to create comment' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Comment created successfully: ${comment.id}`);

    return new Response(
      JSON.stringify({ comment }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});