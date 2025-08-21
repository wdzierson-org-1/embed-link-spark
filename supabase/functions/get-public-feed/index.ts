import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    );

    const url = new URL(req.url);
    const username = url.pathname.split('/').pop();
    const searchParams = url.searchParams;
    const offset = parseInt(searchParams.get('offset') || '0');
    const limit = parseInt(searchParams.get('limit') || '20');
    const search = searchParams.get('search') || '';
    
    if (!username) {
      return new Response(JSON.stringify({ error: 'Username is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    console.log(`Fetching public feed for username: ${username}, offset: ${offset}, limit: ${limit}, search: ${search}`);

    // Get user profile by username  
    const { data: profile, error: profileError } = await supabase
      .from('user_profiles')
      .select('id, username, display_name, bio, avatar_url, public_feed_enabled')
      .eq('username', username)
      .single();

    if (profileError || !profile) {
      console.error('Profile not found:', profileError);
      return new Response(JSON.stringify({ error: 'User not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (!profile.public_feed_enabled) {
      return new Response(JSON.stringify({ error: 'Public feed is disabled for this user' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Build query for public items
    let query = supabase
      .from('items')
      .select(`
        *,
        user_profiles!items_user_id_fkey (
          username,
          display_name,
          avatar_url
        )
      `)
      .eq('user_id', profile.id)
      .eq('is_public', true);

    // Add search filter if provided
    if (search) {
      query = query.or(`title.ilike.%${search}%, description.ilike.%${search}%, content.ilike.%${search}%`);
    }

    // Add ordering and pagination
    query = query
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    const { data: items, error: itemsError } = await query;

    if (itemsError) {
      console.error('Error fetching public items:', itemsError);
      return new Response(JSON.stringify({ error: 'Failed to fetch items' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Get total count for pagination info
    const { count, error: countError } = await supabase
      .from('items')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', profile.id)
      .eq('is_public', true);

    console.log(`Found ${items?.length || 0} public items for ${username}`);

    return new Response(JSON.stringify({
      profile: {
        username: profile.username,
        display_name: profile.display_name,
        bio: profile.bio,
        avatar_url: profile.avatar_url
      },
      items: items || [],
      pagination: {
        offset,
        limit,
        total: count || 0,
        hasMore: (count || 0) > offset + (items?.length || 0)
      }
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in get-public-feed function:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});