// supabase/functions/mcp/index.ts
//
// Stash's MCP server: a stateless Streamable-HTTP endpoint (JSON-RPC over
// POST, JSON responses, no SSE, no sessions) exposing read-only retrieval to
// agents the user connected via OAuth. Spec:
// docs/superpowers/specs/2026-09-05-mcp-server-design.md. Wire contract for
// clients: docs/PLATFORM_API.md → "Agents (MCP)".
//
// Auth: Supabase Auth's OAuth 2.1 server issues the tokens; _shared/agentAuth
// verifies them and loads the user's grant for the calling client. Every
// tool call is written to agent_access_log (Settings → Connected agents →
// Activity) and rate-limited per grant.
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { authenticateAgent, type AgentGrant } from '../_shared/agentAuth.ts';
import {
  SUPPORTED_PROTOCOL_VERSIONS, errorResult, handleMcpMessage, parseJsonRpcBody, textResult,
  type McpServerSpec, type McpToolAnnotations, type McpToolDefinition, type McpToolResult,
} from '../_shared/mcpProtocol.ts';
import {
  ITEM_TYPES, SEARCH_MAX_LIMIT, normalizeSearchRequest, openAiEmbedder, searchItems,
} from '../_shared/search.ts';

// Task 1 decision (2026-09-05): the Vercel rewrite proxies POST bodies and the
// Authorization header, so the branded URL is the resource. Must equal the
// URL users paste into their agent, exactly.
const MCP_RESOURCE_URL = 'https://www.gostash.it/mcp';
// Web deep link for items without a URL of their own (notes, photos, memos) —
// the same `#item=<uuid>` convention the Ask citations use (PLATFORM_API.md).
// ChatGPT only cites results whose url is a non-empty string.
const ITEM_LINK_BASE = 'https://www.gostash.it/home#item=';
const SERVER_VERSION = '1.0.0';
const RATE_PER_MINUTE = 60;
const RATE_PER_DAY = 2000;
const ITEM_BODY_CHARS = 12000;
const ITEM_NOTES_CHARS = 4000;

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? 'https://uqqsgmwkvslaomzxptnp.supabase.co';
const AUTHORIZATION_SERVER = `${SUPABASE_URL}/auth/v1`;
const RESOURCE_METADATA_URL = `${MCP_RESOURCE_URL}/.well-known/oauth-protected-resource`;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, content-type, accept, mcp-protocol-version, mcp-session-id',
  'Access-Control-Expose-Headers': 'www-authenticate, mcp-protocol-version',
};

const json = (status: number, body: unknown, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  });

// RFC 9728 protected-resource metadata. Clients find it through the 401
// challenge below (Claude honors resource_metadata anywhere) or by probing
// /.well-known/oauth-protected-resource[/mcp] on the site (static copies).
const protectedResourceMetadata = () => ({
  resource: MCP_RESOURCE_URL,
  authorization_servers: [AUTHORIZATION_SERVER],
  scopes_supported: ['email'],
  bearer_methods_supported: ['header'],
  resource_name: 'Stash',
});

// SEP-2127 server card (draft, adopted by catalogs): who we are and how to
// connect, without tools (those are discovered at runtime). A static copy
// lives at the site root (public/.well-known/mcp-server-card.json).
const serverCard = () => ({
  $schema: 'https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json',
  name: 'it.gostash/stash',
  title: 'Stash',
  description: 'Search and read the links, notes, photos, voice memos and documents a Stash user saved, with their consent. Read-only.',
  version: SERVER_VERSION,
  websiteUrl: 'https://www.gostash.it',
  icons: [
    { src: 'https://www.gostash.it/icon-192.png', sizes: ['192x192'], mimeType: 'image/png' },
    { src: 'https://www.gostash.it/icon-512.png', sizes: ['512x512'], mimeType: 'image/png' },
  ],
  remotes: [{ type: 'streamable-http', url: MCP_RESOURCE_URL, supportedProtocolVersions: [...SUPPORTED_PROTOCOL_VERSIONS] }],
});

const discoveryResponse = (body: unknown) =>
  new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' },
  });

// RFC 6750 §3: a request with no credentials gets the bare challenge (no
// error code); bad or insufficient credentials name the error.
const challenge = (status: 401 | 403, error: string, description: string) => {
  const params: string[] = [];
  if (status === 401) params.push(`resource_metadata="${RESOURCE_METADATA_URL}"`, 'scope="email"');
  if (error !== 'missing_token') {
    params.push(`error="${error}"`, `error_description="${description.replace(/"/g, "'")}"`);
  }
  return json(status, { error, error_description: description }, { 'WWW-Authenticate': `Bearer ${params.join(', ')}` });
};

