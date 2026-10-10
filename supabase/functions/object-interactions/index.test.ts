// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { createObjectInteractionsHandler } from './handler';
import { buildObjectIntelligenceSource, objectIntelligenceFingerprint, parseObjectIntelligenceOutput } from '../_shared/objectIntelligence';
import { buildObjectInteractionDraft } from '../_shared/objectInteractionDraft';

const itemId = '11111111-1111-4111-8111-111111111111';
const ownerId = '22222222-2222-4222-8222-222222222222';
const jwt = (claims = {}) => `eyJhbGciOiJIUzI1NiJ9.${btoa(JSON.stringify({ sub: ownerId, ...claims }))}.signature`;
const request = (body: unknown = { operation: 'inspect', item_id: itemId }, token: string | null = jwt()) => new Request('https://backend.example/object-interactions', {
  method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body),
});

async function setup() {
  const item = { id: itemId, user_id: ownerId, type: 'text', content: 'Penne recipe: penne, cherry tomatoes, basil and olive oil. Blister the tomatoes in oil, then toss with cooked penne and basil.', attributes: {} as Record<string, unknown> };
  const source = buildObjectIntelligenceSource(item)!;
  const fingerprint = await objectIntelligenceFingerprint(source);
  const intelligence = parseObjectIntelligenceOutput({ interpretation: { kind: 'recipe', summary: 'Pasta with tomatoes and basil.', topics: ['pasta'] },
    facts: { recipe: { ingredients: [{ value: 'penne', evidence_ids: ['e1'] }] } },
    evidence: [{ id: 'e1', source_id: 'content', quote: 'penne, cherry tomatoes, basil and olive oil' }] }, source, fingerprint)!;
  item.attributes.object_intelligence = intelligence;
  const state = { item: item as typeof item | null, job: { status: 'queued' } as { status: string } | null, dbError: null as unknown };
  const queries: Array<{ table: string; columns: string; filters: Array<[string, string]> }> = [];
  const getUser = vi.fn(async () => ({ data: { user: { id: ownerId, email: 'owner@example.org' } }, error: null as unknown }));
  const db = { auth: { getUser }, from(table: string) {
    const query = { table, columns: '', filters: [] as Array<[string, string]> }; queries.push(query);
    const chain = { select(columns: string) { query.columns = columns; return chain; }, eq(column: string, value: string) { query.filters.push([column, value]); return chain; },
      async maybeSingle() { return { data: table === 'items' ? state.item : state.job, error: state.dbError }; } };
    return chain;
  } };
  const requireEntitlement = vi.fn(async () => null as Response | null);
  const draft = { version: 1 as const, action: 'shopping_list' as const, title: 'Shopping list', content: '- penne', source_item_id: itemId, source_fingerprint: fingerprint,
    created_at: '2026-10-10T12:00:00.000Z', evidence_ids: ['e1'], notices: [] as string[] };
  const buildDraft = vi.fn(() => draft as typeof draft | undefined);
  const handle = createObjectInteractionsHandler({ db, requireEntitlement, buildDraft });
  return { handle, db, state, queries, getUser, requireEntitlement, buildDraft, draft, fingerprint, intelligence };
}

