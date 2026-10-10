import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import ObjectIntelligenceSection from './ObjectIntelligenceSection';
import type { ObjectIntelligence } from '../../../supabase/functions/_shared/objectIntelligence';
import { CaptureError } from '@/utils/captureClient';

const { invoke, captureContent } = vi.hoisted(() => ({ invoke: vi.fn(), captureContent: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { functions: { invoke } } }));
vi.mock('@/utils/captureClient', async importOriginal => ({ ...(await importOriginal<typeof import('@/utils/captureClient')>()), captureContent }));

const intelligence: ObjectIntelligence = {
  version: 1, beta: true, extraction_version: 'object-intelligence-v1',
  source_fingerprint: 'a'.repeat(64), processed_at: '2026-10-10T14:00:00.000Z',
  interpretation: { kind: 'recipe', summary: 'A quick tomato pasta.', topics: ['Pasta'] },
  facts: {
    creator: { value: '@sundaysupper', evidence_ids: ['e2'] },
    recipe: { name: { value: 'Tomato pasta', evidence_ids: ['e1'] }, ingredients: [{ value: 'penne', evidence_ids: ['e1'] }, { value: 'tomatoes', evidence_ids: ['e1'] }], steps: [{ value: 'Boil the penne.', evidence_ids: ['e1'] }] },
  },
  evidence: [{ id: 'e1', source_id: 'page', quote: 'Tomato pasta: penne and tomatoes. Boil the penne.' }, { id: 'e2', source_id: 'creator_metadata', quote: '@sundaysupper' }],
  capabilities: [
    { id: 'shopping_list', status: 'source_ready', effect: 'draft', prerequisites: [], requires_confirmation: false },
    { id: 'recipe_card', status: 'source_ready', effect: 'draft', prerequisites: [], requires_confirmation: false },
    { id: 'grocery_order', status: 'needs_lookup', effect: 'external_write', prerequisites: ['retailer'], requires_confirmation: true },
  ],
};
const item = { id: 'source-item', type: 'link', attributes: { object_intelligence: intelligence } };
const draft = { version: 1, action: 'shopping_list', title: 'Tomato pasta shopping list', content: '- penne\n- tomatoes', source_item_id: item.id, source_fingerprint: intelligence.source_fingerprint, created_at: '2026-10-10T14:05:00.000Z', evidence_ids: ['e1'], notices: ['Quantities were not provided.'] };
const ready = () => ({ data: { status: 'ready', intelligence }, error: null });
const draftResult = () => ({ data: { draft }, error: null });
const deferred = <T,>() => { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; };

beforeEach(() => { invoke.mockReset(); captureContent.mockReset(); invoke.mockResolvedValue(ready()); captureContent.mockResolvedValue({ id: 'saved-note' }); });
afterEach(() => { vi.useRealTimers(); });

it('displays only server-validated facts with exact source quotations and supported actions', async () => {
  const onReady = vi.fn();
  render(<ObjectIntelligenceSection item={{ ...item, attributes: { object_intelligence: { ...intelligence, facts: { creator: { value: 'Unvalidated creator', evidence_ids: [] } } } } }} userId="owner" onReady={onReady} />);
  expect(await screen.findByText('@sundaysupper', { selector: 'dd' })).toBeVisible();
  expect(screen.queryByText('Unvalidated creator')).not.toBeInTheDocument();
  expect(screen.getByText('Stash’s interpretation')).toBeVisible();
  expect(screen.getByText(/A quick tomato pasta\./)).toBeVisible();
  expect(screen.getByRole('button', { name: 'Create a shopping list' })).toBeVisible();
  expect(screen.queryByText(/order groceries/i)).not.toBeInTheDocument();
  const ingredients = screen.getByText('Ingredients').closest('div')!;
  fireEvent.click(within(ingredients).getByText('View source'));
  expect(within(ingredients).getByText(intelligence.evidence[0].quote)).toBeVisible();
  expect(invoke).toHaveBeenCalledWith('object-interactions', { body: { operation: 'inspect', item_id: item.id } });
  expect(onReady).toHaveBeenLastCalledWith(intelligence);
});

