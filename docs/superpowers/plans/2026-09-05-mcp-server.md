# Stash MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only remote MCP server (`https://www.gostash.it/mcp`) that any OAuth-capable agent can connect to, with per-agent grants, a user-readable activity log, one-tap revocation, and an architectural fence so agent tokens can only ever get answers, never copies.

**Architecture:** A Supabase edge function (`mcp`) speaks stateless MCP Streamable HTTP (JSON-RPC over POST, JSON responses) behind a Vercel rewrite. Auth is Supabase Auth's OAuth 2.1 server (discovery, dynamic registration, consent API, grant revocation); our React consent page approves requests and records a grant row; the function checks that row on every call and logs every tool call. Retrieval reuses the `search-items` core, extracted into a shared module.

**Tech Stack:** Deno edge functions (Supabase), Postgres RLS, Vite + React + shadcn (web), vitest, Node 18+ smoke script, Supabase Management API for SQL and auth config.

**Spec:** `docs/superpowers/specs/2026-09-05-mcp-server-design.md`

## Global Constraints

- Endpoint users paste: `https://www.gostash.it/mcp` (Task 1 may downgrade to `https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp`; then `MCP_RESOURCE_URL` and the copy in Task 8 change together).
- Authorization server issuer: `https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1`; metadata at `https://uqqsgmwkvslaomzxptnp.supabase.co/.well-known/oauth-authorization-server/auth/v1`.
- OAuth scope pinned to `email` everywhere (401 challenge, protected-resource metadata, smoke script). Never request `openid`.
- Tools v1: `search_stash`, `get_item`. Read-only. No bulk/export tool.
- Scope vocabulary: `['read']` only; column is `text[]`.
- Rate limits per grant: 60 tool calls / rolling 60s, 2,000 / rolling 24h.
- Caps in `get_item`: notes 4,000 chars, captured text 12,000 chars. Search: default limit 20, max 50, snippet 280 chars (unchanged from `search-items`).
- Data lanes: `content` = user's words, `description`/`summary` = AI text, `page_body` = captured source. `attributes` exposed only as `link.flavor` and `location.label`.
- Copy: active voice, sentence case, plain verbs, no apology (DESIGN.md "Voice & copy"). Web UI uses existing tokens only; no new fonts/colors/radii.
- Every edge function that derives a user from a Bearer token rejects agent tokens (JWT with a `client_id` claim) except `mcp`.
- Edge functions deploy with `supabase functions deploy <name> --project-ref uqqsgmwkvslaomzxptnp`; `supabase/config.toml` must match deployed state (`[functions.mcp] verify_jwt = false`).
- DB changes go through the Management API `database/query` endpoint with the keychain token (see "Recipes"); record each migration in `supabase_migrations.schema_migrations`.
- Web ships by pushing `main` (Vercel auto-deploy). Work on branch `feat/mcp-server` in a worktree (superpowers:using-git-worktrees); fast-forward merge into `main` and push only at the deploy points named in Tasks 1, 8, and 11. Never `git add -A` — this checkout carries unrelated untracked files (`docs/gtm/`, other specs).
- Tests: `npm test` (vitest) for pure modules; `npx tsc --noEmit -p tsconfig.app.json` for the web app. Edge-function shells are verified live with curl.

## Recipes

**Management API token** (macOS keychain):
```bash
TOKEN=$(security find-generic-password -s "Supabase CLI" -a "supabase" -w | sed 's/^go-keyring-base64://' | base64 -d)
```
**Run SQL** (use curl, not Python — urllib gets 403):
```bash
q() { curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query \
  -d "{\"query\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")}"; echo; }
```
**Run a SQL file:** `q "$(cat supabase/migrations/<file>.sql)"`
**Test account for browser checks:** `will+uitest@dzierson.com`, password in gitignored `ios/.env.test.local` (`STASH_TEST_*`).

## File structure

| File | Responsibility |
|---|---|
| `supabase/functions/_shared/mcpProtocol.ts` | Pure MCP JSON-RPC core (initialize/ping/tools.list/tools.call, batches, notifications). No imports. |
| `supabase/functions/_shared/mcpProtocol.test.ts` | vitest for the core. |
| `supabase/functions/_shared/search.ts` | Retrieval core extracted from `search-items`: request normalization + hybrid/filter search. |
| `supabase/functions/_shared/search.test.ts` | vitest for `normalizeSearchRequest`. |
| `supabase/functions/_shared/agentToken.ts` | Pure JWT-payload helpers: `bearerToken`, `decodeJwtPayload`, `agentClientId`, `isAgentToken`. |
| `supabase/functions/_shared/agentToken.test.ts` | vitest. |
| `supabase/functions/_shared/auth.ts` | Existing `authenticateUser` + new `assertNotAgentToken`. |
| `supabase/functions/_shared/agentAuth.ts` | `authenticateAgent(authHeader)` → user + grant, or 401/403 failure. |
| `supabase/functions/mcp/index.ts` | HTTP shell: routes, protected-resource metadata, 401 challenge, tool implementations, audit log, rate limit. |
| `supabase/functions/search-items/index.ts` | Becomes a thin shell over `_shared/search.ts`. |
| 11 other functions | Two-line agent-token guard each (Task 5). |
| `supabase/migrations/20260905120000_agent_grants_and_access_log.sql` | Tables, RLS, `is_agent_token()`, restrictive fence policies. |
| `supabase/config.toml` | `[functions.mcp]`, `[auth.oauth_server]`. |
| `vercel.json` | `/mcp` rewrites, static metadata headers. |
| `public/.well-known/oauth-protected-resource/mcp` | Static protected-resource metadata (best effort). |
| `src/integrations/supabase/types.ts` | Row types for the two new tables. |
| `src/utils/oauthConsent.ts` (+ test) | GoTrue OAuth REST calls + pure helpers (redirect detection, loopback detection, return-to URL). |
| `src/pages/OAuthConsent.tsx` | The consent page at `/oauth/consent`. |
| `src/utils/agentActivity.ts` (+ test) | Log row → sentence. |
| `src/hooks/useConnectedAgents.ts` | Loads grants + activity; revokes. |
| `src/components/settings/ConnectedAgentsSettings.tsx` | Settings tab UI. |
| `src/pages/Settings.tsx`, `src/App.tsx` | Tab + route wiring. |
| `scripts/mcp-smoke.mjs` | End-to-end OAuth + tool + fence + revocation smoke test. |
| `docs/PLATFORM_API.md`, `docs/ui-changes.md` | Contract docs. |

---

### Task 1: Endpoint spike — prove the Vercel rewrite, fix the resource URL

**Files:**
- Create: `supabase/functions/mcp/index.ts` (temporary echo stub; replaced in Task 6)
- Modify: `vercel.json`
- Modify: `supabase/config.toml`

**Interfaces:**
- Produces: the decision `MCP_RESOURCE_URL` (either `https://www.gostash.it/mcp` or the raw function URL), recorded at the top of `supabase/functions/mcp/index.ts` in Task 6 and in the Task 8 copy.

- [ ] **Step 1: Write the echo stub**

```ts
// supabase/functions/mcp/index.ts — TEMPORARY spike stub (Task 1). Replaced in Task 6.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  const url = new URL(req.url);
  const body = req.method === 'POST' ? await req.text() : null;
  return new Response(JSON.stringify({
    spike: true,
    method: req.method,
    path: url.pathname,
    hasAuthorization: req.headers.has('authorization'),
    contentType: req.headers.get('content-type'),
    body,
  }), { status: 200, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
});
```

- [ ] **Step 2: Register the function as public in config.toml**

Append to `supabase/config.toml` after the `[functions.summarize-content]` block:

```toml
# MCP endpoint: auth is checked in-function so unauthenticated requests get
# the RFC 9728 WWW-Authenticate challenge instead of the gateway's opaque 401.
[functions.mcp]
verify_jwt = false
```

- [ ] **Step 3: Add the rewrites**

Replace `vercel.json` with:

```json
{
  "rewrites": [
    { "source": "/mcp", "destination": "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp" },
    { "source": "/mcp/:path*", "destination": "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp/:path*" },
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

- [ ] **Step 4: Deploy the stub and verify it directly**

```bash
supabase functions deploy mcp --project-ref uqqsgmwkvslaomzxptnp
supabase functions list --project-ref uqqsgmwkvslaomzxptnp | grep mcp
curl -s -X POST https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp \
  -H "Authorization: Bearer test" -H "Content-Type: application/json" -d '{"hello":1}'
```
Expected: JSON with `"spike":true`, `"hasAuthorization":true`, `"body":"{\"hello\":1}"`. (No `apikey` header is needed with `verify_jwt = false`; `twilio-webhook` is the existing precedent.)

- [ ] **Step 5: Commit, merge to main, push (deploy point)**

```bash
git add vercel.json supabase/config.toml supabase/functions/mcp/index.ts
git commit -m "feat(mcp): endpoint spike — /mcp rewrite + public echo function"
# from the main checkout:
git merge --ff-only feat/mcp-server && git push origin main
```

- [ ] **Step 6: Verify through the rewrite once Vercel deploys (~1–2 min)**

```bash
curl -s -X POST https://www.gostash.it/mcp -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" -d '{"hello":1}'
curl -s https://www.gostash.it/mcp/.well-known/oauth-protected-resource
```
Expected: both return the stub JSON; the POST shows `hasAuthorization:true` and the body; the GET shows `path` ending in `/mcp/.well-known/oauth-protected-resource`.

Decision: if both pass, `MCP_RESOURCE_URL = 'https://www.gostash.it/mcp'`. If the POST body or Authorization header is missing, set `MCP_RESOURCE_URL = 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp'`, remove the two `/mcp` rewrites, and note the outcome in the plan's "Outcome" section at the bottom.

---

### Task 2: MCP protocol core (pure, tested)

**Files:**
- Create: `supabase/functions/_shared/mcpProtocol.ts`
- Test: `supabase/functions/_shared/mcpProtocol.test.ts`

**Interfaces:**
- Produces:
  - `interface McpToolDefinition { name: string; title?: string; description: string; inputSchema: Record<string, unknown> }`
  - `interface McpToolResult { content: Array<{ type: 'text'; text: string }>; structuredContent?: Record<string, unknown>; isError?: boolean }`
  - `interface McpServerSpec { name: string; version: string; instructions?: string; tools: McpToolDefinition[]; callTool(name: string, args: Record<string, unknown>): Promise<McpToolResult> }`
  - `interface McpHttpResult { status: 200 | 202 | 400; body: unknown | null }`
  - `handleMcpMessage(payload: unknown, spec: McpServerSpec): Promise<McpHttpResult>`
  - `parseJsonRpcBody(raw: string): { ok: true; value: unknown } | { ok: false; response: McpHttpResult }`
  - `textResult(text, structured?)`, `errorResult(text)`, `negotiateProtocolVersion(requested)`, `LATEST_PROTOCOL_VERSION`

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/_shared/mcpProtocol.test.ts
import { describe, expect, it, vi } from 'vitest';
import {
  LATEST_PROTOCOL_VERSION, errorResult, handleMcpMessage, negotiateProtocolVersion,
  parseJsonRpcBody, textResult, type McpServerSpec,
} from './mcpProtocol';

const spec = (): McpServerSpec => ({
  name: 'stash',
  version: '1.0.0',
  instructions: 'Search first.',
  tools: [{ name: 'search_stash', description: 'Search', inputSchema: { type: 'object', properties: {} } }],
  callTool: vi.fn(async (name, args) => textResult(`${name}:${JSON.stringify(args)}`, { ok: true })),
});

describe('negotiateProtocolVersion', () => {
  it('echoes a supported version and falls back to the latest otherwise', () => {
    expect(negotiateProtocolVersion('2025-06-18')).toBe('2025-06-18');
    expect(negotiateProtocolVersion('1999-01-01')).toBe(LATEST_PROTOCOL_VERSION);
    expect(negotiateProtocolVersion(undefined)).toBe(LATEST_PROTOCOL_VERSION);
  });
});

