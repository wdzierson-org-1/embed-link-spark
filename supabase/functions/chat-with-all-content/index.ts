import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { authenticateUser } from '../_shared/auth.ts';

// Ask Stash — agentic retrieval. The model drives search itself through three
// tools (search_stash, browse_catalog, get_item) instead of a fixed
// retrieve-then-read pass: it rewrites queries from conversation context
// (follow-ups work), searches more than once for multi-part questions, and
// pulls full item text when a snippet isn't enough.
//
// Reliability model (spec 2026-08-29-ask-retrieval-reliability…): type/tag
// filters are SOFT — a backstop unfiltered search always runs alongside and
// close misses are surfaced labeled, so a wrong filter guess costs ranks, not
// the answer. browse_catalog lists the whole library (personal corpora are
// small) as the recall backstop for bare-word and fuzzy-recall queries. Every
// retrieval is logged to retrieval_log for goldens/QA.
//
// SSE wire contract (unchanged from the one-shot version, clients need no
// changes): `data:{delta}` tokens, then a terminal `data:{done, sources}`.
// OPTIONAL frames clients may ignore: `data:{status, query?}` while a
// tool runs (status: searching | browsing | reading). Sources are the items
// the answer actually cites (fallback: items it read in full), so citations
// stay honest.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const MODEL = 'gpt-5-mini';
const MAX_TOOL_ROUNDS = 5;
const MAX_HISTORY_MESSAGES = 10;
const SEARCH_DEFAULT_LIMIT = 8;
const SEARCH_MAX_LIMIT = 12;
// Backstop hits appended past the filtered group (soft filters, spec R1)
const SEARCH_EXTRA_LIMIT = 4;
const SNIPPET_CHARS = 300;
const ITEM_BODY_CHARS = 6000;
const ITEM_NOTES_CHARS = 4000;
const CATALOG_MAX_ITEMS = 1500;
const CATALOG_DESC_CHARS = 100;

// Canned product knowledge, available to every user regardless of what they've
// saved — so "how do I use Stash?" questions get real answers, especially for
// brand-new accounts with nothing stashed yet.
const APP_GUIDE = `
WHAT STASH IS: A personal memory app. Save links, notes, files, photos, voice
memos — Stash understands each one, describes it, and makes it findable later.

SAVING THINGS:
- On the home page, paste a link anywhere on the screen to capture it instantly.
- Drop files (images, PDFs, audio, video) onto the input box, or click to attach.
- Type (or dictate) a note straight into the input box.
- By phone: add your number in Settings → Phone Number, then text links, photos,
  or voice notes to your Stash WhatsApp/SMS number — no app needed.

WHAT HAPPENS AUTOMATICALLY: Links fetch their own title, preview image, and full
page text. PDFs are read and summarized. Voice notes are transcribed. Images are
analyzed. Everything gets suggested tags and becomes searchable.

FINDING THINGS: Search by keyword from the home page, filter by tag, or just ask
this assistant ("Ask Stash") — answers cite the saved items they came from.

EDITING: Click an item's title to open it. Title, description, and notes save
automatically as you type. You can add or replace an item's image, manage its
tags, or delete it from the same panel.

SHARING: In an item's edit panel, flip the Public Feed toggle to publish it to
your public page at gostash.it/feed/<your-username>. Shared items can carry a
yellow sticky note and receive comments. You can follow other people's feeds.

ACCOUNT: Settings covers your profile, phone number, tags, and subscription.
Stash is free for 14 days, then $4.99/month, cancel anytime.
`.trim();

