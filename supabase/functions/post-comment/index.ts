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
    const { itemId, content, parentCommentId, anonymous } = await req.json();

    console.log('Post comment request:', { 
      hasAuth: !!authHeader, 
      anonymous, 
      itemId, 
      contentLength: content?.length 
    });

    if (!itemId || !content) {
      return new Response(
        JSON.stringify({ error: 'Item ID and content are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Basic content validation and filtering
    const cleanContent = content.trim();
    if (cleanContent.length < 1 || cleanContent.length > 1000) {
      return new Response(
        JSON.stringify({ error: 'Comment must be between 1 and 1000 characters' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Simple spam filter
    const lowerContent = cleanContent.toLowerCase();
    const spamPatterns = [
      'viagra', 'casino', 'lottery', 'winner', 'congratulation',
      'click here', 'free money', 'earn money fast', 'weight loss miracle'
    ];
    
    if (spamPatterns.some(pattern => lowerContent.includes(pattern))) {
      return new Response(
        JSON.stringify({ error: 'Comment contains prohibited content' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    let userId: string;
    let userProfile: any = null;

    // Handle authenticated vs anonymous users
    if (authHeader && !anonymous) {
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
          JSON.stringify({ error: 'Invalid authentication' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      userId = user.id;
      
      // Get user profile
      const { data: profile } = await supabase
        .from('user_profiles')
        .select('username, display_name, avatar_url')
        .eq('id', userId)
        .single();
        
      userProfile = profile;
    } else {
      // Anonymous user - create a special anonymous user ID
      userId = '00000000-0000-0000-0000-000000000000'; // Special anonymous user ID
      userProfile = {
        username: 'anonymous',
        display_name: 'Anonymous',
        avatar_url: null
      };
    }

    // Use service role client for database operations
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    console.log(`Creating comment for item ${itemId} by ${anonymous ? 'anonymous' : `user ${userId}`}`);

    // Verify the item exists, is public, and has comments enabled
    const { data: item, error: itemError } = await supabase
      .from('items')
      .select('id, is_public, comments_enabled')
      .eq('id', itemId)
      .eq('is_public', true)
      .eq('comments_enabled', true)
      .single();

    if (itemError || !item) {
      console.log('Item verification failed:', { itemError, item });
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
        user_id: userId,
        content: cleanContent,
        parent_comment_id: parentCommentId || null
      })
      .select('id, content, created_at, updated_at, parent_comment_id, user_id')
      .single();

    if (commentError) {
      console.error('Error creating comment:', commentError);
      return new Response(
        JSON.stringify({ error: 'Failed to create comment' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Manually attach user profile data for response
    const commentWithProfile = {
      ...comment,
      user_profiles: userProfile
    };

    console.log(`Comment created successfully: ${comment.id} by ${anonymous ? 'anonymous' : userId}`);

    return new Response(
      JSON.stringify({ comment: commentWithProfile }),
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