const stripHtml = (text: string): string => text.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

// Every tool is read-only; the Claude directory groups tools by these hints
// and rejects tools without a title or the read-only/destructive hint.
const READ_ONLY: McpToolAnnotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };

const TOOLS: McpToolDefinition[] = [
  {
    name: 'search_stash',
    title: 'Search the stash',
    description:
      "Search the user's personal Stash: links, notes, photos, voice memos and documents they saved. Hybrid semantic + keyword search over titles, the user's notes, captured page text, transcripts and OCR; results are relevance-ordered with one snippet each. Omit `query` to list the newest saves instead (optionally filtered by type, tag or date). Type filters are guesses — web videos are usually saved as links, voice memos as audio — so retry without them before concluding something isn't saved. Read a result in full with get_item before quoting it. Everything is scoped to the connected user.",
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'What to look for. Omit to list recent saves.' },
        types: { type: 'array', items: { type: 'string', enum: [...ITEM_TYPES] }, description: 'Restrict to item types.' },
        tags: { type: 'array', items: { type: 'string' }, description: 'Restrict to items carrying these tags.' },
        after: { type: 'string', description: 'ISO 8601 timestamp; only items saved after this.' },
        before: { type: 'string', description: 'ISO 8601 timestamp; only items saved before this.' },
        limit: { type: 'integer', minimum: 1, maximum: SEARCH_MAX_LIMIT, description: 'Max results (default 20).' },
      },
      additionalProperties: false,
    },
    annotations: READ_ONLY,
  },
  {
    name: 'get_item',
    title: 'Read a saved item',
    description:
      "Read one saved item in full by id (ids come from search_stash): the user's own notes, the AI description and summary, and the captured source text — page scrape, transcript, OCR or document text (capped at 12,000 characters). Use it before quoting details.",
    inputSchema: {
      type: 'object',
      properties: { id: { type: 'string', description: 'Item id from search_stash.' } },
      required: ['id'],
      additionalProperties: false,
    },
    annotations: READ_ONLY,
  },
  // ChatGPT connectors / deep research require tools named exactly `search`
  // and `fetch` with fixed result shapes. Same code paths as the two above.
  {
    name: 'search',
    title: 'Search the stash (ChatGPT-compatible)',
    description:
      "Search the user's saved items with a single query string. Same capability as search_stash, returned as { results: [{ id, title, url }] }. Use search_stash when you want filters or snippets; use fetch to read a result in full.",
    inputSchema: {
      type: 'object',
      properties: { query: { type: 'string', description: 'What to look for.' } },
      required: ['query'],
      additionalProperties: false,
    },
    annotations: READ_ONLY,
  },
  {
    name: 'fetch',
    title: 'Read a saved item (ChatGPT-compatible)',
    description:
      "Read one saved item in full by id (from search). Same capability as get_item, returned as { id, title, text, url, metadata }.",
    inputSchema: {
      type: 'object',
      properties: { id: { type: 'string', description: 'Item id from search.' } },
      required: ['id'],
      additionalProperties: false,
    },
    annotations: READ_ONLY,
  },
];

const INSTRUCTIONS =
  "Stash is this user's personal memory: the links, notes, photos, voice memos and files they chose to save. Search before assuming something isn't saved; date filters are reliable, type filters are guesses. Read an item with get_item before quoting it. You can search and read, nothing else.";

interface AccessLogRow {
  tool: string;
  query?: string | null;
  filters?: Record<string, unknown> | null;
  item_id?: string | null;
  item_title?: string | null;
  result_count?: number | null;
}

// deno-lint-ignore no-explicit-any
type Admin = any;

const rateLimited = async (admin: Admin, grant: AgentGrant): Promise<string | null> => {
  const now = Date.now();
  const count = async (sinceMs: number) => {
    const { count, error } = await admin
      .from('agent_access_log')
      .select('id', { count: 'exact', head: true })
      .eq('grant_id', grant.id)
      .gte('created_at', new Date(now - sinceMs).toISOString());
    if (error) { console.error('rate count failed:', error); return 0; }
    return count ?? 0;
  };
  if ((await count(60_000)) >= RATE_PER_MINUTE) {
    return `Rate limit reached for this agent (${RATE_PER_MINUTE} calls per minute). Try again in a minute.`;
  }
  if ((await count(86_400_000)) >= RATE_PER_DAY) {
    return `Daily limit reached for this agent (${RATE_PER_DAY} calls per day). Try again tomorrow.`;
  }
  return null;
};

