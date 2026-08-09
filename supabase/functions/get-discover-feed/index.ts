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
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    // Get authenticated user if available
    const authHeader = req.headers.get('authorization');
    let currentUserId: string | null = null;

    if (authHeader) {
      const { data: { user } } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
      currentUserId = user?.id ?? null;
    }

    const url = new URL(req.url);
    const searchParams = url.searchParams;
    const offset = parseInt(searchParams.get('offset') || '0');
    const limit = parseInt(searchParams.get('limit') || '20');
    const search = searchParams.get('search') || '';

    // Build base query for public items from users with public feeds enabled.
    // The !inner join is required so the public_feed_enabled filter excludes the
    // item rows themselves (a plain embed filter only nulls out the embed).
    let query = supabase
      .from('items')
      .select(`
        *,
        comment_count:comments(count),
        user_profile:user_profiles!items_user_id_fkey!inner(id, username, display_name, avatar_url, public_feed_enabled)
      `)
      .eq('is_public', true)
      .eq('user_profile.public_feed_enabled', true);

    // Exclude items from users the current user already follows
    if (currentUserId) {
      const { data: followingIds } = await supabase
        .from('user_follows')
        .select('following_id')
        .eq('follower_id', currentUserId);

      const ids = followingIds?.map(row => row.following_id) ?? [];
      if (ids.length > 0) {
        query = query.not('user_id', 'in', `(${ids.join(',')})`);
      }

      // Also exclude current user's own items
      query = query.neq('user_id', currentUserId);
    }

    // Add search filter if provided
    if (search) {
      query = query.or(`title.ilike.%${search}%, description.ilike.%${search}%, content.ilike.%${search}%`);
    }

    // Order by most recent and paginate
    query = query
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    const { data: items, error: itemsError } = await query;

    if (itemsError) {
      console.error('Error fetching discover feed:', itemsError);
      return new Response(JSON.stringify({ error: 'Failed to fetch items' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const processedItems = (items || []).map(item => ({
      ...item,
      comment_count: item.comment_count?.[0]?.count || 0,
      profile: item.user_profile
    }));

    // A full page means there may be more; avoids a second count query whose
    // filters could drift from the main query and silently break pagination
    const hasMore = (items?.length || 0) === limit;

    return new Response(JSON.stringify({
      items: processedItems,
      pagination: {
        offset,
        limit,
        total: offset + (items?.length || 0),
        hasMore
      }
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in get-discover-feed function:', error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
