// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const ADMIN = 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
const MEMBER = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
const PROPOSAL = 'cccccccc-cccc-4ccc-cccc-cccccccccccc';
const REQUEST = 'dddddddd-dddd-4ddd-dddd-dddddddddddd';
const state = vi.hoisted(() => ({
  handler: null as any,
  authenticate: vi.fn(), rpc: vi.fn(), from: vi.fn(), getUserById: vi.fn(),
  admin: true, adminError: null as any, itemsError: null as any,
  queries: [] as Array<{ table: string; filters: [string, unknown][]; columns?: string }>,
}));
vi.mock('https://deno.land/std@0.168.0/http/server.ts', () => ({ serve: (handler: any) => { state.handler = handler; } }));
vi.mock('../_shared/auth.ts', () => ({ authenticateUser: state.authenticate }));

beforeAll(async () => { await import('./index.ts'); });
beforeEach(() => {
  vi.clearAllMocks(); state.admin = true; state.adminError = null; state.itemsError = null; state.queries = [];
  vi.spyOn(console, 'log').mockImplementation(() => {});
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  vi.spyOn(console, 'error').mockImplementation(() => {});
  state.from.mockImplementation((table: string) => {
    const query = { table, filters: [] as [string, unknown][], columns: '' }; state.queries.push(query);
    const builder = {
      select: (columns: string) => { query.columns = columns; return builder; },
      eq: (key: string, value: unknown) => { query.filters.push([key, value]); return builder; },
      maybeSingle: async () => table === 'admin_users'
        ? { data: state.admin ? { user_id: ADMIN } : null, error: state.adminError }
        : { data: { username: 'will', display_name: 'Will' }, error: null },
      order: async () => ({ data: [{ id: 'item-1', title: 'Saved article' }], error: state.itemsError }),
    }; return builder;
  });
  state.getUserById.mockResolvedValue({ data: { user: { id: MEMBER, email: 'member@example.com', created_at: '2026-01-01' } }, error: null });
  state.authenticate.mockResolvedValue({ user: { id: ADMIN }, supabaseAdmin: {
    from: state.from, rpc: state.rpc, auth: { admin: { getUserById: state.getUserById } },
  } });
  state.rpc.mockResolvedValue({ data: null, error: null });
});
function request(body: unknown, method = 'POST') {
  return new Request('https://stash.example/admin-stats', {
    method, headers: { authorization: 'Bearer verified-user-token', 'content-type': 'application/json' },
    ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
  });
}
const review = (patch: Record<string, unknown> = {}) => ({ action: 'review_proposal', proposal_id: PROPOSAL,
  expected_revision: 2, new_status: 'needs_evidence', review_note: '  Add a reproducible fixture.  ', request_id: REQUEST, ...patch });

describe('admin-stats authentication and compatibility', () => {
  it('serves preflight and refuses other methods without authentication', async () => {
    expect((await state.handler(request(null, 'OPTIONS'))).status).toBe(200);
    expect((await state.handler(request(null, 'GET'))).status).toBe(405);
    expect(state.authenticate).not.toHaveBeenCalled();
  });
  it('does not disclose authentication exceptions', async () => {
    state.authenticate.mockRejectedValue(new Error('supabase key secret-auth-diagnostic'));
    const response = await state.handler(request({ action: 'enrichment' }));
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'Authentication failed' });
    expect(state.from).not.toHaveBeenCalled(); expect(state.rpc).not.toHaveBeenCalled();
  });
  it.each([{ action: 'users' }, { action: 'items', user_id: MEMBER }, { action: 'enrichment' }, review()])
    ('requires current admin membership for every action: %o', async (body) => {
      state.admin = false;
      const response = await state.handler(request(body));
      expect(response.status).toBe(403); expect(state.rpc).not.toHaveBeenCalled(); expect(state.getUserById).not.toHaveBeenCalled();
      expect(state.queries).toEqual([{ table: 'admin_users', filters: [['user_id', ADMIN]], columns: 'user_id' }]);
      expect(state.authenticate).toHaveBeenCalledWith('Bearer verified-user-token');
    });
  it('stops on admin membership database errors', async () => {
    state.adminError = { message: 'secret connection details' };
    const response = await state.handler(request({ action: 'enrichment' }));
    expect(response.status).toBe(500); expect(await response.json()).toEqual({ error: 'Admin check failed' });
    expect(state.rpc).not.toHaveBeenCalled();
  });
  it('preserves the users response and RPC', async () => {
    const users = [{ user_id: MEMBER, total_items: 7 }]; state.rpc.mockResolvedValue({ data: users, error: null });
    const response = await state.handler(request({ action: 'users' }));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ users });
    expect(state.rpc).toHaveBeenCalledWith('admin_user_stats');
  });
  it('preserves member library reads and their owner filter', async () => {
    const response = await state.handler(request({ action: 'items', user_id: MEMBER }));
    expect(response.status).toBe(200); expect(await response.json()).toEqual({
      user: { user_id: MEMBER, email: 'member@example.com', username: 'will', display_name: 'Will', created_at: '2026-01-01' },
      items: [{ id: 'item-1', title: 'Saved article' }],
    });
    expect(state.queries.find(q => q.table === 'items')?.filters).toEqual([['user_id', MEMBER]]);
  });
  it('preserves missing member responses', async () => {
    state.getUserById.mockResolvedValue({ data: null, error: { message: 'missing user' } });
    expect((await state.handler(request({ action: 'items', user_id: MEMBER }))).status).toBe(404);
  });
  it('does not expose legacy RPC failures', async () => {
    state.rpc.mockResolvedValue({ data: null, error: { message: 'secret database details' } });
    const response = await state.handler(request({ action: 'users' }));
    expect(response.status).toBe(500); expect(await response.text()).not.toContain('secret');
  });
  it('does not expose unexpected transport exceptions', async () => {
    state.from.mockImplementation(() => { throw new Error('secret connection details'); });
    const response = await state.handler(request({ action: 'enrichment' }));
    expect(response.status).toBe(500); expect(await response.json()).toEqual({ error: 'Admin request failed' });
    expect(JSON.stringify(vi.mocked(console.error).mock.calls)).not.toContain('secret');
  });
  it('returns JSON without caching private admin results', async () => {
    state.rpc.mockResolvedValue({ data: [], error: null });
    const response = await state.handler(request({ action: 'users' }));
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(response.headers.get('content-type')).toBe('application/json');
    expect(response.headers.get('access-control-allow-methods')).toBe('POST, OPTIONS');
  });
});