const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'search_stash',
      description:
        "Search the user's saved items (hybrid semantic + keyword over titles, notes, summaries, and full captured text). Returns compact results with citation numbers. Call it more than once with different queries or filters for multi-part questions, and rephrase if the first results look irrelevant.",
      parameters: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description:
              "Focused search query. Rewrite the user's words; for follow-ups, resolve pronouns and references from the conversation first.",
          },
          types: {
            type: 'array',
            items: { type: 'string', enum: ['text', 'link', 'image', 'audio', 'video', 'document'] },
            description:
              'Prefer-these-types hint, NOT a hard restriction — close matches outside it are still returned, labeled. Storage types differ from user words: YouTube/web videos are "link" (flavor video), voice notes are "audio", "note" can be text or audio. Use only when confident.',
          },
          after: { type: 'string', description: 'ISO date — only items saved on or after this date.' },
          before: { type: 'string', description: 'ISO date — only items saved on or before this date.' },
          tags: { type: 'array', items: { type: 'string' }, description: 'Only items carrying any of these tags.' },
          limit: { type: 'integer', description: `Max results (default ${SEARCH_DEFAULT_LIMIT}, max ${SEARCH_MAX_LIMIT}).` },
        },
        required: ['query'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'browse_catalog',
      description:
        "List the user's ENTIRE library, one compact line per item (id · type · date saved · title · short description), newest first. Use it when the message is just a word or two, when the user's recall is fuzzy ('that site from a while ago'), for 'what do I have about…' questions, or whenever search results look wrong or incomplete. To cite an item found only here, read it with get_item first (that assigns its citation number).",
      parameters: { type: 'object', properties: {} },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_item',
      description:
        "Fetch one saved item in full: the user's own notes, the AI summary, and the captured source text (page scrape, transcript, OCR, document extraction). Use it when a search snippet isn't enough to answer accurately.",
      parameters: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'Item id from a search_stash result.' },
        },
        required: ['id'],
      },
    },
  },
];

interface RegistryEntry {
  n: number;
  id: string;
  title: string;
  type: string;
  url: string | null;
  fetchedInFull: boolean;
}

const stripHtml = (text: string): string => text.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

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

interface StreamedCompletion {
  content: string;
  toolCalls: Array<{ id: string; name: string; args: string }>;
}

