import { fireEvent, render, screen } from '@testing-library/react';
import EditItemDetailsDrawer from './EditItemDetailsDrawer';

vi.mock('@/components/EditItemLocationSection', () => ({ default: () => <div>location editor</div> }));

const link = (id: string) => ({
  id,
  type: 'link',
  url: 'https://www.theunwindai.com/p/generative-ui-is-the-new-frontend',
  created_at: '2026-08-09T15:49:31Z',
});

const toggle = () => screen.getByRole('button', { name: /details/i });

it('opens expanded, so the facts are visible without a tap', () => {
  render(<EditItemDetailsDrawer item={link('a')} onSaveAttributes={vi.fn()} />);
  expect(toggle()).toHaveAttribute('aria-expanded', 'true');
  expect(screen.getByText('theunwindai.com')).toBeVisible();
});

it('lists an original file for an upload, never for a link (its file is the stored cover)', () => {
  const { rerender } = render(
    <EditItemDetailsDrawer item={{ ...link('a'), file_path: 'user/previews/preview_1788662568357.jpg' }} />,
  );
  expect(screen.queryByText(/original file/i)).not.toBeInTheDocument();
  expect(screen.queryByText('preview_1788662568357.jpg')).not.toBeInTheDocument();
  rerender(
    <EditItemDetailsDrawer
      item={{ id: 'doc', type: 'document', file_path: 'user/files/q3-plan.pdf', mime_type: 'application/pdf', file_size: 120_000 }}
    />,
  );
  expect(screen.getByText(/original file/i)).toBeInTheDocument();
  expect(screen.getByText('q3-plan.pdf')).toBeInTheDocument();
});

it('collapses on a tap, and opens expanded again for the next item', () => {
  const { rerender } = render(<EditItemDetailsDrawer item={link('a')} onSaveAttributes={vi.fn()} />);
  fireEvent.click(toggle());
  expect(toggle()).toHaveAttribute('aria-expanded', 'false');
  rerender(<EditItemDetailsDrawer item={link('b')} onSaveAttributes={vi.fn()} />);
  expect(toggle()).toHaveAttribute('aria-expanded', 'true');
});