const logAccess = async (admin: Admin, userId: string, grant: AgentGrant, row: AccessLogRow) => {
  const { error } = await admin.from('agent_access_log').insert({
    user_id: userId, grant_id: grant.id, client_id: grant.client_id, ...row,
  });
  if (error) console.error('agent_access_log insert failed:', error);
  const { error: bumpError } = await admin
    .from('agent_grants').update({ last_used_at: new Date().toISOString() }).eq('id', grant.id);
  if (bumpError) console.error('last_used_at update failed:', bumpError);
};

const runSearchStash = async (admin: Admin, userId: string, grant: AgentGrant, args: Record<string, unknown>): Promise<McpToolResult> => {
  const request = normalizeSearchRequest(args);
  const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
  if (request.query && !openAIApiKey) return errorResult('Search is temporarily unavailable.');

  const results = await searchItems(request, { supabaseAdmin: admin, userId, embed: openAiEmbedder(openAIApiKey ?? '') });

  const filters = (request.types.length || request.tags.length || request.after || request.before)
    ? { types: request.types, tags: request.tags, after: request.after, before: request.before }
    : null;
  await logAccess(admin, userId, grant, {
    tool: 'search_stash', query: request.query || null, filters, result_count: results.length,
  });

  if (!results.length) {
    return textResult(
      request.query
        ? 'No matches. Try broader or different words, drop the type filter, or omit query to list recent saves.'
        : 'Nothing saved under those filters yet.',
      { results: [], count: 0 },
    );
  }
  const lines = results.map((r, i) => {
    const saved = r.created_at ? ` · saved ${String(r.created_at).slice(0, 10)}` : '';
    const snippet = (r.snippet || r.description || '').replace(/\s+/g, ' ').trim();
    return `[${i + 1}] ${r.title || 'Untitled'} (${r.type}${saved}) id:${r.id}${snippet ? `\n${snippet}` : ''}`;
  });
  return textResult(lines.join('\n\n'), { results, count: results.length });
};

interface ReadItem {
  id: string; title: string; type: string; url: string | null; created_at: string;
  description: string | null; notes: string | null; sticky_note: string | null; summary: string | null;
  captured_text: string | null; truncated: boolean; flavor: string | null; location: string | null;
  text: string;
}

const isToolResult = (v: unknown): v is McpToolResult =>
  typeof v === 'object' && v !== null && Array.isArray((v as McpToolResult).content);

const itemLink = (id: string) => `${ITEM_LINK_BASE}${id}`;

// Shared by get_item and fetch: one item, scoped to the user, rendered once.
// Logs under the canonical tool name so the activity log reads the same
// whichever alias the client used.
const readItem = async (admin: Admin, userId: string, grant: AgentGrant, rawId: unknown, idSource: string): Promise<ReadItem | McpToolResult> => {
  const id = typeof rawId === 'string' ? rawId.trim() : '';
  if (!/^[0-9a-f-]{36}$/i.test(id)) return errorResult(`id must be an item id from ${idSource}.`);

  const { data: item, error } = await admin
    .from('items')
    .select('id, title, type, url, created_at, description, content, supplemental_note, summary, page_body, attributes')
    .eq('id', id)
    .eq('user_id', userId)
    .neq('type', 'collection')
    .maybeSingle();
  if (error) { console.error('get_item query failed:', error); return errorResult('Could not read that item right now.'); }
  if (!item) {
    await logAccess(admin, userId, grant, { tool: 'get_item', item_id: id, item_title: null, result_count: 0 });
    return errorResult('Item not found in this stash.');
  }

  await logAccess(admin, userId, grant, { tool: 'get_item', item_id: item.id, item_title: item.title ?? null, result_count: 1 });

  const flavor: string | null = item.attributes?.link?.flavor ?? null;
  const location: string | null = item.attributes?.location?.label ?? null;
  const notes = item.content ? stripHtml(item.content).slice(0, ITEM_NOTES_CHARS) : null;
  const fullBody = item.page_body ? String(item.page_body) : '';
  const body = fullBody ? fullBody.slice(0, ITEM_BODY_CHARS) : null;
  const truncated = fullBody.length > ITEM_BODY_CHARS;
  const title = item.title || 'Untitled';

  const parts: string[] = [`${title} (${item.type}${flavor ? `/${flavor}` : ''} · saved ${String(item.created_at).slice(0, 10)})`];
  if (item.url) parts.push(`URL: ${item.url}`);
  if (location) parts.push(`Saved at: ${location}`);
  if (item.description) parts.push(`Description: ${item.description}`);
  if (notes) parts.push(`User's notes: ${notes}`);
  if (item.supplemental_note) parts.push(`Sticky note: ${item.supplemental_note}`);
  if (item.summary) parts.push(`Summary: ${item.summary}`);
  if (body) parts.push(`Captured text:\n${body}${truncated ? '\n[truncated]' : ''}`);

  return {
    id: item.id, title, type: item.type, url: item.url ?? null, created_at: item.created_at,
    description: item.description ?? null, notes, sticky_note: item.supplemental_note ?? null, summary: item.summary ?? null,
    captured_text: body, truncated, flavor, location, text: parts.join('\n'),
  };
};

