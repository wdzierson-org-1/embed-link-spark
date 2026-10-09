import { fireEvent, render, screen } from '@testing-library/react';
import LibraryToolbar from './LibraryToolbar';

const base = { searchQuery: '', onSearchChange: vi.fn(), itemCount: 59, tags: [], selectedTags: [], onTagFilterChange: vi.fn() };

it('says how many saves there are, with no tabs, until something is pinned', () => {
  render(<LibraryToolbar {...base} />);
  expect(screen.getByText('59 saves')).toBeInTheDocument();
  expect(screen.queryByRole('tablist', { name: 'Library view' })).not.toBeInTheDocument();
});

it('shows all | pinned tabs with counts once something is pinned, and switches the view', () => {
  const onViewChange = vi.fn();
  render(<LibraryToolbar {...base} pinnedCount={3} view="all" onViewChange={onViewChange} />);
  const tabs = screen.getByRole('tablist', { name: 'Library view' });
  expect(tabs).toHaveTextContent('all · 59');
  expect(screen.getByRole('tab', { name: 'all · 59' })).toHaveAttribute('aria-selected', 'true');
  fireEvent.click(screen.getByRole('tab', { name: 'pinned · 3' }));
  expect(onViewChange).toHaveBeenCalledWith('pinned');
});

it('still says what Stash is reading beside the tabs', () => {
  render(<LibraryToolbar {...base} pinnedCount={1} view="pinned" readingCount={2} />);
  expect(screen.getByRole('tab', { name: 'pinned · 1' })).toHaveAttribute('aria-selected', 'true');
  expect(screen.getByText('reading 2…')).toBeInTheDocument();
});
