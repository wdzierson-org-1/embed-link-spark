import { act, renderHook } from '@testing-library/react';
import { useEditItemState } from './useEditItemState';

/**
 * A card opened while Stash is still reading it: the panel adopts the title and description as
 * they land, unless the person has already typed their own.
 */
const pending = { id: 'item-1', title: '', description: '' };
const named = { id: 'item-1', title: 'Our Locations', description: 'Sollis Health locations across major U.S. cities.' };

it('adopts the title and description that land while the sheet is open', () => {
  const { result, rerender } = renderHook(({ item }) => useEditItemState({ open: true, item }), { initialProps: { item: pending } });
  expect(result.current.title).toBe('');
  rerender({ item: named });
  expect(result.current.title).toBe('Our Locations');
  expect(result.current.description).toBe('Sollis Health locations across major U.S. cities.');
  expect(result.current.titleRef.current).toBe('Our Locations');
});

it('keeps what the person typed when a value lands for the same field', () => {
  const { result, rerender } = renderHook(({ item }) => useEditItemState({ open: true, item }), { initialProps: { item: pending } });
  act(() => {
    result.current.titleRef.current = 'My own title';
    result.current.setTitle('My own title');
  });
  rerender({ item: named });
  expect(result.current.title).toBe('My own title');
  // The description, untouched, still fills in
  expect(result.current.description).toBe('Sollis Health locations across major U.S. cities.');
});

it('decodes entities the way the first load does', () => {
  const { result, rerender } = renderHook(({ item }) => useEditItemState({ open: true, item }), { initialProps: { item: pending } });
  rerender({ item: { ...named, title: 'Tom &amp; Jerry' } });
  expect(result.current.title).toBe('Tom & Jerry');
});
