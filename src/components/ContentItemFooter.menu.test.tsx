import { fireEvent, render, screen, within } from '@testing-library/react';
import ContentItemFooter from './ContentItemFooter';

/**
 * The card menu (DESIGN-v2 §12.3): pin, share to feed, remind, and delete behind a confirmation.
 * "Report a problem" is gone.
 */
const { mockSaveItem } = vi.hoisted(() => ({ mockSaveItem: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { storage: { from: () => ({ getPublicUrl: () => ({ data: { publicUrl: '' } }) }) } } }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: vi.fn() }) }));
vi.mock('@/utils/itemOperations', () => ({ saveItem: mockSaveItem }));
vi.mock('@/components/AnimatedCommentCount', () => ({ AnimatedCommentCount: () => null }));

const item = { id: 'item-1', type: 'link' as const, title: 'A saved page', url: 'https://example.com/a', created_at: '2026-10-01T00:00:00Z', user_id: 'owner-1' };

// Radix opens its menu on pointerdown or Enter, never on a synthetic click; jsdom can drive the key
const openMenu = () => fireEvent.keyDown(screen.getByRole('button', { name: 'Card menu' }), { key: 'Enter' });

it('offers pin, share to feed, resurface and delete; never "report a problem" or "remind"', () => {
  render(<ContentItemFooter item={item} onDeleteItem={vi.fn()} onEditItem={vi.fn()} onTogglePrivacy={vi.fn()} onTogglePin={vi.fn()} />);
  openMenu();
  const menu = screen.getByRole('menu');
  expect(within(menu).getByRole('menuitem', { name: 'Pin this' })).toBeInTheDocument();
  expect(within(menu).getByRole('menuitem', { name: 'Share to feed' })).toBeInTheDocument();
  expect(within(menu).getByRole('menuitem', { name: 'Resurface in…' })).toBeInTheDocument();
  expect(within(menu).getByRole('menuitem', { name: 'Delete this' })).toBeInTheDocument();
  expect(within(menu).queryByRole('menuitem', { name: /report a problem|remind/i })).not.toBeInTheDocument();
});

it('names the resurfacing choices as spans of time, and offers to stop once one is set', () => {
  render(<ContentItemFooter item={{ ...item, remind_at: '2099-01-01T00:00:00Z' }} onDeleteItem={vi.fn()} onEditItem={vi.fn()} />);
  openMenu();
  expect(screen.getByRole('menuitem', { name: "Don't resurface" })).toBeInTheDocument();
  fireEvent.keyDown(screen.getByRole('menuitem', { name: 'Resurface in…' }), { key: 'ArrowRight' });
  expect(screen.getByRole('menuitem', { name: '1 day' })).toBeInTheDocument();
  expect(screen.getByRole('menuitem', { name: '3 days' })).toBeInTheDocument();
});

it('reads the item’s state: Unpin and Unshare from feed', () => {
  render(<ContentItemFooter item={{ ...item, pinned_at: '2026-10-09T00:00:00Z', is_public: true }} onDeleteItem={vi.fn()} onEditItem={vi.fn()} onTogglePrivacy={vi.fn()} onTogglePin={vi.fn()} />);
  openMenu();
  expect(screen.getByRole('menuitem', { name: 'Unpin' })).toBeInTheDocument();
  expect(screen.getByRole('menuitem', { name: 'Unshare from feed' })).toBeInTheDocument();
});

it('pin and share hand the item to their handlers', () => {
  const onTogglePin = vi.fn();
  const onTogglePrivacy = vi.fn();
  render(<ContentItemFooter item={item} onDeleteItem={vi.fn()} onEditItem={vi.fn()} onTogglePrivacy={onTogglePrivacy} onTogglePin={onTogglePin} />);
  openMenu();
  fireEvent.click(screen.getByRole('menuitem', { name: 'Pin this' }));
  expect(onTogglePin).toHaveBeenCalledWith(item);
  openMenu();
  fireEvent.click(screen.getByRole('menuitem', { name: 'Share to feed' }));
  expect(onTogglePrivacy).toHaveBeenCalledWith(item);
});

it('deletes only after the confirmation, which names the item', () => {
  const onDeleteItem = vi.fn();
  render(<ContentItemFooter item={item} onDeleteItem={onDeleteItem} onEditItem={vi.fn()} />);
  openMenu();
  fireEvent.click(screen.getByRole('menuitem', { name: 'Delete this' }));
  const dialog = screen.getByRole('alertdialog');
  expect(dialog).toHaveTextContent('Delete this item?');
  expect(dialog).toHaveTextContent('"A saved page" and everything Stash knows about it will be removed.');
  expect(onDeleteItem).not.toHaveBeenCalled();
  fireEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));
  expect(onDeleteItem).not.toHaveBeenCalled();
  openMenu();
  fireEvent.click(screen.getByRole('menuitem', { name: 'Delete this' }));
  fireEvent.click(within(screen.getByRole('alertdialog')).getByRole('button', { name: 'Delete' }));
  expect(onDeleteItem).toHaveBeenCalledWith('item-1');
});

it('on a public feed, a visitor gets no owner actions', () => {
  render(<ContentItemFooter item={item} onDeleteItem={vi.fn()} onEditItem={vi.fn()} isPublicView currentUserId="someone-else" onCommentClick={vi.fn()} onTogglePin={vi.fn()} />);
  openMenu();
  const menu = screen.getByRole('menu');
  expect(within(menu).getByRole('menuitem', { name: 'Comments' })).toBeInTheDocument();
  expect(within(menu).queryByRole('menuitem', { name: /pin|share|delete|resurface/i })).not.toBeInTheDocument();
});