describe('admin-stats enrichment and proposal review', () => {
  it('reads the bounded dashboard with the JWT actor', async () => {
    const enrichment = { pipeline: { ready: 42 }, proposals: [] };
    state.rpc.mockResolvedValue({ data: enrichment, error: null });
    const response = await state.handler(request({ action: 'enrichment', lookback_hours: 168, proposal_status: 'new', proposal_limit: 30 }));
    expect(response.status).toBe(200); expect(await response.json()).toEqual(enrichment);
    expect(state.rpc).toHaveBeenCalledWith('admin_enrichment_quality', {
      actor_user_id: ADMIN, lookback_hours: 168, proposal_status: 'new', proposal_limit: 30,
    });
  });
  it('records triage only with a server-derived actor and optimistic revision', async () => {
    const result = { ok: true, id: PROPOSAL, revision: 3, status: 'needs_evidence', reviewed_at: '2026-10-10T05:00:00Z', idempotent: false };
    state.rpc.mockResolvedValue({ data: result, error: null });
    const response = await state.handler(request(review()));
    expect(response.status).toBe(200); expect(await response.json()).toEqual(result);
    expect(state.rpc).toHaveBeenCalledWith('review_hosted_quality_proposal', {
      actor_user_id: ADMIN, target_id: PROPOSAL, expected_revision: 2, new_status: 'needs_evidence',
      review_note: 'Add a reproducible fixture.', request_id: REQUEST,
    });
  });
  it('accepts a successful idempotent retry without changing its request identity', async () => {
    state.rpc.mockResolvedValue({ data: { ok: true, id: PROPOSAL, revision: 3, status: 'needs_evidence', reviewed_at: '2026-10-10T05:00:00Z', idempotent: true }, error: null });
    const response = await state.handler(request(review()));
    expect(response.status).toBe(200); expect(await response.json()).toMatchObject({ idempotent: true, revision: 3 });
    expect(state.rpc.mock.calls[0][1].request_id).toBe(REQUEST);
  });
  it.each(['version_conflict', 'request_conflict'])('returns a concurrency conflict for %s', async (error) => {
    const result = { ok: false, error, revision: 3, status: 'planned' };
    state.rpc.mockResolvedValue({ data: result, error: null });
    const response = await state.handler(request(review()));
    expect(response.status).toBe(409); expect(await response.json()).toEqual(result);
  });
  it('returns not found when the proposal was removed', async () => {
    state.rpc.mockResolvedValue({ data: { ok: false, error: 'not_found' }, error: null });
    expect((await state.handler(request(review()))).status).toBe(404);
  });
  it.each([{ action: 'enrichment', actor_user_id: MEMBER }, review({ actor_user_id: MEMBER }), review({ evidence_urls: ['https://fake.example'] })])
    ('rejects actor forgery and edits to evidence before invoking a privileged RPC: %o', async (body) => {
      expect((await state.handler(request(body))).status).toBe(400); expect(state.rpc).not.toHaveBeenCalled();
    });
  it.each([{ code: '42501', expected: 403 }, { code: '22023', expected: 400 }, { code: 'XX000', expected: 500 }])
    ('maps database failures to safe responses: $code', async ({ code, expected }) => {
      state.rpc.mockResolvedValue({ data: null, error: { code, message: 'secret database details', details: 'secret SQL' } });
      const response = await state.handler(request(review()));
      expect(response.status).toBe(expected); expect(await response.text()).not.toContain('secret');
    });
  it('fails closed if the RPC unexpectedly returns no review result', async () => {
    expect((await state.handler(request(review()))).status).toBe(500);
  });
  it('bounds the request size before reading the JSON', async () => {
    expect((await state.handler(request(review({ review_note: 'x'.repeat(20_000) })))).status).toBe(413);
    expect(state.rpc).not.toHaveBeenCalled();
  });
  it('refuses malformed JSON without reaching a privileged RPC', async () => {
    const response = await state.handler(new Request('https://stash.example/admin-stats', {
      method: 'POST', headers: { authorization: 'Bearer verified-user-token' }, body: '{"action":"review_proposal",',
    }));
    expect(response.status).toBe(400); expect(state.rpc).not.toHaveBeenCalled();
  });
});
