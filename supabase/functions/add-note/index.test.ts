// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as any,
  inserted: null as Record<string, unknown> | null,
  attributes: {} as Record<string, unknown>,
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
      // The re-read after the pictures were described
      select: () => ({ eq: () => ({ single: async () => ({ data: { attributes: state.attributes }, error: null }) }) }),
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
  state.attributes = {};
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

  it('derives every field from the words of a Novel JSON note, never its scaffolding', async () => {
    const doc = JSON.stringify({ type: 'doc', content: [
      { type: 'paragraph', content: [{ type: 'text', text: 'Buy milk for the ' }, { type: 'text', marks: [{ type: 'bold' }], text: 'weekend' }] },
      { type: 'paragraph', content: [{ type: 'text', text: 'and eggs' }] },
    ] });
    await save(doc);
    expect(state.inserted).toMatchObject({ content: doc, title: 'Buy milk for the weekend' });
    expect(state.invoke.mock.calls[0]).toEqual(['generate-embeddings', { body: { itemId: 'item-1', textContent: 'Buy milk for the weekend\nand eggs' } }]);
    expect(state.invoke.mock.calls.find(([name]) => name === 'generate-title')?.[1]).toEqual({ body: { content: 'Buy milk for the weekend\nand eggs' } });
  });

  it('caps the fallback title at the first line, sixty characters', async () => {
    const long = 'A'.repeat(70) + '\nsecond line';
    await save(long);
    expect(state.inserted?.title).toBe('A'.repeat(57) + '...');
    await save('Short first line\nmore');
    expect(state.inserted?.title).toBe('Short first line');
  });

  it('continues asynchronous enrichment for actual prose', async () => {
    await save('Use this video for the garden project: https://youtu.be/abc123XYZ_0');
    expect(state.invoke.mock.calls.map(([name]) => name)).toEqual([
      'generate-embeddings', 'generate-title', 'generate-description', 'generate-embeddings',
    ]);
    expect(state.update).toHaveBeenCalledWith({ title: 'Generated title', description: 'Generated description' });
  });
});

describe('add-note pictures', () => {
  const picture = 'https://x.supabase.co/storage/v1/object/public/stash-media/user-1/notes/a.png';
  const withPicture = JSON.stringify({ type: 'doc', content: [
    { type: 'image', attrs: { src: picture } },
    { type: 'paragraph', content: [{ type: 'text', text: 'image + text using / command' }] },
  ] });

  it('has the pictures described first, and titles and describes the note from words and pictures', async () => {
    state.attributes = { note_images: { version: 1, images: [{ src: picture, description: 'A blood test report in a table.', text: 'RBC 4.7', analyzed_at: 't' }] } };
    await save(withPicture);
    const names = state.invoke.mock.calls.map(([name]) => name);
    expect(names).toEqual(['generate-embeddings', 'analyze-note-images', 'generate-title', 'generate-description', 'generate-embeddings']);
    expect(state.invoke.mock.calls[1][1]).toEqual({ body: { itemId: 'item-1' } });
    const words = 'image + text using / command\n\nA blood test report in a table.\nText in the image: RBC 4.7';
    expect(state.invoke.mock.calls[2][1]).toEqual({ body: { content: words } });
    expect(state.invoke.mock.calls[3][1]).toEqual({ body: { content: words, type: 'text' } });
  });

  it('still titles a note that is only a picture', async () => {
    const onlyPicture = JSON.stringify({ type: 'doc', content: [{ type: 'image', attrs: { src: picture } }] });
    state.attributes = { note_images: { version: 1, images: [{ src: picture, description: 'The InsideTracker logo.', analyzed_at: 't' }] } };
    await save(onlyPicture);
    expect(state.inserted?.title).toBe('');
    const names = state.invoke.mock.calls.map(([name]) => name);
    // No words to embed up front; the pictures, then the models, then the index
    expect(names).toEqual(['analyze-note-images', 'generate-title', 'generate-description', 'generate-embeddings']);
    expect(state.invoke.mock.calls[1][1]).toEqual({ body: { content: 'The InsideTracker logo.' } });
    expect(state.update).toHaveBeenCalledWith({ title: 'Generated title', description: 'Generated description' });
  });

  it('does not ask for pictures a note does not have', async () => {
    await save('plain words');
    expect(state.invoke.mock.calls.map(([name]) => name)).not.toContain('analyze-note-images');
  });

  it('keeps going on the words when the pictures cannot be described', async () => {
    state.invoke.mockImplementation(async (name: string) => {
      if (name === 'analyze-note-images') return { data: null, error: new Error('down') };
      return { data: name === 'generate-title' ? { title: 'Generated title' } : { description: 'Generated description' } };
    });
    await save(withPicture);
    expect(state.invoke.mock.calls.find(([name]) => name === 'generate-title')?.[1]).toEqual({ body: { content: 'image + text using / command' } });
  });
});
