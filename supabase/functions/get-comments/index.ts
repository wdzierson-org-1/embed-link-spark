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
    
    console.log(`Full URL: ${req.url}`);
    console.log(`URL pathname: ${url.pathname}`);
    console.log(`Extracted itemId: ${itemId}`);

    if (!itemId) {
      console.log('No item ID provided in URL');
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

    console.log(`Item query result:`, { item, itemError });

    if (itemError || !item) {
      console.log(`Item not found or not public. Error: ${itemError?.message}, Item: ${item}`);
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
        user_id
      `)
      .eq('item_id', itemId)
      .order('created_at', { ascending: true });

    console.log(`Comments query result:`, { comments, commentsError });

    if (commentsError) {
      console.error('Error fetching comments:', commentsError);
      return new Response(
        JSON.stringify({ error: 'Failed to fetch comments' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Enrich comments with user profile data
    const enrichedComments = await Promise.all(
      (comments || []).map(async (comment) => {
        let userProfile;
        
        if (comment.user_id === '00000000-0000-0000-0000-000000000000') {
          // Anonymous user
          userProfile = {
            username: 'anonymous',
            display_name: 'Anonymous',
            avatar_url: null
          };
        } else {
          // Fetch real user profile
          const { data: profile } = await supabase
            .from('user_profiles')
            .select('username, display_name, avatar_url')
            .eq('id', comment.user_id)
            .single();
            
          userProfile = profile || {
            username: 'unknown',
            display_name: 'Unknown User',
            avatar_url: null
          };
        }
        
        return {
          ...comment,
          user_profiles: userProfile
        };
      })
    );

    // Simple content filter - remove obvious spam/abuse patterns
    const filteredComments = enrichedComments.filter(comment => {
      const content = comment.content.toLowerCase();
      const spamPatterns = [
        'viagra', 'casino', 'lottery', 'winner', 'congratulation',
        'click here', 'free money', 'earn money fast', 'weight loss miracle'
      ];
      return !spamPatterns.some(pattern => content.includes(pattern));
    });

    console.log(`Found ${enrichedComments.length} comments for item ${itemId}, ${filteredComments.length} after filtering`);

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