// One streaming chat-completions call: forwards content tokens through onDelta
// as they arrive, accumulates tool-call fragments, returns both when done.
const streamCompletion = async (
  messages: unknown[],
  withTools: boolean,
  openAIApiKey: string,
  onDelta: (delta: string) => void,
): Promise<StreamedCompletion> => {
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      stream: true,
      messages,
      ...(withTools ? { tools: TOOLS } : {}),
      max_completion_tokens: 2500,
      reasoning_effort: 'low',
    }),
  });

  if (!response.ok || !response.body) {
    const errorText = await response.text();
    throw new Error(`OpenAI error ${response.status}: ${errorText.slice(0, 300)}`);
  }

  const decoder = new TextDecoder();
  const reader = response.body.getReader();
  let buffer = '';
  let content = '';
  const toolCalls: Array<{ id: string; name: string; args: string }> = [];

  while (true) {
    const { done, value } = await reader.read();
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
        const delta = JSON.parse(payload).choices?.[0]?.delta;
        if (!delta) continue;
        if (delta.content) {
          content += delta.content;
          onDelta(delta.content);
        }
        for (const tc of delta.tool_calls ?? []) {
          const idx = tc.index ?? 0;
          if (!toolCalls[idx]) toolCalls[idx] = { id: '', name: '', args: '' };
          if (tc.id) toolCalls[idx].id = tc.id;
          if (tc.function?.name) toolCalls[idx].name = tc.function.name;
          if (tc.function?.arguments) toolCalls[idx].args += tc.function.arguments;
        }
      } catch {
        // Ignore malformed keep-alive lines
      }
    }
  }

  return { content, toolCalls: toolCalls.filter(Boolean) };
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

    // Citation registry: every item surfaced to the model gets a stable [n],
    // assigned in order of first appearance across all tool calls.
    const registryById = new Map<string, RegistryEntry>();
    const registryByN: RegistryEntry[] = [];
    const register = (item: { id: string; title: string | null; type: string; url: string | null }): RegistryEntry => {
      let entry = registryById.get(item.id);
      if (!entry) {
        entry = {
          n: registryByN.length + 1,
          id: item.id,
          title: item.title || 'Untitled',
          type: item.type,
          url: item.url,
          fetchedInFull: false,
        };
        registryById.set(item.id, entry);
        registryByN.push(entry);
      }
      return entry;
    };

    // R6: every retrieval the agent runs is logged (service-role table,
    // non-fatal on failure) so quality is observable and goldens replayable.
    const logRetrieval = async (
      tool: string,
      query: string | null,
      filters: Record<string, unknown> | null,
      resultIds: string[] | null,
      resultCount: number,
    ) => {
      const { error } = await supabaseAdmin.from('retrieval_log').insert({
        user_id: user.id,
        tool,
        query,
        filters,
        result_ids: resultIds,
        result_count: resultCount,
      });
      if (error) console.error('retrieval_log insert failed:', error);
    };

    const runSearchStash = async (args: {
      query?: string; types?: string[]; after?: string; before?: string; tags?: string[]; limit?: number;
    }): Promise<string> => {
      const query = typeof args.query === 'string' ? args.query.trim() : '';
      if (!query) return 'Error: query is required.';
      const limit = Math.min(Math.max(Math.trunc(Number(args.limit) || SEARCH_DEFAULT_LIMIT), 1), SEARCH_MAX_LIMIT);
      const types = Array.isArray(args.types) && args.types.length ? args.types : null;
      const tags = Array.isArray(args.tags) && args.tags.length
        ? args.tags.map((t: string) => String(t).toLowerCase())
        : null;

      const queryEmbedding = await generateQueryEmbedding(query, openAIApiKey);
      const embeddingJson = JSON.stringify(queryEmbedding);

      // Soft filters (spec R1): type/tag filters are vocabulary guesses, so a
      // backstop query without them always runs too — dates stay hard, they're
      // explicit anchors. The 2026-08-30 failures were both filtered searches
      // that silently excluded the #1 unfiltered hit.
      const rpc = (soften: boolean) => supabaseAdmin.rpc('hybrid_search_content', {
        query_text: query,
        query_embedding: embeddingJson,
        target_user_id: user.id,
        match_count: Math.min(limit * 2, 30),
        filter_types: soften ? null : types,
        after_ts: args.after || null,
        before_ts: args.before || null,
        filter_tags: soften ? null : tags,
      });

      const hasSoftFilters = Boolean(types || tags);
      const [primary, backstop] = await Promise.all([
        rpc(false),
        hasSoftFilters ? rpc(true) : Promise.resolve(null),
      ]);
      if (primary.error) {
        console.error('search_stash RPC error:', primary.error);
        return 'Search failed — try again with a simpler query or no filters.';
      }

      // A backstop hit still "matches" if the requested type names its link
      // flavor: "video" should surface YouTube saves (type link, flavor video).
      const matchesTypes = (hit: { item_type: string; item_flavor: string | null }) =>
        !types || types.includes(hit.item_type) ||
        (hit.item_flavor != null && types.includes(hit.item_flavor));

      interface SearchHit {
        item_id: string; item_title: string | null; item_type: string; item_url: string | null;
        item_created_at: string | null; item_flavor: string | null; score: number;
        content_chunk: string | null; item_description: string | null;
      }

      // Select up to `limit` primary hits and up to SEARCH_EXTRA_LIMIT
      // backstop-only hits, then rank the union by score — both passes score
      // on the same RRF scale, and a strong hit the filter excluded should
      // outrank weak hits that merely matched the filter.
      const seen = new Set<string>();
      const chosen: Array<{ hit: SearchHit; outside: boolean }> = [];
      for (const hit of (primary.data ?? []) as SearchHit[]) {
        if (chosen.length >= limit) break;
        if (seen.has(hit.item_id)) continue;
        seen.add(hit.item_id);
        chosen.push({ hit, outside: false });
      }
      if (hasSoftFilters && backstop && !backstop.error) {
        let extras = 0;
        for (const hit of (backstop.data ?? []) as SearchHit[]) {
          if (extras >= SEARCH_EXTRA_LIMIT) break;
          if (seen.has(hit.item_id)) continue;
          seen.add(hit.item_id);
          chosen.push({ hit, outside: !matchesTypes(hit) });
          extras++;
        }
      }
      chosen.sort((a, b) => b.hit.score - a.hit.score);

      const blocks: string[] = [];
      const resultIds: string[] = [];
      for (const { hit, outside } of chosen) {
        const entry = register({ id: hit.item_id, title: hit.item_title, type: hit.item_type, url: hit.item_url });
        resultIds.push(hit.item_id);
        const saved = hit.item_created_at ? ` · saved ${hit.item_created_at.slice(0, 10)}` : '';
        const flavor = hit.item_flavor ? `/${hit.item_flavor}` : '';
        const label = outside ? ' — outside your filters, may still be it' : '';
        const snippet = (hit.content_chunk || hit.item_description || '').slice(0, SNIPPET_CHARS);
        blocks.push(`[${entry.n}] ${entry.title} (${entry.type}${flavor}${saved})${label} id:${entry.id}\n${snippet}`);
      }

      const filtersUsed = (types || tags || args.after || args.before)
        ? { types, tags, after: args.after || null, before: args.before || null }
        : null;
      await logRetrieval('search_stash', query, filtersUsed, resultIds, resultIds.length);

      if (!blocks.length) {
        return 'No results. Try a rephrased or broader query, or browse_catalog to see everything.';
      }
      return blocks.join('\n\n');
    };

    const runBrowseCatalog = async (): Promise<string> => {
      const { data, error } = await supabaseAdmin
        .from('items')
        .select('id, type, title, description, created_at, attributes')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(CATALOG_MAX_ITEMS + 1);
      if (error) {
        console.error('browse_catalog error:', error);
        return 'Catalog unavailable — use search_stash instead.';
      }
      const items = data ?? [];
      const truncated = items.length > CATALOG_MAX_ITEMS;
      const rows = items.slice(0, CATALOG_MAX_ITEMS).map((it) => {
        const flavor = it.attributes?.link?.flavor;
        const desc = (it.description || '').replace(/\s+/g, ' ').trim().slice(0, CATALOG_DESC_CHARS);
        return `${it.id} · ${it.type}${flavor ? `/${flavor}` : ''} · ${String(it.created_at).slice(0, 10)} · ${it.title || 'Untitled'}${desc ? ` — ${desc}` : ''}`;
      });
      await logRetrieval('browse_catalog', null, null, null, rows.length);
      if (!rows.length) return 'The library is empty — nothing saved yet.';
      return `Your library: ${rows.length} items, newest first${truncated ? ` (showing the ${CATALOG_MAX_ITEMS} most recent)` : ''}.\n${rows.join('\n')}`;
    };

    const runGetItem = async (args: { id?: string }): Promise<string> => {
      const id = typeof args.id === 'string' ? args.id.trim() : '';
      if (!id) return 'Error: id is required.';
      const { data: item, error } = await supabaseAdmin
        .from('items')
        .select('id, title, type, url, created_at, description, content, supplemental_note, summary, page_body, attributes')
        .eq('id', id)
        .eq('user_id', user.id)
        .maybeSingle();
      if (error || !item) return 'Item not found.';

      const entry = register(item);
      entry.fetchedInFull = true;

      const parts: string[] = [
        `[${entry.n}] ${entry.title} (${item.type} · saved ${String(item.created_at).slice(0, 10)})`,
      ];
      if (item.url) parts.push(`URL: ${item.url}`);
      const location = item.attributes?.location?.label;
      if (location) parts.push(`Saved at: ${location}`);
      if (item.description) parts.push(`Description: ${item.description}`);
      if (item.content) parts.push(`User's notes: ${stripHtml(item.content).slice(0, ITEM_NOTES_CHARS)}`);
      if (item.supplemental_note) parts.push(`Sticky note: ${item.supplemental_note}`);
      if (item.summary) parts.push(`Summary: ${item.summary}`);
      if (item.page_body) parts.push(`Captured text:\n${item.page_body.slice(0, ITEM_BODY_CHARS)}`);
      return parts.join('\n');
    };

    const today = new Date().toISOString().slice(0, 10);
    const systemPrompt = `You are Stash, the user's personal memory assistant. Today is ${today}.

For ANY question about the user's saved content, use the tools before answering — never assume something isn't saved without looking. Rewrite the user's words into focused queries; for follow-up questions, resolve pronouns and references from the conversation before searching. Date filters are reliable anchors ("last week" → after). Type filters are guesses — the stored type often differs from the user's word: YouTube and other web videos are saved as links (shown as link/video), voice notes and memos are audio, and "note" can mean a text note OR a voice note. Results labeled "outside your filters" are just as real as the rest — usually the filter guess was wrong, not the item missing. Use browse_catalog when the message is only a word or two, when recall is fuzzy ("that site from a while ago"), for "what do I have about…" questions, or when search results look irrelevant. NEVER tell the user something isn't saved until an unfiltered search or browse_catalog came up empty too. When several items could plausibly match a fuzzy memory, offer the top 2–4 candidates and ask which one they mean. Use get_item to read an item in full when a snippet isn't enough — especially before quoting details, and always before citing an item you found only in browse_catalog.

Answer using ONLY what the tools return, and cite the saved items you used. When you mention an item by name, write its title as a markdown link whose destination is the item's bracket number — like [Beyond the Basics](#3) — so the user can open the card directly. For claims that don't name the item, append the bare bracket number like [3] — but never add one to a sentence whose item title is already linked. Only cite items you actually used. Be concise and direct. If searching turned up nothing relevant, say so plainly and suggest different keywords. If the user asks how to use the Stash app itself, answer from the APP GUIDE (no citations, no search needed).

APP GUIDE:
${APP_GUIDE}`;

    const trimmedHistory = Array.isArray(conversationHistory)
      ? conversationHistory.slice(-MAX_HISTORY_MESSAGES)
      : [];

    const convo: unknown[] = [
      { role: 'system', content: systemPrompt },
      ...trimmedHistory,
      { role: 'user', content: message },
    ];

    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      async start(controller) {
        const emit = (event: Record<string, unknown>) => {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));
        };
        try {
          let finalText = '';
          let rounds = 0;

          while (true) {
            const withTools = rounds < MAX_TOOL_ROUNDS;
            const result = await streamCompletion(convo, withTools, openAIApiKey, (delta) => emit({ delta }));

            if (!result.toolCalls.length) {
              finalText = result.content;
              break;
            }

            convo.push({
              role: 'assistant',
              content: result.content || null,
              tool_calls: result.toolCalls.map((tc) => ({
                id: tc.id,
                type: 'function',
                function: { name: tc.name, arguments: tc.args },
              })),
            });

            for (const tc of result.toolCalls) {
              let args: Record<string, unknown> = {};
              try {
                args = JSON.parse(tc.args || '{}');
              } catch {
                // Malformed arguments — the tool handlers surface the problem
              }
              let output: string;
              if (tc.name === 'search_stash') {
                emit({ status: 'searching', query: args.query ?? '' });
                output = await runSearchStash(args);
              } else if (tc.name === 'browse_catalog') {
                emit({ status: 'browsing' });
                output = await runBrowseCatalog();
              } else if (tc.name === 'get_item') {
                emit({ status: 'reading' });
                output = await runGetItem(args);
              } else {
                output = `Unknown tool: ${tc.name}`;
              }
              convo.push({ role: 'tool', tool_call_id: tc.id, content: output });
            }
            rounds++;
          }

          // Sources = the items the answer cites — as bare [3] markers or as
          // [Title](#3) links — falling back to items it read in full. Each
          // entry carries its citation number `n` so clients can rewrite the
          // (#n) link targets into real item links.
          const citedNs = new Set(
            [...finalText.matchAll(/\[(\d+)\]|\(#(\d+)\)/g)].map((m) => Number(m[1] ?? m[2])),
          );
          let sourceEntries = registryByN.filter((e) => citedNs.has(e.n));
          if (!sourceEntries.length) {
            sourceEntries = registryByN.filter((e) => e.fetchedInFull);
          }
          const sources = sourceEntries.map((e) => ({ id: e.id, title: e.title, type: e.type, url: e.url, n: e.n }));

          emit({ done: true, sources });
        } catch (streamError) {
          console.error('Agent loop error:', streamError);
          emit({ error: 'Stream interrupted' });
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