describe('handleMcpMessage', () => {
  it('answers initialize with capabilities, server info and instructions', async () => {
    const res = await handleMcpMessage(
      { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {} } },
      spec(),
    );
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      jsonrpc: '2.0', id: 1,
      result: { protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'stash', version: '1.0.0' }, instructions: 'Search first.' },
    });
  });

  it('accepts notifications with 202 and no body', async () => {
    const res = await handleMcpMessage({ jsonrpc: '2.0', method: 'notifications/initialized' }, spec());
    expect(res).toEqual({ status: 202, body: null });
  });

  it('answers ping and tools/list', async () => {
    expect(await handleMcpMessage({ jsonrpc: '2.0', id: 'a', method: 'ping' }, spec())).toEqual({
      status: 200, body: { jsonrpc: '2.0', id: 'a', result: {} },
    });
    const list = await handleMcpMessage({ jsonrpc: '2.0', id: 2, method: 'tools/list' }, spec());
    expect(list.body).toMatchObject({ result: { tools: [{ name: 'search_stash' }] } });
  });

  it('runs tools/call and passes arguments through', async () => {
    const s = spec();
    const res = await handleMcpMessage(
      { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'search_stash', arguments: { query: 'x' } } }, s,
    );
    expect(s.callTool).toHaveBeenCalledWith('search_stash', { query: 'x' });
    expect(res.body).toMatchObject({ id: 3, result: { content: [{ type: 'text', text: 'search_stash:{"query":"x"}' }], structuredContent: { ok: true } } });
  });

  it('rejects unknown tools and non-object arguments with -32602', async () => {
    const bad = await handleMcpMessage({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'nope' } }, spec());
    expect(bad.body).toMatchObject({ id: 4, error: { code: -32602 } });
    const badArgs = await handleMcpMessage(
      { jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'search_stash', arguments: [1] } }, spec(),
    );
    expect(badArgs.body).toMatchObject({ id: 5, error: { code: -32602 } });
  });

  it('turns a throwing tool into an isError result, not a protocol error', async () => {
    const s = spec();
    (s.callTool as ReturnType<typeof vi.fn>).mockRejectedValueOnce(new Error('boom'));
    const res = await handleMcpMessage({ jsonrpc: '2.0', id: 6, method: 'tools/call', params: { name: 'search_stash', arguments: {} } }, s);
    expect(res.body).toMatchObject({ id: 6, result: { isError: true, content: [{ type: 'text', text: expect.stringContaining('boom') }] } });
  });

  it('returns -32601 for unknown methods and -32600 for malformed messages', async () => {
    expect((await handleMcpMessage({ jsonrpc: '2.0', id: 7, method: 'resources/list' }, spec())).body)
      .toMatchObject({ id: 7, error: { code: -32601 } });
    expect((await handleMcpMessage({ id: 8, method: 'ping' }, spec())).body).toMatchObject({ id: 8, error: { code: -32600 } });
    expect((await handleMcpMessage('nonsense', spec())).body).toMatchObject({ id: null, error: { code: -32600 } });
  });

  it('handles batches: responses only for requests; all-notifications → 202', async () => {
    const mixed = await handleMcpMessage(
      [{ jsonrpc: '2.0', method: 'notifications/initialized' }, { jsonrpc: '2.0', id: 9, method: 'ping' }], spec(),
    );
    expect(mixed).toEqual({ status: 200, body: [{ jsonrpc: '2.0', id: 9, result: {} }] });
    expect(await handleMcpMessage([{ jsonrpc: '2.0', method: 'notifications/cancelled' }], spec())).toEqual({ status: 202, body: null });
    expect((await handleMcpMessage([], spec())).status).toBe(400);
  });

  it('ignores client responses (messages with result/error and no method)', async () => {
    expect(await handleMcpMessage({ jsonrpc: '2.0', id: 1, result: {} }, spec())).toEqual({ status: 202, body: null });
  });
});

describe('parseJsonRpcBody', () => {
  it('parses JSON and maps parse failures to a -32700 400', () => {
    expect(parseJsonRpcBody('{"a":1}')).toEqual({ ok: true, value: { a: 1 } });
    const bad = parseJsonRpcBody('{nope');
    expect(bad.ok).toBe(false);
    if (!bad.ok) expect(bad.response).toMatchObject({ status: 400, body: { error: { code: -32700 } } });
  });
});