describe('object interactions endpoint', () => {
  it('handles preflight and rejects non-POST without querying private data', async () => {
    const h = await setup();
    const preflight = await h.handle(new Request('https://backend.example', { method: 'OPTIONS' }));
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get('Access-Control-Allow-Methods')).toBe('POST, OPTIONS');
    const get = await h.handle(new Request('https://backend.example'));
    expect(get.status).toBe(405); expect(get.headers.get('Allow')).toBe('POST, OPTIONS');
    expect(h.getUser).not.toHaveBeenCalled(); expect(h.queries).toEqual([]);
  });

  it('requires a verified session token before reading any item', async () => {
    const h = await setup();
    expect((await h.handle(request(undefined, null))).status).toBe(401);
    h.getUser.mockResolvedValue({ data: { user: null as any }, error: { message: 'private auth detail' } });
    const invalid = await h.handle(request());
    expect(invalid.status).toBe(401); expect(await invalid.json()).toEqual({ error: 'unauthorized' });
    expect(h.queries).toEqual([]); expect(h.requireEntitlement).not.toHaveBeenCalled();
  });

  it('refuses OAuth agent tokens and service-role JWTs even if getUser is misconfigured to accept them', async () => {
    for (const claims of [{ client_id: 'oauth-client' }, { role: 'service_role' }]) {
      const h = await setup(); const response = await h.handle(request(undefined, jwt(claims)));
      expect(response.status).toBe(403); expect(h.queries).toEqual([]); expect(h.buildDraft).not.toHaveBeenCalled();
    }
  });

  it('scopes the item lookup to the verified owner, returning the same absence response for missing or foreign items', async () => {
    const h = await setup(); h.state.item = null;
    const response = await h.handle(request());
    expect(response.status).toBe(404); expect(await response.json()).toEqual({ error: 'item_not_found' });
    expect(h.queries).toHaveLength(1);
    expect(h.queries[0].filters).toEqual([['id', itemId], ['user_id', ownerId]]);
    expect(h.buildDraft).not.toHaveBeenCalled();
    const foreign = await setup(); foreign.state.item!.user_id = '33333333-3333-4333-8333-333333333333';
    expect((await foreign.handle(request())).status).toBe(404);
    expect(foreign.queries).toHaveLength(1);
  });

  it('returns freshly validated source-bound intelligence without entitlement or queue work', async () => {
    const h = await setup(); const response = await h.handle(request());
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ status: 'ready', intelligence: h.intelligence });
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(h.queries.map(q => q.table)).toEqual(['items']); expect(h.requireEntitlement).not.toHaveBeenCalled();
    expect(h.buildDraft).not.toHaveBeenCalled();
  });

  it('normalizes case-insensitive UUID input before owner-scoped lookup and draft binding', async () => {
    const h = await setup(); const canonicalId = 'abcdef12-1111-4111-8111-111111111111';
    h.state.item!.id = canonicalId;
    const response = await h.handle(request({ operation: 'inspect', item_id: canonicalId.toUpperCase() }));
    expect(response.status).toBe(200); expect((await response.json()).status).toBe('ready');
    expect(h.queries[0].filters).toEqual([['id', canonicalId], ['user_id', ownerId]]);
    const drafted = await h.handle(request({ operation: 'draft', item_id: canonicalId.toUpperCase(), action: 'shopping_list', source_fingerprint: h.fingerprint }));
    expect(drafted.status).toBe(200);
    expect(h.buildDraft).toHaveBeenCalledWith(h.intelligence, 'shopping_list', canonicalId);
  });

  it.each(['queued', 'processing'])('reports pending only for current source with a %s job', async status => {
    const h = await setup(); h.state.item!.content += ' Updated source.'; h.state.job = { status };
    const response = await h.handle(request());
    expect(await response.json()).toEqual({ status: 'pending' });
    expect(h.queries[1]).toEqual({ table: 'object_intelligence_jobs', columns: 'status', filters: [['item_id', itemId]] });
  });

  it.each(['no_evidence', 'failed', 'unsupported', 'protected', 'complete'])('does not promise completion for a %s job with no valid intelligence', async status => {
    const h = await setup(); delete h.state.item!.attributes.object_intelligence; h.state.job = { status };
    expect(await (await h.handle(request())).json()).toEqual({ status: 'unavailable' });
  });

  it('does not show generated descriptions or absent source as pending evidence', async () => {
    const h = await setup(); h.state.item!.content = ''; h.state.job = { status: 'processing' };
    expect(await (await h.handle(request())).json()).toEqual({ status: 'unavailable' });
    expect(h.queries.map(q => q.table)).toEqual(['items']);
  });

  it('treats missing jobs and malformed stored claims as unavailable', async () => {
    const h = await setup(); h.state.job = null;
    h.intelligence.facts.recipe!.ingredients![0].value = 'unsupported ingredient';
    expect(await (await h.handle(request())).json()).toEqual({ status: 'unavailable' });
    const draft = await h.handle(request({ operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: h.fingerprint }));
    expect(draft.status).toBe(409); expect(await draft.json()).toEqual({ error: 'intelligence_unavailable' });
    expect(h.buildDraft).not.toHaveBeenCalled();
  });

  it('requires exact operation-specific fields, UUID, supported action and current fingerprint', async () => {
    for (const body of [null, [], {}, { operation: 'inspect', item_id: 'bad' }, { operation: 'inspect', item_id: itemId, user_id: ownerId },
      { operation: 'inspect', item_id: itemId, action: 'shopping_list' }, { operation: 'draft', item_id: itemId, action: 'shopping_list' },
      { operation: 'draft', item_id: itemId, action: 'grocery_order', source_fingerprint: 'a'.repeat(64) },
      { operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: 'bad' }]) {
      const h = await setup(); const response = await h.handle(request(body));
      expect(response.status).toBe(400); expect(h.queries).toEqual([]); expect(h.buildDraft).not.toHaveBeenCalled();
    }
  });

  it('bounds actual request bytes independently of Content-Length and rejects malformed JSON', async () => {
    const h = await setup();
    for (const body of ['x'.repeat(8193), JSON.stringify({ operation: 'inspect', item_id: itemId, excess: '🍅'.repeat(2100) })]) {
      const response = await h.handle(new Request('https://backend.example', { method: 'POST', headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json' }, body }));
      expect(response.status).toBe(413);
    }
    const invalid = await h.handle(new Request('https://backend.example', { method: 'POST', headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json' }, body: '{bad' }));
    expect(invalid.status).toBe(400); expect(h.queries).toEqual([]);
    const announced = await h.handle(new Request('https://backend.example', { method: 'POST', headers: { Authorization: `Bearer ${jwt()}`, 'Content-Type': 'application/json', 'Content-Length': '999999' }, body: '{}' }));
    expect(announced.status).toBe(413); expect(h.queries).toEqual([]);
  });

  it('refuses non-JSON bodies', async () => {
    const h = await setup(); const response = await h.handle(new Request('https://backend.example', { method: 'POST', headers: { Authorization: `Bearer ${jwt()}` }, body: '{}' }));
    expect(response.status).toBe(415); expect(h.queries).toEqual([]);
  });

  it('gates draft creation by entitlement while allowing inspect on a lapsed account', async () => {
    const h = await setup(); h.requireEntitlement.mockResolvedValue(new Response(JSON.stringify({ error: 'subscription_required', message: 'Reactivate your subscription.' }), { status: 403 }));
    const response = await h.handle(request({ operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: h.fingerprint }));
    expect(response.status).toBe(403); expect((await response.json()).error).toBe('subscription_required');
    expect(response.headers.get('Cache-Control')).toBe('no-store'); expect(h.buildDraft).not.toHaveBeenCalled();
    expect(h.requireEntitlement).toHaveBeenCalledWith({ id: ownerId, email: 'owner@example.org' });
    expect((await h.handle(request())).status).toBe(200);
  });

  it('rejects stale source fingerprints and capabilities missing current evidence', async () => {
    const h = await setup();
    const stale = await h.handle(request({ operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: 'a'.repeat(64) }));
    expect(stale.status).toBe(409); expect(await stale.json()).toEqual({ error: 'source_changed' });
    const unavailable = await h.handle(request({ operation: 'draft', item_id: itemId, action: 'recipe_card', source_fingerprint: h.fingerprint }));
    expect(unavailable.status).toBe(409); expect(await unavailable.json()).toEqual({ error: 'action_unavailable' });
    expect(h.buildDraft).not.toHaveBeenCalled();
  });

  it('refuses a previously current envelope after source evidence changes', async () => {
    const h = await setup(); h.state.item!.content += ' New ingredients.';
    const response = await h.handle(request({ operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: h.fingerprint }));
    expect(response.status).toBe(409); expect(await response.json()).toEqual({ error: 'source_changed' });
    expect(h.buildDraft).not.toHaveBeenCalled();
  });

  it('drafts only using validated current facts and returns the helper result without saving another item', async () => {
    const h = await setup(); const response = await h.handle(request({ operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: h.fingerprint }));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ draft: h.draft });
    expect(h.buildDraft).toHaveBeenCalledExactlyOnceWith(h.intelligence, 'shopping_list', itemId);
    expect(h.queries.map(q => q.table)).toEqual(['items']);
  });

  it('integrates the real pure helper without adding interpretation text to the shopping list', async () => {
    const h = await setup(); const handle = createObjectInteractionsHandler({ db: h.db, requireEntitlement: h.requireEntitlement, buildDraft: buildObjectInteractionDraft });
    const response = await handle(request({ operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: h.fingerprint }));
    expect(response.status).toBe(200);
    const { draft } = await response.json();
    expect(draft).toMatchObject({ version: 1, action: 'shopping_list', source_item_id: itemId, source_fingerprint: h.fingerprint, evidence_ids: ['e1'] });
    expect(draft.content).toContain('penne');
    expect(draft.content).not.toContain(h.intelligence.interpretation.summary);
    expect(h.queries.map(q => q.table)).toEqual(['items']);
  });

  it('treats a declined pure draft as unavailable and hides internal failures', async () => {
    const h = await setup(); h.buildDraft.mockReturnValue(undefined);
    const body = { operation: 'draft', item_id: itemId, action: 'shopping_list', source_fingerprint: h.fingerprint };
    const unavailable = await h.handle(request(body));
    expect(unavailable.status).toBe(409); expect(await unavailable.json()).toEqual({ error: 'action_unavailable' });
    h.state.dbError = new Error('private query and source text');
    const failed = await h.handle(request());
    expect(failed.status).toBe(503); expect(await failed.json()).toEqual({ error: 'object_interactions_unavailable' });
    expect(failed.headers.get('Cache-Control')).toBe('no-store');
  });
});