it('previews a draft, preserves edits on save failure, and saves one private derivative through capture', async () => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult());
  captureContent.mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce({ id: 'saved-note' });
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  expect(await screen.findByLabelText('Draft content')).toHaveValue(draft.content);
  expect(screen.getByText('Quantities were not provided.')).toBeVisible();
  fireEvent.change(screen.getByLabelText('Draft title'), { target: { value: 'Dinner supplies' } });
  fireEvent.change(screen.getByLabelText('Draft content'), { target: { value: '- penne\n- cherry tomatoes' } });
  fireEvent.click(screen.getByRole('button', { name: 'Save to Stash' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not save');
  expect(screen.getByLabelText('Draft content')).toHaveValue('- penne\n- cherry tomatoes');
  fireEvent.click(screen.getByRole('button', { name: 'Save to Stash' }));
  expect(await screen.findByRole('button', { name: 'Saved to Stash' })).toBeDisabled();
  expect(captureContent).toHaveBeenLastCalledWith('text', expect.objectContaining({ title: 'Dinner supplies', content: '- penne\n- cherry tomatoes', is_public: false, attributes: { derived_from: expect.objectContaining({ item_id: item.id, source_fingerprint: intelligence.source_fingerprint, action: 'shopping_list', edited: true }) } }), 'owner');
});

it('requires an inline decision before replacing an edited draft and preserves it on stale source', async () => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult()).mockResolvedValueOnce({ data: null, error: { context: new Response(JSON.stringify({ error: 'source_changed' }), { status: 409 }) } });
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  fireEvent.change(await screen.findByLabelText('Draft content'), { target: { value: 'My edited list' } });
  fireEvent.click(screen.getByRole('button', { name: 'Create a recipe card' }));
  expect(screen.getByText(/Replace your edited draft/)).toBeVisible();
  expect(invoke).toHaveBeenCalledTimes(2);
  fireEvent.click(screen.getByRole('button', { name: 'Keep draft' }));
  expect(screen.getByLabelText('Draft content')).toHaveValue('My edited list');
  fireEvent.click(screen.getByRole('button', { name: 'Create a recipe card' }));
  fireEvent.click(screen.getByRole('button', { name: 'Replace draft' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('source changed');
  expect(screen.getByLabelText('Draft content')).toHaveValue('My edited list');
  expect(screen.getByRole('button', { name: 'Refresh details' })).toBeVisible();
});

it('clears old drafts on item changes and ignores the previous item’s late response', async () => {
  const late = deferred<ReturnType<typeof draftResult>>();
  invoke.mockResolvedValueOnce(ready()).mockReturnValueOnce(late.promise).mockResolvedValueOnce({ data: { status: 'unavailable' }, error: null });
  const { rerender } = render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  rerender(<ObjectIntelligenceSection item={{ id: 'other-item' }} userId="owner" />);
  await act(async () => { late.resolve(draftResult()); });
  expect(screen.queryByLabelText('Draft content')).not.toBeInTheDocument();
  expect(screen.queryByText('@sundaysupper')).not.toBeInTheDocument();
});

it('keeps draft edits when a refreshed envelope arrives and labels earlier source versions', async () => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult()).mockResolvedValueOnce({ data: { status: 'ready', intelligence: { ...intelligence, source_fingerprint: 'b'.repeat(64) } }, error: null });
  const { rerender } = render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  fireEvent.change(await screen.findByLabelText('Draft title'), { target: { value: 'My dinner' } });
  rerender(<ObjectIntelligenceSection item={{ ...item, attributes: { object_intelligence: { ...intelligence, source_fingerprint: 'b'.repeat(64) } } }} userId="owner" />);
  expect(await screen.findByText(/earlier version of the source/)).toBeVisible();
  expect(screen.getByLabelText('Draft title')).toHaveValue('My dinner');
});

it('bounds automatic pending checks and does not poll while the document is hidden', async () => {
  vi.useFakeTimers();
  invoke.mockResolvedValue({ data: { status: 'pending' }, error: null });
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  await act(async () => { await Promise.resolve(); });
  for (let count = 0; count < 5; count++) await act(async () => { await vi.advanceTimersByTimeAsync(15_000); });
  expect(invoke).toHaveBeenCalledTimes(5);
  expect(screen.queryByText('Checking available details…')).not.toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Refresh details' })).toBeEnabled();
  fireEvent.click(screen.getByRole('button', { name: 'Refresh details' }));
  await act(async () => { await Promise.resolve(); });
  Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' });
  await act(async () => { await vi.advanceTimersByTimeAsync(30_000); });
  expect(invoke).toHaveBeenCalledTimes(6);
  Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' });
});

it('blocks duplicate saves while capture is pending and after success', async () => {
  const saving = deferred<{ id: string }>();
  captureContent.mockReturnValue(saving.promise);
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult());
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  const save = await screen.findByRole('button', { name: 'Save to Stash' });
  fireEvent.click(save); fireEvent.click(save);
  expect(captureContent).toHaveBeenCalledTimes(1);
  expect(screen.getByLabelText('Draft content')).toBeDisabled();
  await act(async () => { saving.resolve({ id: 'new-note' }); });
  fireEvent.click(screen.getByRole('button', { name: 'Saved to Stash' }));
  expect(captureContent).toHaveBeenCalledTimes(1);
});

