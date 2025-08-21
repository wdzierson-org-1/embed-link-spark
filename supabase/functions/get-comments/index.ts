import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    const url = new URL(req.url);
    const itemId = url.pathname.split('/').pop();

    if (!itemId) {
      return new Response(
        JSON.stringify({ error: 'Item ID is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`Fetching comments for item: ${itemId}`);

    // First verify the item exists and is public
    const { data: item, error: itemError } = await supabase
      .from('items')
      .select('id, is_public, comments_enabled')
      .eq('id', itemId)
      .eq('is_public', true)
      .single();

    if (itemError || !item) {
      return new Response(
        JSON.stringify({ error: 'Item not found or not public' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!item.comments_enabled) {
      return new Response(
        JSON.stringify({ comments: [], commentsEnabled: false }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Fetch comments with user profile information
    const { data: comments, error: commentsError } = await supabase
      .from('comments')
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
      .eq('item_id', itemId)
      .order('created_at', { ascending: true });

    if (commentsError) {
      console.error('Error fetching comments:', commentsError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch comments' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Simple content filter - remove obvious spam/abuse patterns
    const filteredComments = (comments || []).filter(comment => {
      const content = comment.content.toLowerCase();
      const spamPatterns = [
        'viagra', 'casino', 'lottery', 'winner', 'congratulation',
        'click here', 'free money', 'earn money fast', 'weight loss miracle'
      ];
      return !spamPatterns.some(pattern => content.includes(pattern));
    });

    console.log(`Found ${comments?.length || 0} comments for item ${itemId}, ${filteredComments.length} after filtering`);

    return new Response(
      JSON.stringify({ 
        comments: filteredComments, 
        commentsEnabled: true 
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});