// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as any,
  item: null as Record<string, unknown> | null,
  invoke: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock('https://esm.sh/@supabase/supabase-js@2.50.2', () => ({
  createClient: () => ({ functions: { invoke: state.invoke }, rpc: state.rpc }),
}));
vi.mock('../_shared/enrichmentAuth.ts', () => ({
  requireItemAccess: async () => {
    if (!state.item) throw new Error('Item not found or access denied');
    return state.item;
  },
}));

const A = 'https://x.supabase.co/storage/v1/object/public/stash-media/u/notes/a.png';
const B = 'https://x.supabase.co/storage/v1/object/public/stash-media/u/notes/b.png';
const doc = (...srcs: string[]) =>
  JSON.stringify({
    type: 'doc',
    content: [
      ...srcs.map((src) => ({ type: 'image', attrs: { src } })),
      { type: 'paragraph', content: [{ type: 'text', text: 'image + text using / command' }] },
    ],
  });

beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: () => 'test' }, serve: (handler: any) => { state.handler = handler; } });
  await import('./index.ts');
});

beforeEach(() => {
  vi.clearAllMocks();
  state.item = null;
  state.rpc.mockResolvedValue({ data: true, error: null });
  state.invoke.mockImplementation(async (name: string, { body }: { body: { imageUrl?: string } }) => {
    if (name === 'analyze-image') {
      return { data: { success: true, description: `A picture at ${body.imageUrl}`, detected_text: body.imageUrl === A ? 'RBC 4.7' : 'none' }, error: null };
    }
    return { data: { success: true }, error: null };
  });
});

const call = async (itemId = 'item-1') => {
  const response = await state.handler(
    new Request('https://stash.example/analyze-note-images', {
      method: 'POST',
      headers: { authorization: 'Bearer user-token', 'content-type': 'application/json' },
      body: JSON.stringify({ itemId }),
    }),
  );
  return { status: response.status, body: await response.json() };
};

describe('analyze-note-images', () => {
  it('describes each picture once, keeps the text it carries, writes the leaf and re-indexes', async () => {
    state.item = { id: 'item-1', content: doc(A, B), attributes: {} };
    const { status, body } = await call();
    expect(status).toBe(200);
    expect(body).toMatchObject({ success: true, changed: true, described: 2, pending: 0 });
    const vision = state.invoke.mock.calls.filter(([name]) => name === 'analyze-image').map(([, { body }]) => body);
    expect(vision).toEqual([{ imageUrl: A }, { imageUrl: B }]);
    const [, args] = state.rpc.mock.calls[0];
    expect(args.target_id).toBe('item-1');
    expect(args.expected).toBeNull();
    expect(args.next.version).toBe(1);
    expect(args.next.images.map((i: any) => i.src)).toEqual([A, B]);
    expect(args.next.images[0]).toMatchObject({ description: `A picture at ${A}`, text: 'RBC 4.7' });
    expect(args.next.images[1]).not.toHaveProperty('text');
    expect(state.invoke.mock.calls.at(-1)).toEqual(['generate-embeddings', { body: { itemId: 'item-1' } }]);
  });

  it('sends nothing to the model when every picture is already described', async () => {
    const known = { version: 1, images: [{ src: A, description: 'Known', analyzed_at: 't' }] };
    state.item = { id: 'item-1', content: doc(A), attributes: { note_images: known } };
    const { body } = await call();
    expect(body).toMatchObject({ success: true, changed: false, described: 0 });
    expect(state.invoke).not.toHaveBeenCalled();
    expect(state.rpc).not.toHaveBeenCalled();
  });

  it('drops the pictures that left the note and describes only the new one', async () => {
    const known = { version: 1, images: [{ src: A, description: 'Known', analyzed_at: 't' }] };
    state.item = { id: 'item-1', content: doc(B), attributes: { note_images: known } };
    const { body } = await call();
    expect(body).toMatchObject({ changed: true, described: 1 });
    expect(state.invoke.mock.calls.filter(([name]) => name === 'analyze-image')).toHaveLength(1);
    const [, args] = state.rpc.mock.calls[0];
    expect(args.expected).toEqual(known);
    expect(args.next.images.map((i: any) => i.src)).toEqual([B]);
  });

  it('clears the leaf when the last picture is removed', async () => {
    const known = { version: 1, images: [{ src: A, description: 'Known', analyzed_at: 't' }] };
    state.item = { id: 'item-1', content: JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'words' }] }] }), attributes: { note_images: known } };
    const { body } = await call();
    expect(body).toMatchObject({ changed: true, described: 0 });
    expect(state.rpc.mock.calls[0][1].next).toBeNull();
  });

  it('keeps going when a picture cannot be described, and leaves it for the next save', async () => {
    state.invoke.mockImplementation(async (name: string, { body }: { body: { imageUrl?: string } }) => {
      if (name === 'analyze-image') return body.imageUrl === A ? { data: { success: false, error: 'vision down' }, error: null } : { data: { success: true, description: 'B' }, error: null };
      return { data: {}, error: null };
    });
    state.item = { id: 'item-1', content: doc(A, B), attributes: {} };
    const { body } = await call();
    expect(body).toMatchObject({ changed: true, described: 1, pending: 1 });
    expect(state.rpc.mock.calls[0][1].next.images.map((i: any) => i.src)).toEqual([B]);
  });

  it('answers item_changed when the leaf moved under it, and does not re-index', async () => {
    state.rpc.mockResolvedValue({ data: false, error: null });
    state.item = { id: 'item-1', content: doc(A), attributes: {} };
    const { body } = await call();
    expect(body).toEqual({ success: false, reason: 'item_changed' });
    expect(state.invoke.mock.calls.map(([name]) => name)).not.toContain('generate-embeddings');
  });

  it('refuses a save the caller cannot reach', async () => {
    const { status } = await call('someone-elses');
    expect(status).toBe(403);
  });
});