it('copies edited plain text and keeps edits when clipboard access fails', async () => {
  const writeText = vi.fn().mockRejectedValueOnce(new Error('denied')).mockResolvedValueOnce(undefined);
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult());
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  fireEvent.change(await screen.findByLabelText('Draft content'), { target: { value: '<b>My list</b>' } });
  fireEvent.click(screen.getByRole('button', { name: 'Copy draft' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not copy');
  expect(screen.getByLabelText('Draft content')).toHaveValue('<b>My list</b>');
  fireEvent.click(screen.getByRole('button', { name: 'Copy draft' }));
  expect(await screen.findByRole('button', { name: 'Copied' })).toBeVisible();
  expect(writeText).toHaveBeenLastCalledWith(`${draft.title}\n\n<b>My list</b>`);
  expect(screen.queryByText('My list')).not.toBeInTheDocument();
});

it('omits facts already shown elsewhere and hides unavailable intelligence', async () => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce({ data: { status: 'unavailable' }, error: null });
  const { rerender, container } = render(<ObjectIntelligenceSection item={item} userId="owner" hiddenFactPaths={['recipe.name']} />);
  expect(await screen.findByText('Ingredients')).toBeVisible();
  expect(screen.queryByText('Name')).not.toBeInTheDocument();
  rerender(<ObjectIntelligenceSection item={{ id: 'empty' }} userId="owner" />);
  await waitFor(() => expect(container).toBeEmptyDOMElement());
});

it.each(['pending', 'unavailable'])('preserves and labels the previous draft when refreshed details are %s', async status => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult())
    .mockResolvedValueOnce({ data: null, error: { context: new Response(JSON.stringify({ error: 'source_changed' }), { status: 409 }) } })
    .mockResolvedValueOnce({ data: { status }, error: null });
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  expect(await screen.findByLabelText('Draft content')).toHaveValue(draft.content);
  fireEvent.click(screen.getByRole('button', { name: 'Create a recipe card' }));
  fireEvent.click(await screen.findByRole('button', { name: 'Refresh details' }));
  expect(await screen.findByText(/Current source details could not be verified/)).toBeVisible();
  expect(screen.getByLabelText('Draft content')).toHaveValue(draft.content);
});

it('shows the subscription path and prevents repeated draft requests after entitlement denial', async () => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValue({ data: null, error: { context: new Response(JSON.stringify({ error: 'subscription_required', message: 'Do not render this arbitrary text' }), { status: 403 }) } });
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Your trial has ended');
  expect(screen.getByRole('link', { name: 'Manage subscription' })).toHaveAttribute('href', '/settings');
  expect(screen.getByRole('button', { name: 'Create a shopping list' })).toBeDisabled();
  fireEvent.click(screen.getByRole('button', { name: 'Create a shopping list' }));
  expect(invoke).toHaveBeenCalledTimes(2);
  expect(screen.queryByText('Do not render this arbitrary text')).not.toBeInTheDocument();
});

it('rechecks source changes even when the stored intelligence envelope has not changed yet', async () => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce({ data: { status: 'pending' }, error: null });
  const { rerender } = render(<ObjectIntelligenceSection item={{ ...item, page_body: 'Old source' }} userId="owner" />);
  expect(await screen.findByText('Ingredients')).toBeVisible();
  rerender(<ObjectIntelligenceSection item={{ ...item, page_body: 'Changed source' }} userId="owner" />);
  expect(await screen.findByText(/More details are being gathered/)).toBeVisible();
  expect(screen.queryByText('Ingredients')).not.toBeInTheDocument();
  expect(invoke).toHaveBeenCalledTimes(2);
});

it.each([
  ['subscription_required', 403, 'Your trial has ended', 'Manage subscription', '/settings'],
  ['session_required', 401, 'Sign in again', 'Sign in', '/auth'],
] as const)('preserves edits and offers the correct recovery when saving fails with %s', async (code, status, message, link, href) => {
  invoke.mockResolvedValueOnce(ready()).mockResolvedValueOnce(draftResult());
  captureContent.mockRejectedValue(new CaptureError(code, status, 'Do not render this arbitrary server message'));
  render(<ObjectIntelligenceSection item={item} userId="owner" />);
  fireEvent.click(await screen.findByRole('button', { name: 'Create a shopping list' }));
  fireEvent.change(await screen.findByLabelText('Draft content'), { target: { value: 'My revised draft' } });
  fireEvent.click(screen.getByRole('button', { name: 'Save to Stash' }));
  expect(await screen.findByRole('alert')).toHaveTextContent(message);
  expect(screen.getByRole('link', { name: link })).toHaveAttribute('href', href);
  expect(screen.getByRole('button', { name: 'Save to Stash' })).toBeDisabled();
  fireEvent.click(screen.getByRole('button', { name: 'Save to Stash' }));
  expect(captureContent).toHaveBeenCalledTimes(1);
  expect(screen.getByLabelText('Draft content')).toHaveValue('My revised draft');
  expect(screen.queryByText(/arbitrary server message/)).not.toBeInTheDocument();
});
