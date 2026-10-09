// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as any,
  inserted: null as Record<string, unknown> | null,
  invoke: vi.fn(),
  update: vi.fn(),
  background: [] as Promise<unknown>[],
}));

vi.mock('https://esm.sh/@supabase/supabase-js@2.50.2', () => ({
  createClient: () => ({
    auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    from: () => ({
      insert: (row: Record<string, unknown>) => {
        state.inserted = row;
        return { select: () => ({ single: async () => ({ data: { id: 'item-1', ...row }, error: null }) }) };
      },
      update: (row: Record<string, unknown>) => {
        state.update(row);
        return { eq: async () => ({ error: null }) };
      },
    }),
    functions: { invoke: state.invoke },
  }),
}));
vi.mock('../_shared/agentToken.ts', () => ({ isAgentToken: () => false }));
vi.mock('../_shared/entitlementGate.ts', () => ({ requireEntitlement: async () => null }));

beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: () => 'test' }, serve: (handler: any) => { state.handler = handler; } });
  vi.stubGlobal('EdgeRuntime', { waitUntil: (promise: Promise<unknown>) => state.background.push(promise) });
  await import('./index.ts');
});

beforeEach(() => {
  vi.clearAllMocks();
  state.inserted = null;
  state.background = [];
  state.invoke.mockImplementation(async (name: string) => ({ data: name === 'generate-title' ? { title: 'Generated title' } : { description: 'Generated description' } }));
});

async function save(content: string, title?: string) {
  const response = await state.handler(new Request('https://stash.example/add-note', {
    method: 'POST',
    headers: { Authorization: 'Bearer user-token', 'Content-Type': 'application/json' },
    body: JSON.stringify({ content, title }),
  }));
  await Promise.all(state.background);
  return response;
}

describe('add-note evidence guard', () => {
  it.each([
    'https://youtube.com/watch?v=abc123XYZ_0&si=share-token',
    ' \nhttps://youtu.be/abc123XYZ_0\n ',
    'http://example.com/article',
  ])('does not invent a title or description from a bare URL: %s', async content => {
    const response = await save(content);
    expect(response.status).toBe(200);
    expect(state.inserted).toMatchObject({ type: 'text', content, description: null });
    expect(state.invoke.mock.calls.map(([name]) => name)).toEqual(['generate-embeddings']);
    expect(state.update).not.toHaveBeenCalled();
  });

  it('keeps a user-provided title for a direct URL-only note', async () => {
    await save('https://youtube.com/watch?v=abc123XYZ_0', 'Watch later');
    expect(state.inserted?.title).toBe('Watch later');
    expect(state.invoke.mock.calls.map(([name]) => name)).toEqual(['generate-embeddings']);
  });

  it('continues asynchronous enrichment for actual prose', async () => {
    await save('Use this video for the garden project: https://youtu.be/abc123XYZ_0');
    expect(state.invoke.mock.calls.map(([name]) => name)).toEqual([
      'generate-embeddings', 'generate-title', 'generate-description', 'generate-embeddings',
    ]);
    expect(state.update).toHaveBeenCalledWith({ title: 'Generated title', description: 'Generated description' });
  });
});
