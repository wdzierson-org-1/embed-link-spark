import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { authenticateUser } from './auth.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface HybridHit {
  item_id: string;
  content_chunk: string;
  item_title: string | null;
  item_type: string;
  item_url: string | null;
  score: number;
}

const MAX_CHARS_PER_ITEM = 1500;
const MAX_CONTEXT_CHARS = 7000;
const MAX_HISTORY_MESSAGES = 6;

const generateQueryEmbedding = async (text: string, openAIApiKey: string): Promise<number[]> => {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: text }),
  });

  if (!response.ok) {
    throw new Error(`Embedding request failed: ${response.status}`);
  }

  const data = await response.json();
  return data.data[0].embedding;
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { user, supabaseAdmin } = await authenticateUser(req.headers.get('Authorization'));
    const { message, conversationHistory = [] } = await req.json();

    if (!message || typeof message !== 'string') {
      return new Response(JSON.stringify({ error: 'Message is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
    if (!openAIApiKey) {
      throw new Error('OPENAI_API_KEY not configured');
    }

    // Hybrid retrieval: vector chunks + full-text item matches, RRF-fused in SQL
    let hits: HybridHit[] = [];
    try {
      const queryEmbedding = await generateQueryEmbedding(message, openAIApiKey);
      const { data, error } = await supabaseAdmin.rpc('hybrid_search_content', {
        query_text: message,
        query_embedding: JSON.stringify(queryEmbedding),
        target_user_id: user.id,
        match_count: 12,
      });
      if (error) {
        console.error('Hybrid search error:', error);
      } else {
        hits = data || [];
      }
    } catch (searchError) {
      console.error('Retrieval failed, answering without context:', searchError);
    }

    // Group chunks by item in relevance order; the numbered context blocks and
    // the citations shown to the user are the SAME items, in the same order
    const itemOrder: string[] = [];
    const byItem = new Map<string, { title: string; type: string; url: string | null; chunks: string[] }>();
    for (const hit of hits) {
      if (!byItem.has(hit.item_id)) {
        byItem.set(hit.item_id, {
          title: hit.item_title || 'Untitled',
          type: hit.item_type,
          url: hit.item_url,
          chunks: [],
        });
        itemOrder.push(hit.item_id);
      }
      byItem.get(hit.item_id)!.chunks.push(hit.content_chunk);
    }

    const sources: Array<{ id: string; title: string; type: string; url: string | null }> = [];
    const contextBlocks: string[] = [];
    let totalChars = 0;

    for (const itemId of itemOrder) {
      if (totalChars >= MAX_CONTEXT_CHARS) break;
      const item = byItem.get(itemId)!;
      let text = item.chunks.join('\n').slice(0, MAX_CHARS_PER_ITEM);
      if (totalChars + text.length > MAX_CONTEXT_CHARS) {
        text = text.slice(0, MAX_CONTEXT_CHARS - totalChars);
      }
      totalChars += text.length;
      sources.push({ id: itemId, title: item.title, type: item.type, url: item.url });
      contextBlocks.push(`[${sources.length}] ${item.title} (${item.type})\n${text}`);
    }

    const systemPrompt = contextBlocks.length > 0
      ? `You are Stash, the user's personal memory assistant. Answer using ONLY the saved items below. Cite items inline with their bracket number, like [1]. Be concise and direct. If the saved items don't actually contain the answer, say so plainly instead of guessing.

SAVED ITEMS:
${contextBlocks.join('\n\n')}`
      : `You are Stash, the user's personal memory assistant. No saved items matched this question. Say plainly that you couldn't find anything relevant in their stash, and suggest they try different keywords or save the information first. Do not invent content.`;

    const trimmedHistory = Array.isArray(conversationHistory)
      ? conversationHistory.slice(-MAX_HISTORY_MESSAGES)
      : [];

    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4.1-mini',
        stream: true,
        messages: [
          { role: 'system', content: systemPrompt },
          ...trimmedHistory,
          { role: 'user', content: message },
        ],
        max_tokens: 1200,
        temperature: 0.3,
      }),
    });

    if (!openaiResponse.ok || !openaiResponse.body) {
      const errorText = await openaiResponse.text();
      console.error('OpenAI error:', openaiResponse.status, errorText);
      return new Response(JSON.stringify({ error: 'AI request failed' }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Proxy OpenAI's SSE stream as our own: {delta} events, then {done, sources}
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const upstream = openaiResponse.body.getReader();

    const stream = new ReadableStream({
      async start(controller) {
        let buffer = '';
        try {
          while (true) {
            const { done, value } = await upstream.read();
            if (done) break;
            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split('\n');
            buffer = lines.pop() || '';
            for (const line of lines) {
              const trimmed = line.trim();
              if (!trimmed.startsWith('data:')) continue;
              const payload = trimmed.slice(5).trim();
              if (payload === '[DONE]') continue;
              try {
                const delta = JSON.parse(payload).choices?.[0]?.delta?.content;
                if (delta) {
                  controller.enqueue(encoder.encode(`data: ${JSON.stringify({ delta })}\n\n`));
                }
              } catch {
                // Ignore malformed keep-alive lines
              }
            }
          }
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true, sources })}\n\n`));
        } catch (streamError) {
          console.error('Stream proxy error:', streamError);
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: 'Stream interrupted' })}\n\n`));
        } finally {
          controller.close();
        }
      },
    });

    return new Response(stream, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    });
  } catch (error) {
    console.error('Error in chat-with-all-content:', error);
    const message = error instanceof Error ? error.message : 'Unknown error';
    const status = message.includes('Authentication') || message.includes('authorization') ? 401 : 500;
    return new Response(JSON.stringify({ error: message }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
