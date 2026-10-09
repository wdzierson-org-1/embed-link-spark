import { generateEmbeddings } from './aiOperations';

const invoke = vi.hoisted(() => vi.fn());
vi.mock('@/integrations/supabase/client', () => ({ supabase: { functions: { invoke } } }));

// What supabase-js hands back for a non-2xx function response: the Response rides in `context`
const httpError = (status: number) => ({ name: 'FunctionsHttpError', message: 'Edge Function returned a non-2xx status code', context: { status } });

beforeEach(() => {
  invoke.mockReset();
  vi.spyOn(console, 'log').mockImplementation(() => {});
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

describe('generateEmbeddings', () => {
  it('asks the function to index the save', async () => {
    invoke.mockResolvedValue({ data: { success: true }, error: null });
    await expect(generateEmbeddings('item-1', '  some text  ')).resolves.toEqual({ deferred: false });
    expect(invoke).toHaveBeenCalledWith('generate-embeddings', { body: { itemId: 'item-1', textContent: 'some text' } });
  });

  it('treats 409 item_changed as deferred, not failed: the save changed while indexing and its changer re-indexes', async () => {
    invoke.mockResolvedValue({ data: null, error: httpError(409) });
    await expect(generateEmbeddings('item-1', 'text')).resolves.toEqual({ deferred: true });
    expect(console.error).not.toHaveBeenCalled();
  });

  it('reads the same outcome from a 200 whose body says item_changed (the function no longer answers 409)', async () => {
    invoke.mockResolvedValue({ data: { success: false, chunksProcessed: 0, reason: 'item_changed' }, error: null });
    await expect(generateEmbeddings('item-1', 'text')).resolves.toEqual({ deferred: true });
    expect(console.error).not.toHaveBeenCalled();
  });

  it('still throws on a real failure', async () => {
    invoke.mockResolvedValue({ data: null, error: httpError(500) });
    await expect(generateEmbeddings('item-1', 'text')).rejects.toMatchObject({ name: 'FunctionsHttpError' });
  });
});