const runGetItem = async (admin: Admin, userId: string, grant: AgentGrant, args: Record<string, unknown>): Promise<McpToolResult> => {
  const r = await readItem(admin, userId, grant, args.id, 'search_stash');
  if (isToolResult(r)) return r;
  return textResult(r.text, {
    id: r.id, title: r.title, type: r.type, url: r.url, created_at: r.created_at,
    description: r.description, notes: r.notes, sticky_note: r.sticky_note, summary: r.summary,
    captured_text: r.captured_text, attributes: { link: r.flavor ? { flavor: r.flavor } : null, location: r.location ? { label: r.location } : null },
  });
};

// ChatGPT's contract: the structured object AND the same object JSON-encoded
// in the text item; `url` must be non-empty for a citation to be created.
const jsonResult = (structured: Record<string, unknown>): McpToolResult =>
  ({ content: [{ type: 'text', text: JSON.stringify(structured) }], structuredContent: structured });

const runSearch = async (admin: Admin, userId: string, grant: AgentGrant, args: Record<string, unknown>): Promise<McpToolResult> => {
  const query = typeof args.query === 'string' ? args.query.trim() : '';
  if (!query) return errorResult('query is required.');
  const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
  if (!openAIApiKey) return errorResult('Search is temporarily unavailable.');
  const request = normalizeSearchRequest({ query, limit: 10 });
  const results = await searchItems(request, { supabaseAdmin: admin, userId, embed: openAiEmbedder(openAIApiKey) });
  await logAccess(admin, userId, grant, { tool: 'search_stash', query, filters: null, result_count: results.length });
  return jsonResult({
    results: results.map((r) => ({ id: r.id, title: r.title || 'Untitled', url: r.url || itemLink(r.id) })),
  });
};

const runFetch = async (admin: Admin, userId: string, grant: AgentGrant, args: Record<string, unknown>): Promise<McpToolResult> => {
  const r = await readItem(admin, userId, grant, args.id, 'search');
  if (isToolResult(r)) return r;
  return jsonResult({
    id: r.id, title: r.title, text: r.text, url: r.url || itemLink(r.id),
    metadata: {
      type: r.type, created_at: r.created_at, flavor: r.flavor, location: r.location,
      description: r.description, summary: r.summary, truncated: r.truncated,
    },
  });
};

const buildSpec = (admin: Admin, userId: string, grant: AgentGrant): McpServerSpec => ({
  name: 'stash',
  version: SERVER_VERSION,
  instructions: INSTRUCTIONS,
  tools: TOOLS,
  callTool: async (name, args) => {
    const limited = await rateLimited(admin, grant);
    if (limited) return errorResult(limited);
    if (name === 'search_stash') return runSearchStash(admin, userId, grant, args);
    if (name === 'get_item') return runGetItem(admin, userId, grant, args);
    if (name === 'search') return runSearch(admin, userId, grant, args);
    if (name === 'fetch') return runFetch(admin, userId, grant, args);
    return errorResult(`Unknown tool: ${name}`);
  },
});

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });

  const path = new URL(req.url).pathname;
  if (req.method === 'GET' && path.endsWith('/.well-known/oauth-protected-resource')) return discoveryResponse(protectedResourceMetadata());
  if (req.method === 'GET' && path.endsWith('/.well-known/mcp-server-card')) return discoveryResponse(serverCard());
  if (req.method !== 'POST') {
    return json(405, { error: 'method_not_allowed', error_description: 'Send MCP JSON-RPC messages with POST.' }, { 'Allow': 'POST, OPTIONS' });
  }

  try {
    const auth = await authenticateAgent(req.headers.get('Authorization'));
    if (!auth.ok) return challenge(auth.status, auth.error, auth.description);

    const parsed = parseJsonRpcBody(await req.text());
    if (!parsed.ok) return json(parsed.response.status, parsed.response.body);

    const result = await handleMcpMessage(parsed.value, buildSpec(auth.supabaseAdmin, auth.user.id, auth.grant));
    if (result.status === 202) return new Response(null, { status: 202, headers: { ...corsHeaders, 'Cache-Control': 'no-store' } });
    return json(result.status, result.body);
  } catch (error) {
    console.error('Error in mcp:', error);
    return json(200, { jsonrpc: '2.0', id: null, error: { code: -32603, message: 'Internal error' } });
  }
});