describe('result helpers', () => {
  it('build text and error results', () => {
    expect(textResult('hi')).toEqual({ content: [{ type: 'text', text: 'hi' }] });
    expect(textResult('hi', { n: 1 })).toEqual({ content: [{ type: 'text', text: 'hi' }], structuredContent: { n: 1 } });
    expect(errorResult('no')).toEqual({ content: [{ type: 'text', text: 'no' }], isError: true });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run supabase/functions/_shared/mcpProtocol.test.ts`
Expected: FAIL — cannot resolve `./mcpProtocol`.

- [ ] **Step 3: Implement the core**

```ts
// supabase/functions/_shared/mcpProtocol.ts
//
// Pure MCP core for a stateless, tools-only server over Streamable HTTP
// (spec: https://modelcontextprotocol.io/specification — basic/transports).
// Deliberately dependency-free: it runs under Deno in the `mcp` edge function
// and under vitest on the web toolchain. The HTTP shell owns auth, headers and
// status codes; this module owns JSON-RPC semantics.

export const SUPPORTED_PROTOCOL_VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26'] as const;
export const LATEST_PROTOCOL_VERSION: string = SUPPORTED_PROTOCOL_VERSIONS[0];

export interface McpToolDefinition {
  name: string;
  title?: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

export interface McpToolResult {
  content: Array<{ type: 'text'; text: string }>;
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
}

export interface McpServerSpec {
  name: string;
  version: string;
  instructions?: string;
  tools: McpToolDefinition[];
  callTool: (name: string, args: Record<string, unknown>) => Promise<McpToolResult>;
}

export interface McpHttpResult {
  status: 200 | 202 | 400;
  body: unknown | null;
}

type JsonRpcId = string | number | null;

export const textResult = (text: string, structured?: Record<string, unknown>): McpToolResult =>
  structured ? { content: [{ type: 'text', text }], structuredContent: structured } : { content: [{ type: 'text', text }] };

export const errorResult = (text: string): McpToolResult => ({ content: [{ type: 'text', text }], isError: true });

const rpcResult = (id: JsonRpcId, result: unknown) => ({ jsonrpc: '2.0', id, result });
const rpcError = (id: JsonRpcId, code: number, message: string) => ({ jsonrpc: '2.0', id, error: { code, message } });

export const negotiateProtocolVersion = (requested: unknown): string =>
  typeof requested === 'string' && (SUPPORTED_PROTOCOL_VERSIONS as readonly string[]).includes(requested)
    ? requested
    : LATEST_PROTOCOL_VERSION;

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

// One JSON-RPC message → one response object, or null when nothing should be
// sent back (notifications, and responses the client sends us).
async function handleOne(message: unknown, spec: McpServerSpec): Promise<Record<string, unknown> | null> {
  if (!isPlainObject(message)) return rpcError(null, -32600, 'Invalid Request');
  const id = (message.id === undefined ? undefined : message.id) as JsonRpcId | undefined;
  if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    if (message.method === undefined && ('result' in message || 'error' in message)) return null;
    return rpcError(id ?? null, -32600, 'Invalid Request');
  }
  if (id === undefined) return null; // notification
  const params = isPlainObject(message.params) ? message.params : {};

  switch (message.method) {
    case 'initialize':
      return rpcResult(id, {
        protocolVersion: negotiateProtocolVersion(params.protocolVersion),
        capabilities: { tools: {} },
        serverInfo: { name: spec.name, version: spec.version },
        ...(spec.instructions ? { instructions: spec.instructions } : {}),
      });
    case 'ping':
      return rpcResult(id, {});
    case 'tools/list':
      return rpcResult(id, { tools: spec.tools });
    case 'tools/call': {
      const name = params.name;
      if (typeof name !== 'string' || !spec.tools.some((t) => t.name === name)) {
        return rpcError(id, -32602, `Unknown tool: ${String(name)}`);
      }
      const args = params.arguments === undefined ? {} : params.arguments;
      if (!isPlainObject(args)) return rpcError(id, -32602, 'arguments must be an object');
      try {
        return rpcResult(id, await spec.callTool(name, args));
      } catch (e) {
        const detail = e instanceof Error ? e.message : 'unknown error';
        return rpcResult(id, errorResult(`Tool failed: ${detail}`));
      }
    }
    default:
      return rpcError(id, -32601, `Method not found: ${message.method}`);
  }
}

export async function handleMcpMessage(payload: unknown, spec: McpServerSpec): Promise<McpHttpResult> {
  if (Array.isArray(payload)) {
    if (payload.length === 0) return { status: 400, body: rpcError(null, -32600, 'Invalid Request: empty batch') };
    const responses = (await Promise.all(payload.map((m) => handleOne(m, spec)))).filter((r) => r !== null);
    return responses.length ? { status: 200, body: responses } : { status: 202, body: null };
  }
  const response = await handleOne(payload, spec);
  return response ? { status: 200, body: response } : { status: 202, body: null };
}

export function parseJsonRpcBody(raw: string): { ok: true; value: unknown } | { ok: false; response: McpHttpResult } {
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch {
    return { ok: false, response: { status: 400, body: rpcError(null, -32700, 'Parse error') } };
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run supabase/functions/_shared/mcpProtocol.test.ts`
Expected: all green. Then `npm test` — the full suite still passes (the new file is picked up by vitest's default include; `ios/`, `extension/`, `.claude/` stay excluded).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/mcpProtocol.ts supabase/functions/_shared/mcpProtocol.test.ts
git commit -m "feat(mcp): dependency-free MCP JSON-RPC core with tests"
```

---

### Task 3: Extract the retrieval core into `_shared/search.ts`

**Files:**
- Create: `supabase/functions/_shared/search.ts`
- Test: `supabase/functions/_shared/search.test.ts`
- Modify: `supabase/functions/search-items/index.ts` (whole file)

**Interfaces:**
- Produces:
  - `ITEM_TYPES`, `type ItemType`, `SEARCH_DEFAULT_LIMIT = 20`, `SEARCH_MAX_LIMIT = 50`, `SNIPPET_CHARS = 280`
  - `interface SearchRequest { query: string; types: ItemType[]; tags: string[]; after: string | null; before: string | null; limit: number }`
  - `interface SearchResult { id; title; type; url; created_at; description; snippet; score }` (exact shape of today's `search-items` response rows)
  - `normalizeSearchRequest(body: unknown): SearchRequest`
  - `searchItems(req: SearchRequest, deps: { supabaseAdmin; userId: string; embed: (text: string) => Promise<number[]> }): Promise<SearchResult[]>`
  - `openAiEmbedder(apiKey: string): (text: string) => Promise<number[]>`

- [ ] **Step 1: Write the failing normalization tests**

```ts
// supabase/functions/_shared/search.test.ts
import { describe, expect, it } from 'vitest';
import { SEARCH_DEFAULT_LIMIT, SEARCH_MAX_LIMIT, normalizeSearchRequest } from './search';

describe('normalizeSearchRequest', () => {
  it('returns defaults for empty or non-object bodies', () => {
    const expected = { query: '', types: [], tags: [], after: null, before: null, limit: SEARCH_DEFAULT_LIMIT };
    expect(normalizeSearchRequest({})).toEqual(expected);
    expect(normalizeSearchRequest(null)).toEqual(expected);
    expect(normalizeSearchRequest([1, 2])).toEqual(expected);
    expect(normalizeSearchRequest('x')).toEqual(expected);
  });

  it('trims the query, keeps only known types, lowercases and trims tags', () => {
    const req = normalizeSearchRequest({ query: '  tacos ', types: ['link', 'bogus', 'audio'], tags: [' Food ', '', 7] });
    expect(req.query).toBe('tacos');
    expect(req.types).toEqual(['link', 'audio']);
    expect(req.tags).toEqual(['food']);
  });

  it('clamps and truncates limit', () => {
    expect(normalizeSearchRequest({ limit: 999 }).limit).toBe(SEARCH_MAX_LIMIT);
    expect(normalizeSearchRequest({ limit: 0 }).limit).toBe(SEARCH_DEFAULT_LIMIT);
    expect(normalizeSearchRequest({ limit: -4 }).limit).toBe(1);
    expect(normalizeSearchRequest({ limit: 3.9 }).limit).toBe(3);
    expect(normalizeSearchRequest({ limit: 'abc' }).limit).toBe(SEARCH_DEFAULT_LIMIT);
  });

  it('normalizes timestamps to ISO and drops invalid ones', () => {
    const req = normalizeSearchRequest({ after: '2026-08-01', before: 'not a date' });
    expect(req.after).toBe('2026-08-01T00:00:00.000Z');
    expect(req.before).toBeNull();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run supabase/functions/_shared/search.test.ts`
Expected: FAIL — cannot resolve `./search`.

- [ ] **Step 3: Write the shared module**

```ts
// supabase/functions/_shared/search.ts
//
// Canonical retrieval core (docs/PLATFORM_API.md → POST /search-items). Two
// callers: the search-items HTTP shell and the mcp function's search_stash
// tool. Keeping one implementation is what makes MCP "a thin wrapper over the
// retrieval stack that already exists".
//
//   • query mode  — hybrid semantic+keyword search via hybrid_search_content,
//                   optional structured filters, one result per item,
//                   relevance-ordered.
//   • filter mode — no/empty query: newest-first listing under the same
//                   filters (type, date range, tags).
//
// No imports on purpose: normalizeSearchRequest is unit-tested under vitest.

export const ITEM_TYPES = ['text', 'link', 'image', 'audio', 'video', 'document'] as const;
export type ItemType = typeof ITEM_TYPES[number];
export const SNIPPET_CHARS = 280;
export const SEARCH_DEFAULT_LIMIT = 20;
export const SEARCH_MAX_LIMIT = 50;

export interface SearchRequest {
  query: string;
  types: ItemType[];
  tags: string[];
  after: string | null;
  before: string | null;
  limit: number;
}

export interface SearchResult {
  id: string;
  title: string | null;
  type: string;
  url: string | null;
  created_at: string;
  description: string | null;
  snippet: string | null;
  score: number | null;
}

// Structural stand-in for a supabase-js service-role client so this module
// stays import-free. The shells pass a real client.
// deno-lint-ignore no-explicit-any
export type SupabaseAdminLike = any;

export interface SearchDeps {
  supabaseAdmin: SupabaseAdminLike;
  userId: string;
  embed: (text: string) => Promise<number[]>;
}

const parseTimestamp = (value: unknown): string | null => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const parsed = new Date(value);
  return isNaN(parsed.getTime()) ? null : parsed.toISOString();
};

export function normalizeSearchRequest(body: unknown): SearchRequest {
  const b = (typeof body === 'object' && body !== null && !Array.isArray(body) ? body : {}) as Record<string, unknown>;
  const query = typeof b.query === 'string' ? b.query.trim() : '';
  const types = Array.isArray(b.types)
    ? b.types.filter((t): t is ItemType => typeof t === 'string' && (ITEM_TYPES as readonly string[]).includes(t))
    : [];
  const tags = Array.isArray(b.tags)
    ? b.tags.filter((t): t is string => typeof t === 'string' && t.trim().length > 0).map((t) => t.trim().toLowerCase())
    : [];
  const rawLimit = Math.trunc(Number(b.limit) || SEARCH_DEFAULT_LIMIT);
  const limit = Math.min(Math.max(rawLimit, 1), SEARCH_MAX_LIMIT);
  return { query, types, tags, after: parseTimestamp(b.after), before: parseTimestamp(b.before), limit };
}

export const openAiEmbedder = (apiKey: string) => async (text: string): Promise<number[]> => {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: text }),
  });
  if (!response.ok) throw new Error(`Embedding request failed: ${response.status}`);
  const data = await response.json();
  return data.data[0].embedding;
};

export async function searchItems(req: SearchRequest, deps: SearchDeps): Promise<SearchResult[]> {
  const { supabaseAdmin, userId } = deps;
  const { query, types, tags, after, before, limit } = req;

  if (query) {
    const queryEmbedding = await deps.embed(query);
    const { data, error } = await supabaseAdmin.rpc('hybrid_search_content', {
      query_text: query,
      query_embedding: JSON.stringify(queryEmbedding),
      target_user_id: userId,
      match_count: Math.min(limit * 2, SEARCH_MAX_LIMIT),
      filter_types: types.length ? types : null,
      after_ts: after,
      before_ts: before,
      filter_tags: tags.length ? tags : null,
    });
    if (error) throw error;

    // Hits arrive relevance-ordered with up to 2 chunks per item; keep the
    // best-scored row per item and surface its chunk as the snippet.
    const seen = new Set<string>();
    const results: SearchResult[] = [];
    for (const hit of data ?? []) {
      if (seen.has(hit.item_id)) continue;
      seen.add(hit.item_id);
      results.push({
        id: hit.item_id,
        title: hit.item_title,
        type: hit.item_type,
        url: hit.item_url,
        created_at: hit.item_created_at,
        description: hit.item_description,
        snippet: hit.content_chunk ? hit.content_chunk.slice(0, SNIPPET_CHARS) : null,
        score: hit.score,
      });
      if (results.length >= limit) break;
    }
    return results;
  }

  // Filter-only mode: newest first under the same filters.
  let itemIds: string[] | null = null;
  if (tags.length) {
    const { data: tagRows, error: tagError } = await supabaseAdmin
      .from('tags').select('id').eq('user_id', userId).in('name', tags);
    if (tagError) throw tagError;
    const tagIds = (tagRows ?? []).map((t: { id: string }) => t.id);
    if (!tagIds.length) return [];
    const { data: itRows, error: itError } = await supabaseAdmin
      .from('item_tags').select('item_id').in('tag_id', tagIds);
    if (itError) throw itError;
    itemIds = [...new Set((itRows ?? []).map((r: { item_id: string }) => r.item_id))];
    if (!itemIds.length) return [];
  }

  let listQuery = supabaseAdmin
    .from('items')
    .select('id, title, type, url, created_at, description')
    .eq('user_id', userId)
    .neq('type', 'collection')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (types.length) listQuery = listQuery.in('type', types);
  if (after) listQuery = listQuery.gte('created_at', after);
  if (before) listQuery = listQuery.lte('created_at', before);
  if (itemIds) listQuery = listQuery.in('id', itemIds);

  const { data, error } = await listQuery;
  if (error) throw error;

  return (data ?? []).map((item: {
    id: string; title: string | null; type: string; url: string | null;
    created_at: string; description: string | null;
  }) => ({
    id: item.id,
    title: item.title,
    type: item.type,
    url: item.url,
    created_at: item.created_at,
    description: item.description,
    snippet: item.description ? item.description.slice(0, SNIPPET_CHARS) : null,
    score: null,
  }));
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run supabase/functions/_shared/search.test.ts`
Expected: PASS.

- [ ] **Step 5: Turn `search-items` into a shell**

Replace `supabase/functions/search-items/index.ts` with:

```ts
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
```

- [ ] **Step 6: Deploy and check parity against production**

Get a session token for the test account, then compare a query before/after (run the "before" call first, keep the output):

```bash
ANON='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE'
source ios/.env.test.local   # exports STASH_TEST_EMAIL / STASH_TEST_PASSWORD (check the file for exact names)
JWT=$(curl -s -X POST "https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$STASH_TEST_EMAIL\",\"password\":\"$STASH_TEST_PASSWORD\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
SEARCH() { curl -s -X POST https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/search-items \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON" -H "Content-Type: application/json" -d "$1"; echo; }
SEARCH '{"query":"design"}' > /tmp/search-before.json
SEARCH '{"types":["link"],"limit":3}' > /tmp/list-before.json
supabase functions deploy search-items --project-ref uqqsgmwkvslaomzxptnp
SEARCH '{"query":"design"}' > /tmp/search-after.json
SEARCH '{"types":["link"],"limit":3}' > /tmp/list-after.json
diff <(python3 -m json.tool /tmp/search-before.json) <(python3 -m json.tool /tmp/search-after.json) && echo SEARCH-PARITY-OK
diff <(python3 -m json.tool /tmp/list-before.json) <(python3 -m json.tool /tmp/list-after.json) && echo LIST-PARITY-OK
```
Expected: both parity lines print (result ids and snippets identical; `score` values may differ in the last decimals across embedding calls — if only scores differ, that is parity).

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/search.ts supabase/functions/_shared/search.test.ts supabase/functions/search-items/index.ts
git commit -m "refactor(search): extract retrieval core to _shared/search.ts for reuse by MCP"
```

---

### Task 4: Migration — grants, access log, and the "no copies" fence

**Files:**
- Create: `supabase/migrations/20260905120000_agent_grants_and_access_log.sql`

**Interfaces:**
- Produces tables `public.agent_grants`, `public.agent_access_log`, function `public.is_agent_token()`, restrictive policies named `agent tokens: no direct access` on every user-data table and `agent tokens: no storage access` on `storage.objects`.

- [ ] **Step 1: Write the migration**

```sql
-- MCP server (spec: docs/superpowers/specs/2026-09-05-mcp-server-design.md).
--
-- agent_grants: one row per (user, OAuth client) the user approved on
-- /oauth/consent. The mcp function refuses any token whose client has no
-- active row. Owner may read/insert/update (consent page, Settings revoke);
-- no delete — history stays. Service role bypasses RLS.
--
-- agent_access_log: one row per tool call, user-readable (Settings →
-- Connected agents → Activity) and the rate-limit ledger. Written by the mcp
-- function with the service role.
--
-- is_agent_token() + RESTRICTIVE policies: a Supabase OAuth access token is a
-- full user JWT. Without this fence an agent token could read every table
-- through PostgREST. Restrictive policies AND with the existing permissive
-- ones, so normal sessions are unaffected and agent tokens get zero rows —
-- "copies are unsupported by architecture".

CREATE TABLE IF NOT EXISTS public.agent_grants (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id    text NOT NULL,
  client_name  text NOT NULL,
  client_uri   text,
  scopes       text[] NOT NULL DEFAULT '{read}',
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  revoked_at   timestamptz,
  UNIQUE (user_id, client_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_grants_user ON public.agent_grants (user_id, created_at DESC);

ALTER TABLE public.agent_grants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own grants" ON public.agent_grants
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "owner creates own grants" ON public.agent_grants
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "owner updates own grants" ON public.agent_grants
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.agent_access_log (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL,
  grant_id     uuid NOT NULL REFERENCES public.agent_grants(id) ON DELETE CASCADE,
  client_id    text NOT NULL,
  tool         text NOT NULL,
  query        text,
  filters      jsonb,
  item_id      uuid,
  item_title   text,
  result_count int,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_access_log_user_time ON public.agent_access_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_access_log_grant_time ON public.agent_access_log (grant_id, created_at DESC);

ALTER TABLE public.agent_access_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own agent activity" ON public.agent_access_log
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_agent_token() RETURNS boolean
  LANGUAGE sql STABLE
  SET search_path = public
AS $$
  SELECT coalesce(auth.jwt() ->> 'client_id', '') <> ''
$$;

-- The fence. One restrictive policy per user-data table.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'items', 'embeddings', 'tags', 'item_tags', 'item_attachments',
    'conversations', 'messages', 'comments', 'card_feedback', 'chat_feedback',
    'sms_conversations', 'user_follows', 'user_phone_numbers',
    'user_preferences', 'user_profiles', 'agent_grants', 'agent_access_log'
  ] LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "agent tokens: no direct access" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "agent tokens: no direct access" ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (NOT public.is_agent_token()) WITH CHECK (NOT public.is_agent_token())', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS "agent tokens: no storage access" ON storage.objects;
CREATE POLICY "agent tokens: no storage access" ON storage.objects
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_agent_token()) WITH CHECK (NOT public.is_agent_token());
```

- [ ] **Step 2: Apply it through the Management API and record it**

```bash
TOKEN=$(security find-generic-password -s "Supabase CLI" -a "supabase" -w | sed 's/^go-keyring-base64://' | base64 -d)
q() { curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query \
  -d "{\"query\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")}"; echo; }
q "$(cat supabase/migrations/20260905120000_agent_grants_and_access_log.sql)"
q "insert into supabase_migrations.schema_migrations (version, name) values ('20260905120000', 'agent_grants_and_access_log') on conflict do nothing"
```
Expected: first call returns `[]` (no error object); second returns `[]`.

- [ ] **Step 3: Verify the schema and the fence shape**

```bash
q "select count(*) as fence_policies from pg_policies where policyname = 'agent tokens: no direct access'"
q "select policyname, permissive from pg_policies where tablename = 'items' order by 1"
q "select column_name from information_schema.columns where table_name = 'agent_grants' order by ordinal_position"
q "select public.is_agent_token() as is_agent"
```
Expected: `fence_policies` = 17; the items list includes `agent tokens: no direct access` with `permissive = RESTRICTIVE`; columns `id, user_id, client_id, client_name, client_uri, scopes, created_at, last_used_at, revoked_at`; `is_agent` = false (no JWT in that context).

Then prove a normal session still works (fence must be invisible to real users):

```bash
curl -s "https://uqqsgmwkvslaomzxptnp.supabase.co/rest/v1/items?select=id&limit=1" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT"
```
Expected: one row (JWT from Task 3 Step 6). The agent-token side of the fence is proven in Task 10.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260905120000_agent_grants_and_access_log.sql
git commit -m "feat(mcp): agent_grants + agent_access_log tables and the agent-token RLS fence"
```

---

### Task 5: Agent-token guard in every user-facing edge function

**Files:**
- Create: `supabase/functions/_shared/agentToken.ts`
- Test: `supabase/functions/_shared/agentToken.test.ts`
- Modify: `supabase/functions/_shared/auth.ts`
- Modify (guard insert): `add-note/index.ts:45`, `add-url/index.ts:223`, `add-file/index.ts:93`, `check-subscription/index.ts:47`, `create-checkout/index.ts:32`, `create-trial-subscription/index.ts:33`, `customer-portal/index.ts:37`, `chat-with-content/index.ts:34`, `summarize-content/index.ts:43`, `post-comment/index.ts:77`, `get-discover-feed/index.ts:25` (line numbers as of `b04e8ff`; match on the `getUser(` call).

**Interfaces:**
- Produces (`agentToken.ts`): `bearerToken(header: string | null | undefined): string | null`, `decodeJwtPayload(token: string): Record<string, unknown> | null`, `agentClientId(token: string): string | null`, `isAgentToken(token: string | null | undefined): boolean`.
- Produces (`auth.ts`): `assertNotAgentToken(tokenOrHeader: string | null | undefined): void` (throws `Error('Authentication failed: agent tokens are only accepted by the MCP endpoint')`), and `authenticateUser` now calls it.

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/_shared/agentToken.test.ts
import { describe, expect, it } from 'vitest';
import { agentClientId, bearerToken, decodeJwtPayload, isAgentToken } from './agentToken';

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fakeJwt = (payload: Record<string, unknown>) =>
  `${b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${b64url(JSON.stringify(payload))}.sig`;

describe('bearerToken', () => {
  it('strips the scheme case-insensitively and rejects other schemes', () => {
    expect(bearerToken('Bearer abc')).toBe('abc');
    expect(bearerToken('bearer   abc ')).toBe('abc');
    expect(bearerToken('Basic abc')).toBeNull();
    expect(bearerToken(null)).toBeNull();
    expect(bearerToken('Bearer ')).toBeNull();
  });
});

describe('decodeJwtPayload', () => {
  it('decodes base64url payloads and returns null for garbage', () => {
    expect(decodeJwtPayload(fakeJwt({ sub: 'u1', client_id: 'c1' }))).toEqual({ sub: 'u1', client_id: 'c1' });
    expect(decodeJwtPayload('not.a')).toBeNull();
    expect(decodeJwtPayload('a.!!!.c')).toBeNull();
  });
});

describe('agentClientId / isAgentToken', () => {
  it('detects the client_id claim that only OAuth-issued tokens carry', () => {
    expect(agentClientId(fakeJwt({ sub: 'u1', client_id: 'c1' }))).toBe('c1');
    expect(agentClientId(fakeJwt({ sub: 'u1' }))).toBeNull();
    expect(agentClientId(fakeJwt({ sub: 'u1', client_id: '' }))).toBeNull();
    expect(isAgentToken(fakeJwt({ client_id: 'c1' }))).toBe(true);
    expect(isAgentToken(fakeJwt({ sub: 'u1' }))).toBe(false);
    expect(isAgentToken(null)).toBe(false);
    expect(isAgentToken('garbage')).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run supabase/functions/_shared/agentToken.test.ts`
Expected: FAIL — cannot resolve `./agentToken`.

- [ ] **Step 3: Implement `agentToken.ts`**

```ts
// supabase/functions/_shared/agentToken.ts
//
// Supabase OAuth-server access tokens are ordinary user JWTs plus a
// `client_id` claim (docs: auth/oauth-server/oauth-flows → "Access token
// structure"). That claim is how every endpoint tells an agent token from a
// person's session. Decoding here is NOT verification — callers verify with
// auth.getUser first; this only reads claims off an already-trusted token.
// Import-free so it runs under Deno and vitest.

export function bearerToken(header: string | null | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  const token = match?.[1]?.trim();
  return token ? token : null;
}

export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
    const json = atob(padded);
    const payload = JSON.parse(json);
    return typeof payload === 'object' && payload !== null ? payload as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

export function agentClientId(token: string): string | null {
  const payload = decodeJwtPayload(token);
  const clientId = payload?.client_id;
  return typeof clientId === 'string' && clientId.length > 0 ? clientId : null;
}

export function isAgentToken(token: string | null | undefined): boolean {
  return !!token && agentClientId(token) !== null;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `npx vitest run supabase/functions/_shared/agentToken.test.ts`
Expected: PASS.

- [ ] **Step 5: Wire the guard into `_shared/auth.ts`**

Replace the file with:

```ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { isAgentToken } from './agentToken.ts';

export const AGENT_TOKEN_REJECTED = 'Authentication failed: agent tokens are only accepted by the MCP endpoint';

// Agent (OAuth-client) tokens may only enter through the mcp function, where
// grants, scopes, rate limits and the activity log apply. Every other
// endpoint refuses them — the second half of the "answers, never copies"
// fence (the first half is the RLS policies in the 20260905120000 migration).
// Accepts either a raw token or a full "Bearer …" header.
export function assertNotAgentToken(tokenOrHeader: string | null | undefined): void {
  const token = tokenOrHeader?.replace(/^Bearer\s+/i, '').trim();
  if (token && isAgentToken(token)) {
    throw new Error(AGENT_TOKEN_REJECTED);
  }
}

// Verify the caller's Supabase JWT, then hand back a service-role client.
// Tenancy is enforced by the edge function passing the verified user.id into
// user-scoped queries/RPCs — never by trusting ids from the request body.
export async function authenticateUser(authHeader: string | null) {
  if (!authHeader) {
    throw new Error('No authorization header');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Supabase configuration missing');
  }

  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
  const token = authHeader.replace('Bearer ', '');

  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);

  if (userError || !user) {
    console.error('Authentication error:', userError);
    throw new Error('Authentication failed');
  }

  assertNotAgentToken(token);

  return { user, supabaseAdmin };
}
```
(`search-items` and `chat-with-all-content` already map messages containing "Authentication" to 401, so agent tokens get a 401 with this message.)

- [ ] **Step 6: Insert the guard into the direct-`getUser` functions**

Add `import { isAgentToken } from '../_shared/agentToken.ts';` to each file's imports, then right after the existing successful-auth check:

`add-note/index.ts` and `add-url/index.ts` (after the `if (authError || !user) { … }` block that follows `getUser(token)`):
```ts
    if (isAgentToken(token)) {
      return new Response(
        JSON.stringify({ error: 'Agent tokens are only accepted by the MCP endpoint' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
```

`add-file/index.ts` (after `if (authError || !user) return json(401, …);`):
```ts
    if (isAgentToken(token)) return json(403, { error: 'Agent tokens are only accepted by the MCP endpoint' });
```

`check-subscription/index.ts` (after `const user = userData.user;`):
```ts
    if (isAgentToken(token)) return unauthorized("Agent tokens are only accepted by the MCP endpoint");
```

`create-checkout/index.ts`, `create-trial-subscription/index.ts`, `customer-portal/index.ts` (after the `const user = …` line):
```ts
    if (isAgentToken(token)) throw new Error("Agent tokens are only accepted by the MCP endpoint");
```

`chat-with-content/index.ts` (after `const { data: { user } } = await authedClient.auth.getUser();`) and `summarize-content/index.ts` (same spot) — the token is the header there:
```ts
      if (isAgentToken(authHeader)) {
        return new Response(JSON.stringify({ error: 'Agent tokens are only accepted by the MCP endpoint' }), {
          status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
```
In `summarize-content` use its own helper instead (signature `json(body, status = 200)`, defined at the top of the file), matching the 401 line directly above:
```ts
    if (isAgentToken(authHeader)) {
      return json({ success: false, reason: 'Agent tokens are only accepted by the MCP endpoint' }, 403);
    }
```
(`chat-with-content` and `post-comment` both define `corsHeaders` at the top of the file, so the snippet above works as written.)

`post-comment/index.ts` (after the `if (authError || !user) { … }` block):
```ts
      if (isAgentToken(authHeader)) {
        return new Response(JSON.stringify({ error: 'Agent tokens are only accepted by the MCP endpoint' }), {
          status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
```

`get-discover-feed/index.ts` (optional auth — treat an agent token as anonymous):
```ts
    if (authHeader && !isAgentToken(authHeader)) {
      const { data: { user } } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''));
      currentUserId = user?.id ?? null;
    }
```
(replaces the existing `if (authHeader) { … }` block.)

- [ ] **Step 7: Deploy every touched function and confirm normal sessions still work**

```bash
for f in search-items chat-with-all-content add-note add-url add-file check-subscription create-checkout \
         create-trial-subscription customer-portal chat-with-content summarize-content post-comment get-discover-feed; do
  supabase functions deploy $f --project-ref uqqsgmwkvslaomzxptnp || { echo "DEPLOY FAILED: $f"; break; }
done
supabase functions list --project-ref uqqsgmwkvslaomzxptnp
# Smoke with a real session token (JWT/ANON from Task 3 Step 6):
curl -s -X POST https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/check-subscription \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON" | head -c 300; echo
curl -s -X POST https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/search-items \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{"limit":1}'; echo
```
Expected: check-subscription returns the subscription JSON (not 401/403); search-items returns one result. The agent-token rejection itself is proven end-to-end in Task 10 Step 5.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/_shared/agentToken.ts supabase/functions/_shared/agentToken.test.ts supabase/functions/_shared/auth.ts \
  supabase/functions/add-note/index.ts supabase/functions/add-url/index.ts supabase/functions/add-file/index.ts \
  supabase/functions/check-subscription/index.ts supabase/functions/create-checkout/index.ts \
  supabase/functions/create-trial-subscription/index.ts supabase/functions/customer-portal/index.ts \
  supabase/functions/chat-with-content/index.ts supabase/functions/summarize-content/index.ts \
  supabase/functions/post-comment/index.ts supabase/functions/get-discover-feed/index.ts
git commit -m "feat(mcp): reject agent (OAuth-client) tokens on every non-MCP endpoint"
```

---

### Task 6: The `mcp` edge function

**Files:**
- Create: `supabase/functions/_shared/agentAuth.ts`
- Modify: `supabase/functions/mcp/index.ts` (replace the Task 1 stub entirely)

**Interfaces:**
- Consumes: `handleMcpMessage`, `parseJsonRpcBody`, `textResult`, `errorResult`, `McpServerSpec`, `McpToolDefinition` (Task 2); `normalizeSearchRequest`, `searchItems`, `openAiEmbedder`, `ITEM_TYPES` (Task 3); `bearerToken`, `agentClientId` (Task 5); tables from Task 4.
- Produces (`agentAuth.ts`): `authenticateAgent(authHeader: string | null): Promise<AgentAuthResult>` where
  `type AgentAuthResult = { ok: true; user: { id: string; email?: string }; grant: AgentGrant; supabaseAdmin } | { ok: false; status: 401 | 403; error: string; description: string }` and
  `interface AgentGrant { id: string; user_id: string; client_id: string; client_name: string; scopes: string[]; revoked_at: string | null }`.

- [ ] **Step 1: Write `agentAuth.ts`**

```ts
// supabase/functions/_shared/agentAuth.ts
//
// Authentication for the mcp function only. Order matters:
//   1. bearer token present
//   2. Supabase verifies it (signature, expiry, session still alive — a grant
//      revoked through Supabase kills the session, so revoked tokens die here)
//   3. token carries client_id (issued through the OAuth server, not a
//      person's session — every agent request must be attributable)
//   4. our agent_grants row for (user, client) exists and is not revoked
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { agentClientId, bearerToken } from './agentToken.ts';

export interface AgentGrant {
  id: string;
  user_id: string;
  client_id: string;
  client_name: string;
  scopes: string[];
  revoked_at: string | null;
}

export type AgentAuthResult =
  | { ok: true; user: { id: string; email?: string }; grant: AgentGrant; supabaseAdmin: ReturnType<typeof createClient> }
  | { ok: false; status: 401 | 403; error: string; description: string };

export async function authenticateAgent(authHeader: string | null): Promise<AgentAuthResult> {
  const token = bearerToken(authHeader);
  if (!token) {
    return { ok: false, status: 401, error: 'missing_token', description: 'Missing bearer token' };
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) throw new Error('Supabase configuration missing');
  const supabaseAdmin = createClient(supabaseUrl, serviceKey);

  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) {
    return { ok: false, status: 401, error: 'invalid_token', description: 'Token is invalid, expired, or revoked' };
  }

  const clientId = agentClientId(token);
  if (!clientId) {
    return {
      ok: false, status: 401, error: 'invalid_token',
      description: 'Stash MCP accepts only tokens issued through Connect an agent (OAuth), not session tokens',
    };
  }

  const { data: grant, error: grantError } = await supabaseAdmin
    .from('agent_grants')
    .select('id, user_id, client_id, client_name, scopes, revoked_at')
    .eq('user_id', user.id)
    .eq('client_id', clientId)
    .maybeSingle();
  if (grantError) {
    console.error('agent_grants lookup failed:', grantError);
    throw new Error('Grant lookup failed');
  }
  if (!grant || grant.revoked_at) {
    return {
      ok: false, status: 403, error: 'insufficient_scope',
      description: "This agent's access to your stash was revoked or never granted. Reconnect it from Settings → Connected agents at gostash.it.",
    };
  }

  return { ok: true, user: { id: user.id, email: user.email ?? undefined }, grant: grant as AgentGrant, supabaseAdmin };
}
```

- [ ] **Step 2: Write the function**

Replace `supabase/functions/mcp/index.ts` with (set `MCP_RESOURCE_URL` per Task 1's decision):

```ts
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
  errorResult, handleMcpMessage, parseJsonRpcBody, textResult,
  type McpServerSpec, type McpToolDefinition, type McpToolResult,
} from '../_shared/mcpProtocol.ts';
import {
  ITEM_TYPES, SEARCH_MAX_LIMIT, normalizeSearchRequest, openAiEmbedder, searchItems,
} from '../_shared/search.ts';

// Task 1 decision. Must equal the URL users paste into their agent, exactly.
const MCP_RESOURCE_URL = 'https://www.gostash.it/mcp';
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
// /.well-known/oauth-protected-resource/mcp on the site (static copy).
const protectedResourceMetadata = () => ({
  resource: MCP_RESOURCE_URL,
  authorization_servers: [AUTHORIZATION_SERVER],
  scopes_supported: ['email'],
  bearer_methods_supported: ['header'],
  resource_name: 'Stash',
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

const runGetItem = async (admin: Admin, userId: string, grant: AgentGrant, args: Record<string, unknown>): Promise<McpToolResult> => {
  const id = typeof args.id === 'string' ? args.id.trim() : '';
  if (!/^[0-9a-f-]{36}$/i.test(id)) return errorResult('id must be an item id from search_stash.');

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
  const body = item.page_body ? String(item.page_body).slice(0, ITEM_BODY_CHARS) : null;

  const parts: string[] = [`${item.title || 'Untitled'} (${item.type}${flavor ? `/${flavor}` : ''} · saved ${String(item.created_at).slice(0, 10)})`];
  if (item.url) parts.push(`URL: ${item.url}`);
  if (location) parts.push(`Saved at: ${location}`);
  if (item.description) parts.push(`Description: ${item.description}`);
  if (notes) parts.push(`User's notes: ${notes}`);
  if (item.supplemental_note) parts.push(`Sticky note: ${item.supplemental_note}`);
  if (item.summary) parts.push(`Summary: ${item.summary}`);
  if (body) parts.push(`Captured text:\n${body}${item.page_body.length > ITEM_BODY_CHARS ? '\n[truncated]' : ''}`);

  return textResult(parts.join('\n'), {
    id: item.id, title: item.title, type: item.type, url: item.url, created_at: item.created_at,
    description: item.description, notes, sticky_note: item.supplemental_note ?? null, summary: item.summary,
    captured_text: body, attributes: { link: flavor ? { flavor } : null, location: location ? { label: location } : null },
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
    return errorResult(`Unknown tool: ${name}`);
  },
});

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });

  const path = new URL(req.url).pathname;
  if (req.method === 'GET' && path.endsWith('/.well-known/oauth-protected-resource')) {
    return new Response(JSON.stringify(protectedResourceMetadata()), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' },
    });
  }
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
```

- [ ] **Step 3: Deploy and verify the unauthenticated surface**

```bash
supabase functions deploy mcp --project-ref uqqsgmwkvslaomzxptnp
BASE=https://www.gostash.it/mcp   # or the raw function URL per Task 1
curl -s -i -X POST $BASE -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | sed -n '1,12p'
curl -s $BASE/.well-known/oauth-protected-resource; echo
curl -s -i $BASE | sed -n '1,3p'
curl -s -i -X POST $BASE -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"ping"}' | sed -n '1,8p'
```
Expected, in order: `401` with `WWW-Authenticate: Bearer resource_metadata="https://www.gostash.it/mcp/.well-known/oauth-protected-resource", scope="email", …`; the metadata JSON with `"resource":"https://www.gostash.it/mcp"`; `405`; and — with a *session* JWT — `401` whose description says only OAuth-issued tokens are accepted (this is the "session tokens refused" rule).

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/_shared/agentAuth.ts supabase/functions/mcp/index.ts
git commit -m "feat(mcp): MCP edge function — OAuth-authenticated search_stash + get_item with audit log and rate limits"
```

---

### Task 7: Consent page (`/oauth/consent`)

**Files:**
- Modify: `src/integrations/supabase/types.ts` (add two table types before `card_feedback`)
- Create: `src/utils/oauthConsent.ts`
- Test: `src/utils/oauthConsent.test.ts`
- Create: `src/pages/OAuthConsent.tsx`
- Modify: `src/App.tsx` (import + route)

**Interfaces:**
- Produces (`oauthConsent.ts`):
  - `interface OAuthClient { id: string; name: string; uri?: string; logo_uri?: string }`
  - `interface AuthorizationDetails { authorization_id: string; redirect_uri: string; client: OAuthClient; user: { id: string; email: string }; scope: string }`
  - `interface OAuthRedirect { redirect_url: string }`
  - `isRedirect(r): r is OAuthRedirect`, `consentReturnTo(authorizationId): string`, `hostOf(url?): string | null`, `isLoopbackHost(host): boolean`
  - `fetchAuthorizationDetails(id, accessToken): Promise<AuthorizationDetails | OAuthRedirect>`
  - `decideAuthorization(id, accessToken, 'approve' | 'deny'): Promise<OAuthRedirect>`
  - `listOAuthGrants(accessToken): Promise<Array<{ client: OAuthClient; scopes: string[]; granted_at: string }>>`
  - `revokeOAuthGrant(clientId, accessToken): Promise<void>`
- Produces (types): `Database['public']['Tables']['agent_grants' | 'agent_access_log']`.

- [ ] **Step 1: Add the table types**

In `src/integrations/supabase/types.ts`, insert directly after `    Tables: {` (before `card_feedback`):

```ts
      agent_access_log: {
        Row: {
          client_id: string
          created_at: string
          filters: Json | null
          grant_id: string
          id: string
          item_id: string | null
          item_title: string | null
          query: string | null
          result_count: number | null
          tool: string
          user_id: string
        }
        Insert: {
          client_id: string
          created_at?: string
          filters?: Json | null
          grant_id: string
          id?: string
          item_id?: string | null
          item_title?: string | null
          query?: string | null
          result_count?: number | null
          tool: string
          user_id: string
        }
        Update: {
          client_id?: string
          created_at?: string
          filters?: Json | null
          grant_id?: string
          id?: string
          item_id?: string | null
          item_title?: string | null
          query?: string | null
          result_count?: number | null
          tool?: string
          user_id?: string
        }
        Relationships: []
      }
      agent_grants: {
        Row: {
          client_id: string
          client_name: string
          client_uri: string | null
          created_at: string
          id: string
          last_used_at: string | null
          revoked_at: string | null
          scopes: string[]
          user_id: string
        }
        Insert: {
          client_id: string
          client_name: string
          client_uri?: string | null
          created_at?: string
          id?: string
          last_used_at?: string | null
          revoked_at?: string | null
          scopes?: string[]
          user_id: string
        }
        Update: {
          client_id?: string
          client_name?: string
          client_uri?: string | null
          created_at?: string
          id?: string
          last_used_at?: string | null
          revoked_at?: string | null
          scopes?: string[]
          user_id?: string
        }
        Relationships: []
      }
```

- [ ] **Step 2: Write the failing tests**

```ts
// src/utils/oauthConsent.test.ts
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  consentReturnTo, decideAuthorization, hostOf, isLoopbackHost, isRedirect, revokeOAuthGrant,
} from './oauthConsent';

describe('isRedirect', () => {
  it('detects the already-consented / decided shape', () => {
    expect(isRedirect({ redirect_url: 'https://claude.ai/api/mcp/auth_callback?code=1' })).toBe(true);
    expect(isRedirect({ authorization_id: 'a', redirect_uri: 'x', client: { id: 'c', name: 'Claude' }, user: { id: 'u', email: 'e' }, scope: 'email' })).toBe(false);
  });
});

describe('consentReturnTo', () => {
  it('round-trips the authorization id through the sign-in page', () => {
    const url = consentReturnTo('abc 123');
    expect(url.startsWith('/auth?returnTo=')).toBe(true);
    const returnTo = new URLSearchParams(url.slice('/auth?'.length)).get('returnTo');
    expect(returnTo).toBe('/oauth/consent?authorization_id=abc%20123');
  });
});

describe('hostOf / isLoopbackHost', () => {
  it('extracts hosts and flags loopback redirects', () => {
    expect(hostOf('https://claude.ai/api/mcp/auth_callback')).toBe('claude.ai');
    expect(hostOf('http://localhost:3118/callback')).toBe('localhost');
    expect(hostOf('not a url')).toBeNull();
    expect(hostOf(undefined)).toBeNull();
    expect(isLoopbackHost('localhost')).toBe(true);
    expect(isLoopbackHost('127.0.0.1')).toBe(true);
    expect(isLoopbackHost('[::1]')).toBe(true);
    expect(isLoopbackHost('claude.ai')).toBe(false);
    expect(isLoopbackHost(null)).toBe(false);
  });
});

describe('REST helpers', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('posts the consent decision with the session token and returns the redirect', async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ redirect_url: 'https://x/cb?code=1' }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const out = await decideAuthorization('auth-1', 'tok', 'approve');
    expect(out).toEqual({ redirect_url: 'https://x/cb?code=1' });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/auth\/v1\/oauth\/authorizations\/auth-1\/consent$/);
    expect(init.method).toBe('POST');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer tok');
    expect(init.body).toBe(JSON.stringify({ action: 'approve' }));
  });

  it('surfaces GoTrue error descriptions', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: 'invalid_request', error_description: 'expired' }), { status: 400 })));
    await expect(decideAuthorization('auth-1', 'tok', 'deny')).rejects.toThrow('expired');
  });

  it('revokes by client id with DELETE', async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);
    await revokeOAuthGrant('client-9', 'tok');
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/auth\/v1\/user\/oauth\/grants\?client_id=client-9$/);
    expect(init.method).toBe('DELETE');
  });
});
```

- [ ] **Step 3: Run to verify failure**

Run: `npx vitest run src/utils/oauthConsent.test.ts`
Expected: FAIL — cannot resolve `./oauthConsent`.

- [ ] **Step 4: Implement `oauthConsent.ts`**

```ts
// src/utils/oauthConsent.ts
//
// Supabase Auth OAuth-server calls the consent page and Settings need. Our
// supabase-js (2.50) predates `auth.oauth.*`, so these hit GoTrue's REST
// endpoints directly with the session JWT (same calls the newer client makes:
// GET  /auth/v1/oauth/authorizations/{id}
// POST /auth/v1/oauth/authorizations/{id}/consent  { action }
// GET  /auth/v1/user/oauth/grants
// DELETE /auth/v1/user/oauth/grants?client_id=…).
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';

export interface OAuthClient {
  id: string;
  name: string;
  uri?: string;
  logo_uri?: string;
}

export interface AuthorizationDetails {
  authorization_id: string;
  redirect_uri: string;
  client: OAuthClient;
  user: { id: string; email: string };
  scope: string;
}

export interface OAuthRedirect {
  redirect_url: string;
}

export interface OAuthGrant {
  client: OAuthClient;
  scopes: string[];
  granted_at: string;
}

export const isRedirect = (r: AuthorizationDetails | OAuthRedirect): r is OAuthRedirect =>
  typeof (r as OAuthRedirect).redirect_url === 'string';

export const consentReturnTo = (authorizationId: string): string =>
  `/auth?returnTo=${encodeURIComponent(`/oauth/consent?authorization_id=${encodeURIComponent(authorizationId)}`)}`;

export const hostOf = (url: string | undefined): string | null => {
  if (!url) return null;
  try {
    return new URL(url).host.replace(/:\d+$/, '');
  } catch {
    return null;
  }
};

export const isLoopbackHost = (host: string | null): boolean =>
  host === 'localhost' || host === '127.0.0.1' || host === '[::1]';

const errorMessage = async (res: Response): Promise<string> => {
  try {
    const body = await res.json();
    return body.error_description || body.msg || body.message || body.error || `Request failed (${res.status})`;
  } catch {
    return `Request failed (${res.status})`;
  }
};

const authRequest = async (path: string, accessToken: string, init: RequestInit = {}): Promise<Response> => {
  const res = await fetch(`${SUPABASE_URL}/auth/v1${path}`, {
    ...init,
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(init.headers as Record<string, string> | undefined),
    },
  });
  if (!res.ok) throw new Error(await errorMessage(res));
  return res;
};

export async function fetchAuthorizationDetails(authorizationId: string, accessToken: string): Promise<AuthorizationDetails | OAuthRedirect> {
  const res = await authRequest(`/oauth/authorizations/${encodeURIComponent(authorizationId)}`, accessToken);
  return res.json();
}

export async function decideAuthorization(authorizationId: string, accessToken: string, action: 'approve' | 'deny'): Promise<OAuthRedirect> {
  const res = await authRequest(`/oauth/authorizations/${encodeURIComponent(authorizationId)}/consent`, accessToken, {
    method: 'POST',
    body: JSON.stringify({ action }),
  });
  return res.json();
}

export async function listOAuthGrants(accessToken: string): Promise<OAuthGrant[]> {
  const res = await authRequest('/user/oauth/grants', accessToken);
  return res.json();
}

export async function revokeOAuthGrant(clientId: string, accessToken: string): Promise<void> {
  await authRequest(`/user/oauth/grants?client_id=${encodeURIComponent(clientId)}`, accessToken, { method: 'DELETE' });
}
```

- [ ] **Step 5: Run to verify pass**

Run: `npx vitest run src/utils/oauthConsent.test.ts`
Expected: PASS.

- [ ] **Step 6: Build the page**

```tsx
// src/pages/OAuthConsent.tsx
//
// Supabase Auth redirects here (site URL + authorization path) with
// ?authorization_id=… when an OAuth client (an MCP agent) asks for access.
// Signed-out visitors bounce through /auth and come back. Approving writes
// our agent_grants row FIRST (the mcp function refuses tokens without one),
// then tells Supabase to issue the code. Spec: docs/superpowers/specs/
// 2026-09-05-mcp-server-design.md → "Web surfaces".
import { useEffect, useState } from 'react';
import { Navigate, useSearchParams } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import StashWordmark from '@/components/StashWordmark';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import {
  consentReturnTo, decideAuthorization, fetchAuthorizationDetails, hostOf, isLoopbackHost, isRedirect,
  type AuthorizationDetails, type OAuthClient,
} from '@/utils/oauthConsent';

const card =
  'w-full max-w-[440px] rounded-[20px] border border-black/[0.07] bg-white px-7 py-8 shadow-[0_2px_6px_rgba(20,22,30,0.05),0_24px_70px_rgba(30,33,44,0.16)] sm:px-8';
const primaryCta =
  'h-11 w-full rounded-xl bg-[#6d5bd0] text-[15px] font-medium text-white hover:bg-[#5f4ec2] focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';
const secondaryCta =
  'h-11 w-full rounded-xl border border-black/[0.07] bg-white text-[15px] font-medium text-[#22262f] hover:bg-[rgba(20,22,30,0.04)] focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0';

const CAN = ['Search your stash', 'Read saved items in full'];
const CANNOT = ['Add, edit or delete anything', 'Export your stash', 'See your account or billing'];

const Shell = ({ children }: { children: React.ReactNode }) => (
  <div className="relative min-h-screen overflow-hidden bg-[#f7f7f9] font-montreal">
    <div className="relative z-10 flex min-h-screen items-center justify-center p-4">
      <div className={card}>
        <div className="flex justify-center">
          <StashWordmark className="h-6 text-[#22262f]" />
        </div>
        {children}
      </div>
    </div>
  </div>
);

const OAuthConsent = () => {
  const [searchParams] = useSearchParams();
  const authorizationId = searchParams.get('authorization_id');
  const { user, session, loading } = useAuth();
  const [details, setDetails] = useState<AuthorizationDetails | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<'approve' | 'deny' | null>(null);

  const isRealUser = !!user && !(user as { is_anonymous?: boolean }).is_anonymous;
  const accessToken = session?.access_token;

  const ensureGrant = async (client: OAuthClient) => {
    if (!user) throw new Error('Not signed in');
    const { error: upsertError } = await supabase.from('agent_grants').upsert(
      {
        user_id: user.id,
        client_id: client.id,
        client_name: client.name || 'Unnamed agent',
        client_uri: client.uri ?? null,
        scopes: ['read'],
        revoked_at: null,
      },
      { onConflict: 'user_id,client_id' },
    );
    if (upsertError) throw new Error('Could not record this connection. Try again.');
  };

  useEffect(() => {
    if (!authorizationId || !isRealUser || !accessToken) return;
    let cancelled = false;
    (async () => {
      try {
        const res = await fetchAuthorizationDetails(authorizationId, accessToken);
        if (cancelled) return;
        if (isRedirect(res)) {
          // Supabase already holds consent for this client. That response has
          // no client info, so we can't touch agent_grants here — and needn't:
          // revocation deletes the Supabase grant before marking ours, so an
          // auto-approve implies our row is still active.
          window.location.assign(res.redirect_url);
          return;
        }
        setDetails(res);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'This connection request is no longer valid.');
      }
    })();
    return () => { cancelled = true; };
  }, [authorizationId, isRealUser, accessToken]);

  const decide = async (action: 'approve' | 'deny') => {
    if (!details || !accessToken) return;
    setBusy(action);
    setError(null);
    try {
      if (action === 'approve') await ensureGrant(details.client);
      const { redirect_url } = await decideAuthorization(details.authorization_id, accessToken, action);
      window.location.assign(redirect_url);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Start again from your agent.');
      setBusy(null);
    }
  };

  if (!authorizationId) {
    return (
      <Shell>
        <p className="mt-6 text-center text-[15px] text-[#22262f]">This link is missing its authorization request.</p>
        <p className="mt-2 text-center text-sm text-[#646b76]">Start again from your agent and it will bring you back here.</p>
      </Shell>
    );
  }

  if (loading) {
    return (
      <Shell>
        <div className="mt-8 flex justify-center"><Loader2 className="h-5 w-5 animate-spin text-[#6d5bd0]" /></div>
      </Shell>
    );
  }

  if (!isRealUser) return <Navigate to={consentReturnTo(authorizationId)} replace />;

  if (error && !details) {
    return (
      <Shell>
        <p className="mt-6 text-center text-[15px] text-[#22262f]">{error}</p>
        <p className="mt-2 text-center text-sm text-[#646b76]">Start again from your agent.</p>
      </Shell>
    );
  }

  if (!details) {
    return (
      <Shell>
        <div className="mt-8 flex justify-center"><Loader2 className="h-5 w-5 animate-spin text-[#6d5bd0]" /></div>
      </Shell>
    );
  }

  const clientHost = hostOf(details.client.uri);
  const returnHost = hostOf(details.redirect_uri);
  const loopback = isLoopbackHost(returnHost);

  return (
    <Shell>
      <h1 className="mt-5 text-center text-[20px] leading-tight text-[#22262f]">
        <span className="font-medium">{details.client.name || 'An agent'}</span> wants to connect to your Stash
      </h1>
      {clientHost && <p className="mt-1 text-center text-sm text-[#646b76]">{clientHost}</p>}

      <div className="mt-6 space-y-4 text-[15px]">
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[#646b76]">It can</p>
          <ul className="mt-1.5 space-y-1 text-[#22262f]">
            {CAN.map((line) => <li key={line}>· {line}</li>)}
          </ul>
        </div>
        <div>
          <p className="text-xs font-medium uppercase tracking-wide text-[#646b76]">It can't</p>
          <ul className="mt-1.5 space-y-1 text-[#22262f]">
            {CANNOT.map((line) => <li key={line}>· {line}</li>)}
          </ul>
        </div>
      </div>

      <p className="mt-6 text-sm text-[#646b76]">
        Signed in as <span className="text-[#22262f]">{user?.email}</span>.
        {returnHost && <> Returns to <span className="text-[#22262f]">{returnHost}</span>.</>}
      </p>
      {loopback && (
        <p className="mt-2 rounded-xl bg-[#fff7e6] px-3 py-2 text-sm text-[#7a4b00]">
          This connection returns to a program running on your computer. Continue only if you started it from an app you trust.
        </p>
      )}
      {error && <p className="mt-3 text-sm text-[#c93a3a]">{error}</p>}

      <div className="mt-6 space-y-2.5">
        <Button className={primaryCta} onClick={() => decide('approve')} disabled={busy !== null}>
          {busy === 'approve' ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Allow access'}
        </Button>
        <Button variant="outline" className={secondaryCta} onClick={() => decide('deny')} disabled={busy !== null}>
          {busy === 'deny' ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Deny'}
        </Button>
      </div>
      <p className="mt-4 text-center text-xs text-[#959ba6]">You can revoke this any time in Settings → Connected agents.</p>
    </Shell>
  );
};

export default OAuthConsent;
```

- [ ] **Step 7: Route it**

In `src/App.tsx`: add `import OAuthConsent from '@/pages/OAuthConsent';` after the `Settings` import, and add `<Route path="/oauth/consent" element={<OAuthConsent />} />` directly after the `/settings` route.

- [ ] **Step 8: Typecheck and run the suite**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: no type errors; all tests pass.

- [ ] **Step 9: Commit**

```bash
git add src/integrations/supabase/types.ts src/utils/oauthConsent.ts src/utils/oauthConsent.test.ts src/pages/OAuthConsent.tsx src/App.tsx
git commit -m "feat(mcp): /oauth/consent page — approve or deny an agent, record the grant"
```

---

### Task 8: Settings → Connected agents, static metadata, deploy web

**Files:**
- Create: `src/utils/agentActivity.ts`
- Test: `src/utils/agentActivity.test.ts`
- Create: `src/hooks/useConnectedAgents.ts`
- Create: `src/components/settings/ConnectedAgentsSettings.tsx`
- Modify: `src/pages/Settings.tsx`
- Create: `public/.well-known/oauth-protected-resource/mcp`
- Modify: `vercel.json`

**Interfaces:**
- Consumes: `listOAuthGrants`, `revokeOAuthGrant` (Task 7); `agent_grants`, `agent_access_log` types (Task 7).
- Produces: `MCP_SERVER_URL` const (in `agentActivity.ts`, single source for the web copy), `describeAgentActivity(row: AgentAccessRow, clientName: string): string`, `useConnectedAgents()`.

- [ ] **Step 1: Write the failing tests**

```ts
// src/utils/agentActivity.test.ts
import { describe, expect, it } from 'vitest';
import { describeAgentActivity, type AgentAccessRow } from './agentActivity';

const row = (over: Partial<AgentAccessRow>): AgentAccessRow => ({
  id: 'r1', client_id: 'c1', tool: 'search_stash', query: null, filters: null,
  item_id: null, item_title: null, result_count: null, created_at: '2026-09-05T14:14:00Z', ...over,
});

describe('describeAgentActivity', () => {
  it('describes searches with the query and result count', () => {
    expect(describeAgentActivity(row({ query: 'restaurants in Saratoga', result_count: 3 }), 'Claude'))
      .toBe('Claude searched for “restaurants in Saratoga” · 3 results');
    expect(describeAgentActivity(row({ query: 'x', result_count: 1 }), 'Claude')).toBe('Claude searched for “x” · 1 result');
    expect(describeAgentActivity(row({ query: 'x', result_count: 0 }), 'Claude')).toBe('Claude searched for “x” · no results');
  });

  it('describes listings, with the type filter when present', () => {
    expect(describeAgentActivity(row({ result_count: 20 }), 'Claude')).toBe('Claude listed recent saves · 20 results');
    expect(describeAgentActivity(row({ filters: { types: ['link'] }, result_count: 5 }), 'Cursor')).toBe('Cursor listed recent links · 5 results');
    expect(describeAgentActivity(row({ filters: { types: ['image', 'audio'] }, result_count: 2 }), 'Cursor')).toBe('Cursor listed recent photos and audio · 2 results');
  });

  it('describes reads by title and misses honestly', () => {
    expect(describeAgentActivity(row({ tool: 'get_item', item_title: 'Beyond the Basics', result_count: 1 }), 'Claude')).toBe('Claude read “Beyond the Basics”');
    expect(describeAgentActivity(row({ tool: 'get_item', item_title: null, result_count: 0 }), 'Claude')).toBe('Claude tried to read an item that wasn’t found');
  });

  it('falls back for unknown tools', () => {
    expect(describeAgentActivity(row({ tool: 'future_tool' }), 'Claude')).toBe('Claude used future_tool');
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run src/utils/agentActivity.test.ts`
Expected: FAIL — cannot resolve `./agentActivity`.

- [ ] **Step 3: Implement `agentActivity.ts`**

```ts
// src/utils/agentActivity.ts
//
// Renders agent_access_log rows as the sentences Settings → Connected agents
// shows ("Claude searched your stash for restaurants, Tue 2:14pm" — the
// audit-log requirement in the 2026-08-28 context-layer spec, Workstream D).

export const MCP_SERVER_URL = 'https://www.gostash.it/mcp';

export interface AgentAccessRow {
  id: string;
  client_id: string;
  tool: string;
  query: string | null;
  filters: Record<string, unknown> | null;
  item_id: string | null;
  item_title: string | null;
  result_count: number | null;
  created_at: string;
}

const TYPE_LABELS: Record<string, string> = {
  text: 'notes', link: 'links', image: 'photos', audio: 'audio', video: 'videos', document: 'documents',
};

const joinNatural = (parts: string[]): string =>
  parts.length <= 1 ? parts.join('') : `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;

const countPhrase = (n: number | null): string => {
  if (n === null) return '';
  if (n === 0) return ' · no results';
  return ` · ${n} result${n === 1 ? '' : 's'}`;
};

export function describeAgentActivity(row: AgentAccessRow, clientName: string): string {
  const who = clientName || 'An agent';
  if (row.tool === 'search_stash') {
    if (row.query) return `${who} searched for “${row.query}”${countPhrase(row.result_count)}`;
    const types = Array.isArray(row.filters?.types) ? (row.filters!.types as string[]).map((t) => TYPE_LABELS[t] ?? t) : [];
    const what = types.length ? `recent ${joinNatural(types)}` : 'recent saves';
    return `${who} listed ${what}${countPhrase(row.result_count)}`;
  }
  if (row.tool === 'get_item') {
    if (row.item_title) return `${who} read “${row.item_title}”`;
    return row.result_count === 0 ? `${who} tried to read an item that wasn’t found` : `${who} read an item`;
  }
  return `${who} used ${row.tool}`;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `npx vitest run src/utils/agentActivity.test.ts`
Expected: PASS.

- [ ] **Step 5: Write the hook**

```ts
// src/hooks/useConnectedAgents.ts
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { revokeOAuthGrant } from '@/utils/oauthConsent';
import type { AgentAccessRow } from '@/utils/agentActivity';

export interface ConnectedAgent {
  id: string;
  client_id: string;
  client_name: string;
  client_uri: string | null;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

export const useConnectedAgents = () => {
  const { user, session } = useAuth();
  const { toast } = useToast();
  const [grants, setGrants] = useState<ConnectedAgent[]>([]);
  const [activity, setActivity] = useState<AgentAccessRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [revoking, setRevoking] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const [grantsRes, activityRes] = await Promise.all([
      supabase.from('agent_grants')
        .select('id, client_id, client_name, client_uri, created_at, last_used_at, revoked_at')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false }),
      supabase.from('agent_access_log')
        .select('id, client_id, tool, query, filters, item_id, item_title, result_count, created_at')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(50),
    ]);
    if (grantsRes.error || activityRes.error) {
      console.error('connected agents load failed:', grantsRes.error ?? activityRes.error);
      toast({ title: 'Could not load connected agents', description: 'Reload the page to try again.', variant: 'destructive' });
    }
    setGrants((grantsRes.data ?? []) as ConnectedAgent[]);
    setActivity((activityRes.data ?? []) as AgentAccessRow[]);
    setLoading(false);
  }, [user, toast]);

  useEffect(() => { load(); }, [load]);

  const clientNameFor = useCallback(
    (clientId: string) => grants.find((g) => g.client_id === clientId)?.client_name ?? 'An agent',
    [grants],
  );

  // Supabase first (kills the client's sessions + refresh tokens), then our
  // row (closes the MCP door for tokens still inside their hour).
  const revoke = async (grant: ConnectedAgent) => {
    if (!session?.access_token) return;
    setRevoking(grant.id);
    try {
      await revokeOAuthGrant(grant.client_id, session.access_token);
      const { error } = await supabase.from('agent_grants')
        .update({ revoked_at: new Date().toISOString() })
        .eq('id', grant.id);
      if (error) throw error;
      toast({ title: `${grant.client_name} disconnected` });
      await load();
    } catch (e) {
      console.error('revoke failed:', e);
      toast({ title: 'Could not disconnect', description: 'Try again in a moment.', variant: 'destructive' });
    } finally {
      setRevoking(null);
    }
  };

  return {
    active: grants.filter((g) => !g.revoked_at),
    activity,
    loading,
    revoke,
    revoking,
    clientNameFor,
  };
};
```

- [ ] **Step 6: Write the settings component**

```tsx
// src/components/settings/ConnectedAgentsSettings.tsx
import { formatDistanceToNow } from 'date-fns';
import { Copy, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { useToast } from '@/hooks/use-toast';
import { useConnectedAgents } from '@/hooks/useConnectedAgents';
import { MCP_SERVER_URL, describeAgentActivity } from '@/utils/agentActivity';

const relative = (iso: string) => formatDistanceToNow(new Date(iso), { addSuffix: true });

const ConnectedAgentsSettings = () => {
  const { toast } = useToast();
  const { active, activity, loading, revoke, revoking, clientNameFor } = useConnectedAgents();

  const copyUrl = () => {
    navigator.clipboard.writeText(MCP_SERVER_URL);
    toast({ title: 'Copied', description: 'Paste it into your agent as a remote MCP server.' });
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Connect an agent</CardTitle>
          <CardDescription>
            Let an AI agent you trust search your stash. Agents get answers, never copies: they can search
            and read items one at a time, can't change anything, and every request is logged here.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="flex items-center gap-2">
            <code className="flex-1 truncate rounded-xl border border-black/[0.07] bg-[rgba(20,22,30,0.03)] px-3 py-2 text-sm text-[#22262f]">
              {MCP_SERVER_URL}
            </code>
            <Button variant="outline" size="sm" onClick={copyUrl} aria-label="Copy MCP server URL">
              <Copy className="h-4 w-4" />
            </Button>
          </div>
          <div className="space-y-3 text-sm text-muted-foreground">
            <p><span className="font-medium text-foreground">Claude (web or desktop):</span> Settings → Connectors → Add custom connector → paste the URL → Connect. Claude sends you here to approve.</p>
            <p><span className="font-medium text-foreground">Claude Code:</span> <code className="rounded bg-[rgba(20,22,30,0.05)] px-1 py-0.5">claude mcp add --transport http stash {MCP_SERVER_URL}</code></p>
            <p><span className="font-medium text-foreground">Other agents:</span> any client that supports remote MCP servers with OAuth sign-in.</p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Connected</CardTitle>
          <CardDescription>Agents that can search your stash right now.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          ) : active.length === 0 ? (
            <p className="text-sm text-muted-foreground">No agents connected yet. Paste the URL above into one to start.</p>
          ) : (
            <ul className="divide-y divide-black/[0.06]">
              {active.map((g) => (
                <li key={g.id} className="flex items-center justify-between gap-4 py-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-foreground">{g.client_name}</p>
                    <p className="text-xs text-muted-foreground">
                      Connected {relative(g.created_at)}
                      {g.last_used_at ? ` · last used ${relative(g.last_used_at)}` : ' · not used yet'}
                    </p>
                  </div>
                  <AlertDialog>
                    <AlertDialogTrigger asChild>
                      <Button variant="outline" size="sm" disabled={revoking === g.id}>
                        {revoking === g.id ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Revoke'}
                      </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                      <AlertDialogHeader>
                        <AlertDialogTitle>Disconnect {g.client_name}?</AlertDialogTitle>
                        <AlertDialogDescription>
                          It loses access immediately. You can connect it again any time.
                        </AlertDialogDescription>
                      </AlertDialogHeader>
                      <AlertDialogFooter>
                        <AlertDialogCancel>Keep connected</AlertDialogCancel>
                        <AlertDialogAction onClick={() => revoke(g)}>Revoke access</AlertDialogAction>
                      </AlertDialogFooter>
                    </AlertDialogContent>
                  </AlertDialog>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Activity</CardTitle>
          <CardDescription>Every search and read, newest first.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading ? (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          ) : activity.length === 0 ? (
            <p className="text-sm text-muted-foreground">No activity yet. Once an agent connects, every search and read shows up here.</p>
          ) : (
            <ul className="divide-y divide-black/[0.06]">
              {activity.map((row) => (
                <li key={row.id} className="flex items-start justify-between gap-4 py-2.5">
                  <p className="text-sm text-foreground">{describeAgentActivity(row, clientNameFor(row.client_id))}</p>
                  <p className="shrink-0 text-xs text-muted-foreground">{relative(row.created_at)}</p>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
};

export default ConnectedAgentsSettings;
```

- [ ] **Step 7: Add the tab**

In `src/pages/Settings.tsx`:
- Change the lucide import to `import { Settings as SettingsIcon, Smartphone, User, Crown, Tag, Bot } from 'lucide-react';`
- Add `import ConnectedAgentsSettings from '@/components/settings/ConnectedAgentsSettings';` after the `TagsSettings` import.
- Change `grid-cols-4` to `grid-cols-5` on the `TabsList`.
- After the subscription `TabsTrigger`, add:
```tsx
          <TabsTrigger value="agents" className="flex items-center gap-2">
            <Bot className="h-4 w-4" />
            Connected agents
          </TabsTrigger>
```
- After the subscription `TabsContent`, add:
```tsx
        <TabsContent value="agents" className="mt-0">
          <ConnectedAgentsSettings />
        </TabsContent>
```

- [ ] **Step 8: Static metadata + headers**

Create `public/.well-known/oauth-protected-resource/mcp` (no extension) with:
```json
{"resource":"https://www.gostash.it/mcp","authorization_servers":["https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1"],"scopes_supported":["email"],"bearer_methods_supported":["header"],"resource_name":"Stash"}
```
Add a `headers` array to `vercel.json` (keep the rewrites from Task 1):
```json
  "headers": [
    {
      "source": "/.well-known/oauth-protected-resource/mcp",
      "headers": [
        { "key": "Content-Type", "value": "application/json; charset=utf-8" },
        { "key": "Cache-Control", "value": "public, max-age=3600" }
      ]
    }
  ]
```

- [ ] **Step 9: Typecheck, test, commit, merge to main, push (deploy point)**

```bash
npx tsc --noEmit -p tsconfig.app.json && npm test
git add src/utils/agentActivity.ts src/utils/agentActivity.test.ts src/hooks/useConnectedAgents.ts \
  src/components/settings/ConnectedAgentsSettings.tsx src/pages/Settings.tsx \
  public/.well-known/oauth-protected-resource/mcp vercel.json
git commit -m "feat(mcp): Settings → Connected agents (connect, revoke, activity) + static resource metadata"
# from the main checkout:
git merge --ff-only feat/mcp-server && git push origin main
```

- [ ] **Step 10: Verify the deployed web surface**

After Vercel finishes: `curl -s -i https://www.gostash.it/.well-known/oauth-protected-resource/mcp | sed -n '1,12p'` → expect `200`, JSON body, `content-type: application/json` (if it serves `index.html`, the static route lost to Vercel's `.well-known` handling — note it and rely on the 401 pointer; nothing else depends on it).

With Playwright MCP: `browser_navigate` to `https://www.gostash.it/auth`, sign in as `will+uitest@dzierson.com`, navigate to `/settings`, click "Connected agents" → three cards render; "No agents connected yet." and "No activity yet." empty states show; Copy puts the URL on the clipboard (toast "Copied"). Then navigate to `/oauth/consent` (no id) → "This link is missing its authorization request." card. Take a screenshot of the tab for the ui-changes entry.

---

### Task 9: Turn on the OAuth server

**Files:**
- Modify: `supabase/config.toml` (mirror of the hosted config)

- [ ] **Step 1: Read the current allow list, then PATCH the config**

```bash
TOKEN=$(security find-generic-password -s "Supabase CLI" -a "supabase" -w | sed 's/^go-keyring-base64://' | base64 -d)
CUR=$(curl -s -H "Authorization: Bearer $TOKEN" https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/config/auth | python3 -c 'import json,sys; print(json.load(sys.stdin)["uri_allow_list"])')
curl -s -X PATCH https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/config/auth \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(python3 - "$CUR" <<'EOF'
import json, sys
cur = sys.argv[1]
allow = ",".join([u for u in cur.split(",") if u] + ["https://www.gostash.it/**", "https://gostash.it/**"])
print(json.dumps({
  "site_url": "https://www.gostash.it",
  "uri_allow_list": allow,
  "oauth_server_enabled": True,
  "oauth_server_allow_dynamic_registration": True,
  "oauth_server_authorization_path": "/oauth/consent",
}))
EOF
)" | python3 -c 'import json,sys; c=json.load(sys.stdin); print({k:c.get(k) for k in ("site_url","oauth_server_enabled","oauth_server_allow_dynamic_registration","oauth_server_authorization_path")})'
```
Expected: `{'site_url': 'https://www.gostash.it', 'oauth_server_enabled': True, 'oauth_server_allow_dynamic_registration': True, 'oauth_server_authorization_path': '/oauth/consent'}`.

- [ ] **Step 2: Verify discovery**

```bash
curl -s https://uqqsgmwkvslaomzxptnp.supabase.co/.well-known/oauth-authorization-server/auth/v1 | python3 -m json.tool | grep -E '"issuer"|registration_endpoint|authorization_endpoint|token_endpoint"|code_challenge_methods_supported' -A1
```
Expected: `issuer` = `https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1`, a `registration_endpoint`, `authorization_endpoint` ending `/oauth/authorize`, `token_endpoint` ending `/oauth/token`, and `S256` under `code_challenge_methods_supported`.

- [ ] **Step 3: Mirror in config.toml and commit**

Append to `supabase/config.toml` under the `[auth]` block:
```toml
# Hosted project has the same values (set 2026-09-05 via the Management API):
# Supabase is the OAuth 2.1 authorization server for the MCP endpoint.
[auth.oauth_server]
enabled = true
authorization_url_path = "/oauth/consent"
allow_dynamic_registration = true
```
Also change `site_url = "http://localhost:3000"` to `site_url = "https://www.gostash.it"` so local config no longer lies about production.

```bash
git add supabase/config.toml
git commit -m "chore(auth): enable Supabase OAuth 2.1 server for MCP (consent at /oauth/consent)"
```

---

### Task 10: End-to-end smoke — OAuth, tools, fence, revocation

**Files:**
- Create: `scripts/mcp-smoke.mjs`

**Interfaces:**
- Consumes: everything deployed. Writes `/tmp/stash-mcp-smoke.json` (tokens) for the `--reuse` run.

- [ ] **Step 1: Write the smoke script**

```js
#!/usr/bin/env node
// scripts/mcp-smoke.mjs — end-to-end check of the Stash MCP server.
//
//   node scripts/mcp-smoke.mjs                 # full run: discovery → DCR → PKCE authorize (you approve in a browser) → tools → fence
//   node scripts/mcp-smoke.mjs --reuse         # re-run the tool + fence calls with the saved token (e.g. after revoking in Settings)
//   node scripts/mcp-smoke.mjs --server https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp
//
// Node 18+, no dependencies. Mirrors what Claude does: reads the 401 challenge,
// fetches protected-resource + authorization-server metadata, registers a
// public client with a loopback redirect, and exchanges the code with PKCE.
import http from 'node:http';
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const SERVER = opt('--server', 'https://www.gostash.it/mcp');
const QUERY = opt('--query', 'design');
const PORT = Number(opt('--port', '8765'));
const REUSE = args.includes('--reuse');
const STATE_FILE = '/tmp/stash-mcp-smoke.json';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE';
const SUPABASE = 'https://uqqsgmwkvslaomzxptnp.supabase.co';

const b64url = (buf) => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const ok = (label, cond, detail = '') => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}`); if (!cond) process.exitCode = 1; };

async function rpc(token, id, method, params) {
  const res = await fetch(SERVER, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jsonrpc: '2.0', ...(id === undefined ? {} : { id }), method, ...(params ? { params } : {}) }),
  });
  return { status: res.status, body: res.status === 202 ? null : await res.json().catch(() => null), www: res.headers.get('www-authenticate') };
}

async function oauth() {
  const first = await fetch(SERVER, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
  ok('unauthenticated POST → 401', first.status === 401, String(first.status));
  const www = first.headers.get('www-authenticate') || '';
  const prmUrl = /resource_metadata="([^"]+)"/.exec(www)?.[1];
  ok('401 carries resource_metadata', !!prmUrl, www);
  const prm = await (await fetch(prmUrl)).json();
  ok('resource matches server URL', prm.resource === SERVER, `${prm.resource} vs ${SERVER}`);
  const issuer = new URL(prm.authorization_servers[0]);
  const asMeta = await (await fetch(`${issuer.origin}/.well-known/oauth-authorization-server${issuer.pathname}`)).json();
  ok('authorization server metadata', !!asMeta.registration_endpoint && !!asMeta.token_endpoint, JSON.stringify(Object.keys(asMeta)));

  const redirectUri = `http://127.0.0.1:${PORT}/callback`;
  const reg = await (await fetch(asMeta.registration_endpoint, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_name: 'Stash MCP smoke test', client_uri: 'https://www.gostash.it',
      redirect_uris: [redirectUri], grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'], token_endpoint_auth_method: 'none',
    }),
  })).json();
  ok('dynamic client registration', !!reg.client_id, JSON.stringify(reg).slice(0, 200));

  const verifier = b64url(randomBytes(32));
  const challenge = b64url(createHash('sha256').update(verifier).digest());
  const state = b64url(randomBytes(12));
  const authorizeUrl = `${asMeta.authorization_endpoint}?${new URLSearchParams({
    response_type: 'code', client_id: reg.client_id, redirect_uri: redirectUri, state,
    code_challenge: challenge, code_challenge_method: 'S256', scope: 'email',
  })}`;

  const code = await new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const u = new URL(req.url, `http://127.0.0.1:${PORT}`);
      if (u.pathname !== '/callback') { res.writeHead(404).end(); return; }
      res.writeHead(200, { 'Content-Type': 'text/plain' }).end('Stash smoke test: you can close this tab.');
      server.close();
      if (u.searchParams.get('state') !== state) return reject(new Error('state mismatch'));
      if (u.searchParams.get('error')) return reject(new Error(`${u.searchParams.get('error')}: ${u.searchParams.get('error_description')}`));
      resolve(u.searchParams.get('code'));
    });
    server.listen(PORT, '127.0.0.1', () => {
      console.log(`\nOpen this URL, sign in as the test account, and approve:\n\n${authorizeUrl}\n`);
    });
  });

  const tokens = await (await fetch(asMeta.token_endpoint, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'authorization_code', code, client_id: reg.client_id, redirect_uri: redirectUri, code_verifier: verifier }),
  })).json();
  ok('token exchange', !!tokens.access_token, JSON.stringify(tokens).slice(0, 160));
  writeFileSync(STATE_FILE, JSON.stringify({ client_id: reg.client_id, ...tokens }, null, 2));
  return tokens.access_token;
}

