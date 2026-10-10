import { createObjectDraft, inspectObject, ObjectInteractionError } from './objectInteractions';

const { invoke } = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { functions: { invoke } } }));
const fingerprint = 'a'.repeat(64);
const draft = { version: 1, action: 'shopping_list', title: 'Shopping list', content: '- tomatoes', source_item_id: 'source', source_fingerprint: fingerprint, created_at: '2026-10-10T14:00:00.000Z', evidence_ids: ['e1'], notices: ['Review before saving.'] };

beforeEach(() => { invoke.mockReset(); });
afterEach(() => { vi.useRealTimers(); });

it.each([
  { source_item_id: 'other' }, { source_fingerprint: 'b'.repeat(64) }, { action: 'itinerary' },
  { title: 'x'.repeat(161) }, { content: 'é'.repeat(12_001) }, { evidence_ids: ['raw-source'] },
])('rejects incorrectly bound or oversized draft responses %#', async patch => {
  invoke.mockResolvedValue({ data: { draft: { ...draft, ...patch } }, error: null });
  await expect(createObjectDraft('source', 'shopping_list', fingerprint)).rejects.toBeInstanceOf(ObjectInteractionError);
});

it('sends only item/action/source binding and returns a server draft', async () => {
  invoke.mockResolvedValue({ data: { draft }, error: null });
  expect(await createObjectDraft('source', 'shopping_list', fingerprint)).toEqual(draft);
  expect(invoke).toHaveBeenCalledWith('object-interactions', { body: { operation: 'draft', item_id: 'source', action: 'shopping_list', source_fingerprint: fingerprint } });
});

it('classifies stale errors without showing provider messages', async () => {
  invoke.mockResolvedValue({ data: null, error: { message: 'private provider details', context: new Response(JSON.stringify({ error: 'source_changed' }), { status: 409 }) } });
  await expect(createObjectDraft('source', 'shopping_list', fingerprint)).rejects.toMatchObject({ code: 'stale', message: 'stale' });
});

it.each([
  [403, 'subscription_required', 'subscription_required'], [403, 'session_required', 'session_required'],
  [401, 'unauthorized', 'session_required'], [404, 'item_not_found', 'item_unavailable'],
  [409, 'intelligence_unavailable', 'intelligence_unavailable'], [409, 'action_unavailable', 'action_unavailable'],
  [409, 'private_unknown_error', 'request_failed'],
])('classifies closed API code %s %s', async (status, error, code) => {
  const context = new Response(JSON.stringify({ error, message: 'Untrusted private message' }), { status });
  invoke.mockResolvedValue({ data: null, error: { context } });
  await expect(createObjectDraft('source', 'shopping_list', fingerprint)).rejects.toMatchObject({ code, message: code });
  expect(context.bodyUsed).toBe(false);
});

it('times out an unresponsive inspection', async () => {
  vi.useFakeTimers(); invoke.mockReturnValue(new Promise(() => {}));
  const outcome = inspectObject('source').catch(error => error);
  await vi.advanceTimersByTimeAsync(30_000);
  expect(await outcome).toMatchObject({ code: 'request_failed' });
});
