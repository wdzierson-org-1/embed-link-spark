import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import CardInlineNote from './CardInlineNote';

const { update, single, refresh } = vi.hoisted(() => ({ update: vi.fn(), single: vi.fn(), refresh: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: () => ({ update: (value: unknown) => { update(value); return { eq: () => ({ select: () => ({ single }) }) }; } }) },
}));
vi.mock('@/utils/itemOperations', () => ({ scheduleEmbeddingRefresh: refresh }));

const rich = JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Keep this context', marks: [{ type: 'bold' }] }] }] });

beforeEach(() => { vi.clearAllMocks(); single.mockResolvedValue({ data: { id: 'one' }, error: null }); });

it('preserves rich marks and Ctrl+Enter line breaks when Enter saves the shared content', async () => {
  const onSaved = vi.fn();
  render(<CardInlineNote item={{ id: 'one', content: rich }} onSaved={onSaved} />);
  fireEvent.click(screen.getByRole('button', { name: 'Edit note' }));
  const editor = await screen.findByRole('textbox', { name: 'Card note' });
  fireEvent.keyDown(editor, { key: 'Enter', ctrlKey: true });
  expect(update).not.toHaveBeenCalled();
  await waitFor(() => expect(editor.querySelector('br')).not.toBeNull());
  fireEvent.keyDown(editor, { key: 'Enter' });
  await waitFor(() => expect(onSaved).toHaveBeenCalledOnce());
  const saved = JSON.parse(update.mock.calls[0][0].content);
  expect(JSON.stringify(saved)).toContain('"type":"bold"');
  expect(JSON.stringify(saved)).toContain('"type":"hardBreak"');
  expect(refresh).toHaveBeenCalledWith({ id: 'one' });
});

it('retains the editor and draft on a failed save, and allows retry', async () => {
  single.mockResolvedValueOnce({ error: new Error('offline') });
  render(<CardInlineNote item={{ id: 'one', content: rich }} />);
  fireEvent.click(screen.getByRole('button', { name: 'Edit note' }));
  const editor = await screen.findByRole('textbox', { name: 'Card note' });
  fireEvent.keyDown(editor, { key: 'Enter' });
  expect(await screen.findByRole('alert')).toHaveTextContent('Your changes are still here');
  expect(editor).toHaveTextContent('Keep this context');
  fireEvent.click(screen.getByRole('button', { name: 'Save' }));
  await waitFor(() => expect(screen.queryByRole('textbox')).not.toBeInTheDocument());
});

it('lets Escape cancel without writing and never offers editing in a public view', async () => {
  const { rerender } = render(<CardInlineNote item={{ id: 'one' }} />);
  fireEvent.click(screen.getByRole('button', { name: 'Add a note' }));
  fireEvent.keyDown(await screen.findByRole('textbox'), { key: 'Escape' });
  expect(update).not.toHaveBeenCalled();
  rerender(<CardInlineNote item={{ id: 'one', content: rich }} readOnly />);
  expect(screen.queryByRole('button')).not.toBeInTheDocument();
});

it('saves changed content on blur and acknowledges only a confirmed save', async () => {
  let finishSave!: (result: { data: { id: string }; error: null }) => void;
  single.mockReturnValueOnce(new Promise(resolve => { finishSave = resolve; }));
  render(<><CardInlineNote item={{ id: 'one', content: rich }} /><button>Outside</button></>);
  fireEvent.click(screen.getByRole('button', { name: 'Edit note' }));
  const editor = await screen.findByRole('textbox', { name: 'Card note' });
  await waitFor(() => expect(editor).toHaveFocus());
  expect(screen.queryByText(/Enter to save|for a new line/)).not.toBeInTheDocument();
  fireEvent.keyDown(editor, { key: 'Enter', ctrlKey: true });
  fireEvent.blur(editor, { relatedTarget: screen.getByRole('button', { name: 'Outside' }) });
  await waitFor(() => expect(single).toHaveBeenCalledOnce());
  expect(screen.queryByRole('status')).not.toBeInTheDocument();
  finishSave({ data: { id: 'one' }, error: null });
  expect(await screen.findByRole('status')).toHaveTextContent('Saved');
});

it('allows moving focus to Cancel without blur saving the draft', async () => {
  render(<CardInlineNote item={{ id: 'one', content: rich }} />);
  fireEvent.click(screen.getByRole('button', { name: 'Edit note' }));
  const editor = await screen.findByRole('textbox', { name: 'Card note' });
  await waitFor(() => expect(editor).toHaveFocus());
  fireEvent.keyDown(editor, { key: 'Enter', ctrlKey: true });
  const cancel = screen.getByRole('button', { name: 'Cancel' });
  fireEvent.blur(editor, { relatedTarget: cancel });
  fireEvent.click(cancel);
  expect(update).not.toHaveBeenCalled();
  expect(screen.queryByRole('status')).not.toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Edit note' })).toHaveFocus();
});

it('closes an unchanged note on blur without writing or claiming a save', async () => {
  render(<CardInlineNote item={{ id: 'one', content: rich }} />);
  fireEvent.click(screen.getByRole('button', { name: 'Edit note' }));
  const editor = await screen.findByRole('textbox', { name: 'Card note' });
  await waitFor(() => expect(editor).toHaveFocus());
  fireEvent.blur(editor);
  expect(update).not.toHaveBeenCalled();
  expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  expect(screen.queryByRole('status')).not.toBeInTheDocument();
});