async function tools(token) {
  const init = await rpc(token, 1, 'initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'smoke', version: '0' } });
  ok('initialize', init.status === 200 && init.body?.result?.serverInfo?.name === 'stash', JSON.stringify(init.body).slice(0, 200));
  const note = await rpc(token, undefined, 'notifications/initialized');
  ok('notifications/initialized → 202', note.status === 202, String(note.status));
  const list = await rpc(token, 2, 'tools/list');
  const names = (list.body?.result?.tools ?? []).map((t) => t.name);
  ok('tools/list', names.includes('search_stash') && names.includes('get_item'), names.join(','));
  const search = await rpc(token, 3, 'tools/call', { name: 'search_stash', arguments: { query: QUERY, limit: 3 } });
  const results = search.body?.result?.structuredContent?.results ?? [];
  ok('search_stash returns results', search.status === 200 && !search.body?.result?.isError && results.length > 0, (search.body?.result?.content?.[0]?.text ?? '').slice(0, 200));
  if (results[0]) {
    const item = await rpc(token, 4, 'tools/call', { name: 'get_item', arguments: { id: results[0].id } });
    ok('get_item reads the first hit', item.status === 200 && !item.body?.result?.isError, (item.body?.result?.content?.[0]?.text ?? '').slice(0, 160));
  }
  const missing = await rpc(token, 5, 'tools/call', { name: 'get_item', arguments: { id: '00000000-0000-0000-0000-000000000000' } });
  ok('get_item unknown id → isError', missing.body?.result?.isError === true);
  const listing = await rpc(token, 6, 'tools/call', { name: 'search_stash', arguments: { types: ['link'], limit: 2 } });
  ok('search_stash without query lists', !listing.body?.result?.isError, String(listing.body?.result?.structuredContent?.count));
}

async function fence(token) {
  const rest = await fetch(`${SUPABASE}/rest/v1/items?select=id&limit=1`, { headers: { apikey: ANON, Authorization: `Bearer ${token}` } });
  const rows = await rest.json().catch(() => null);
  ok('fence: PostgREST items → no rows for agent token', Array.isArray(rows) && rows.length === 0, `${rest.status} ${JSON.stringify(rows).slice(0, 80)}`);
  const fn = await fetch(`${SUPABASE}/functions/v1/search-items`, { method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{"limit":1}' });
  ok('fence: search-items refuses agent token', fn.status === 401 || fn.status === 403, String(fn.status));
  const add = await fetch(`${SUPABASE}/functions/v1/add-note`, { method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{"content":"smoke"}' });
  ok('fence: add-note refuses agent token', add.status === 403, String(add.status));
}

const token = REUSE ? JSON.parse(readFileSync(STATE_FILE, 'utf8')).access_token : await oauth();
if (REUSE) {
  const ping = await rpc(token, 1, 'ping');
  console.log(`reuse: ping → ${ping.status} ${JSON.stringify(ping.body)} ${ping.www ?? ''}`);
}
await tools(token);
await fence(token);
```

- [ ] **Step 2: Run the full flow (browser approval via Playwright)**

```bash
node scripts/mcp-smoke.mjs --query design   # keep running; it prints the authorize URL and waits
```
In Playwright MCP: `browser_navigate` to the printed URL → Supabase redirects to `https://www.gostash.it/oauth/consent?authorization_id=…` → the page bounces to `/auth?returnTo=…` (sign in as the test account) → back on the consent card: confirm it shows "Stash MCP smoke test wants to connect to your Stash", the can/can't lists, "Returns to 127.0.0.1", and the loopback warning → click **Allow access** → the browser lands on `http://127.0.0.1:8765/callback` ("you can close this tab").

Expected script output: every line `PASS` — 401 challenge, metadata, registration, token exchange, initialize, 202, tools/list, search results, get_item, unknown id → isError, listing, and the three fence checks.

If `dynamic client registration` FAILS on the loopback `redirect_uris`, re-run with `--port 443`-style hosted redirect is not possible; instead record the failure in the Outcome section: hosted Claude (redirect `https://claude.ai/api/mcp/auth_callback`) is unaffected, Claude Code is the gap.

- [ ] **Step 3: Confirm the audit trail and Settings rendering**

```bash
q "select tool, query, result_count, item_title, created_at from agent_access_log order by created_at desc limit 6"
q "select client_name, scopes, last_used_at, revoked_at from agent_grants order by created_at desc limit 3"
```
Expected: rows for the calls just made; `last_used_at` set; `revoked_at` null.

Playwright: `/settings` → Connected agents → "Stash MCP smoke test" listed with "last used less than a minute ago"; Activity shows "Stash MCP smoke test searched for “design” · 3 results" and "… read “<title>”". Screenshot for the ui-changes entry.

- [ ] **Step 4: Revoke and prove the door closes**

Playwright: click **Revoke** → confirm **Revoke access** → toast "Stash MCP smoke test disconnected"; the Connected list shows the empty state; Activity remains.

```bash
node scripts/mcp-smoke.mjs --reuse
q "select revoked_at is not null as revoked from agent_grants where client_name = 'Stash MCP smoke test'"
```
Expected: `reuse: ping → 401` or `403` (Supabase kills the session on grant revoke → 401 `invalid_token`; if the JWT is still honored, our grant check yields 403 `insufficient_scope`); every subsequent line `FAIL` is expected here and confirms revocation. `revoked` = true.

- [ ] **Step 5: Reconnect works (re-consent un-revokes)**

Run `node scripts/mcp-smoke.mjs` again and approve → all `PASS`; `q "select revoked_at from agent_grants where client_name = 'Stash MCP smoke test'"` → null. Then revoke once more from Settings so the test account is left clean.

- [ ] **Step 6: Commit**

```bash
git add scripts/mcp-smoke.mjs
git commit -m "test(mcp): end-to-end OAuth + tools + fence + revocation smoke script"
```

---

### Task 11: Real client check, docs, memory, merge

**Files:**
- Modify: `docs/PLATFORM_API.md` (new section before "Message routing convention")
- Modify: `docs/ui-changes.md` (new top entry)
- Modify: `docs/superpowers/plans/2026-09-05-mcp-server.md` (Outcome section at the bottom)

- [ ] **Step 1: Claude Code as a real client (if available in the session)**

```bash
claude mcp add --transport http stash https://www.gostash.it/mcp
claude mcp list
```
Then in an interactive `claude` session run `/mcp` → authenticate → approve on the consent page → ask "search my stash for design". Expected: tools appear as `mcp__stash__search_stash` / `mcp__stash__get_item` and return results. If the session cannot run the interactive flow, record it as a step for Will in the Outcome section (exact commands above).

- [ ] **Step 2: PLATFORM_API.md — "Agents (MCP)" section**

Insert before `## Message routing convention — RETIRED 2026-08-27`:

```markdown
## Agents (MCP)

Remote MCP server (Streamable HTTP, JSON responses, stateless):
`https://www.gostash.it/mcp` (a Vercel rewrite to the `mcp` edge function).
Read-only. Spec: `docs/superpowers/specs/2026-09-05-mcp-server-design.md`.

**Auth** is OAuth 2.1 through Supabase Auth's OAuth server — not the session
JWT used everywhere else. Unauthenticated requests get
`401` + `WWW-Authenticate: Bearer resource_metadata="https://www.gostash.it/mcp/.well-known/oauth-protected-resource", scope="email"`;
clients discover the authorization server
(`https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1`), register dynamically,
and send the user to `https://www.gostash.it/oauth/consent` to approve. The
consent page records an `agent_grants` row; the server refuses tokens whose
client has no active row. Session JWTs are refused on `/mcp`; agent tokens
(JWTs carrying a `client_id` claim) are refused on every other endpoint and
get zero rows through PostgREST/Storage (restrictive RLS) — agents receive
answers, never copies.

**Tools:** `search_stash` (same request/response shape as `POST /search-items`,
plus a readable text rendering) and `get_item` (`{ id }` → notes, description,
summary, captured text capped at 12k chars, `attributes.link.flavor`,
`attributes.location.label`). Every call is logged to `agent_access_log`
(Settings → Connected agents → Activity) and rate-limited per grant
(60/min, 2,000/day → `isError` result).

**Client contracts** (any surface adding a "Connected agents" screen):
active grants = `agent_grants` where `revoked_at is null` (owner RLS);
activity = last 50 `agent_access_log` rows, rendered per
`src/utils/agentActivity.ts`; revoke = `DELETE /auth/v1/user/oauth/grants?client_id=…`
(session JWT) **then** set `agent_grants.revoked_at`.
```

- [ ] **Step 3: ui-changes.md entry (top of file, after the `---`)**

```markdown
## 2026-09-05 · Connect an agent (MCP server) — web

Read-only MCP server at `https://www.gostash.it/mcp` behind Supabase's OAuth
2.1 server; spec `docs/superpowers/specs/2026-09-05-mcp-server-design.md`,
plan `docs/superpowers/plans/2026-09-05-mcp-server.md`, wire contract in
`docs/PLATFORM_API.md` → "Agents (MCP)".

- **New route `/oauth/consent`** (Supabase redirects here with
  `?authorization_id=`): one card — "<Agent> wants to connect to your Stash",
  *It can* (search your stash · read saved items in full), *It can't* (add,
  edit or delete anything · export your stash · see your account or billing),
  signed-in email, "Returns to <host>" with an amber warning for loopback
  hosts, **Allow access** / **Deny**. Signed-out visitors bounce through
  `/auth?returnTo=…` and come back. Approve upserts `agent_grants`
  (`scopes = ['read']`, `revoked_at = null`) before consent is sent.
- **Settings gains a fifth tab, "Connected agents"** (lucide `Bot`): Connect
  card (URL + copy, Claude / Claude Code / other how-tos), Connected list
  (name · connected · last used · **Revoke** with confirm), Activity list
  (last 50 sentences from `agent_access_log`, e.g. "Claude searched for
  “restaurants in Saratoga” · 3 results", "Claude read “Beyond the Basics”").
  No subscription gate.
- **Contracts for iOS/macOS** (no screens yet): read `agent_grants`
  (`revoked_at is null`) and `agent_access_log` (owner RLS); revoke = GoTrue
  `DELETE /auth/v1/user/oauth/grants?client_id=` then set `revoked_at`.
  Sentence rules: `src/utils/agentActivity.ts`.
- **Behavior change for all clients:** OAuth-issued agent tokens are rejected
  by every non-MCP edge function (403) and by RLS. Session tokens are
  unaffected.
```

- [ ] **Step 4: Outcome section + final commit, merge, push (deploy point)**

Append to this plan:
```markdown
## Outcome (2026-09-05)
- Endpoint: <www.gostash.it/mcp via rewrite | raw function URL> (Task 1 result).
- Smoke: <all PASS | which lines failed and why>.
- Claude Code loopback DCR: <worked | gap>.
- Static /.well-known metadata on Vercel: <served | falls back to 401 pointer>.
- Left for Will: connect a real Claude connector from claude.ai (Settings →
  Connectors → Add custom connector → https://www.gostash.it/mcp).
```
Then:
```bash
git add docs/PLATFORM_API.md docs/ui-changes.md docs/superpowers/plans/2026-09-05-mcp-server.md
git commit -m "docs(mcp): platform API contract, ui-changes entry, plan outcome"
# from the main checkout:
git merge --ff-only feat/mcp-server && git push origin main
```
Finally update memory (`project-vision-roadmap.md` / a new `mcp-server.md`): what shipped, the endpoint, the fence rule, the smoke script, and any gap found.
