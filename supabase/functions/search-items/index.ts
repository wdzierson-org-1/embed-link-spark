import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { authenticateUser } from '../_shared/auth.ts';
import { normalizeSearchRequest, openAiEmbedder, searchItems } from '../_shared/search.ts';

// Canonical search surface for every retrieval consumer (web toolbar, chat
// tool-calling, MCP, iOS/Siri). The retrieval logic lives in
// _shared/search.ts so the mcp function's search_stash tool is the same code.
// Request:  { query?, types?, tags?, after?, before?, limit? }
// Response: { results: [{ id, title, type, url, created_at, description, snippet, score }] }

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { user, supabaseAdmin } = await authenticateUser(req.headers.get('Authorization'));
    const request = normalizeSearchRequest(await req.json().catch(() => ({})));

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (request.query && !openAIApiKey) {
      throw new Error('OPENAI_API_KEY not configured');
    }

    const results = await searchItems(request, {
      supabaseAdmin,
      userId: user.id,
      embed: openAiEmbedder(openAIApiKey ?? ''),
    });

    return new Response(JSON.stringify({ results }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in search-items:', error);
    const message = error instanceof Error ? error.message : 'Unknown error';
    const status = message.includes('Authentication') || message.includes('authorization') ? 401 : 500;
    return new Response(JSON.stringify({ error: message }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
