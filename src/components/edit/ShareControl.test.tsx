import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { TooltipProvider } from '@/components/ui/tooltip';
import ShareControl from './ShareControl';

const writeText = vi.fn().mockResolvedValue(undefined);

beforeEach(() => {
  Object.assign(navigator, { clipboard: { writeText } });
  writeText.mockClear();
});

const renderControl = (shareToken: string | null, onChange = vi.fn().mockResolvedValue(undefined)) => {
  render(
    <TooltipProvider>
      <ShareControl shareToken={shareToken} onChange={onChange} />
    </TooltipProvider>,
  );
  return onChange;
};

it('mints a ten-character link on the first click, stores it, copies it and opens the window', async () => {
  const onChange = renderControl(null);
  fireEvent.click(screen.getByRole('button', { name: 'Share' }));
  await waitFor(() => expect(onChange).toHaveBeenCalledTimes(1));
  const updates = onChange.mock.calls[0][0];
  expect(updates.share_token).toMatch(/^[A-Za-z0-9]{10}$/);
  expect(typeof updates.shared_at).toBe('string');
  await waitFor(() => expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/s/${updates.share_token}`));
  expect(await screen.findByText(`${window.location.origin}/s/${updates.share_token}`)).toBeInTheDocument();
  expect(screen.getByRole('status')).toHaveTextContent('link copied');
});

it('when already shared, the cell wears the link and opens the window without re-copying', async () => {
  const onChange = renderControl('Xk3mN9pQ2a');
  fireEvent.click(screen.getByRole('button', { name: /shared/i }));
  expect(await screen.findByText(`${window.location.origin}/s/Xk3mN9pQ2a`)).toBeInTheDocument();
  expect(onChange).not.toHaveBeenCalled();
  expect(writeText).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Copy link' }));
  await waitFor(() => expect(writeText).toHaveBeenCalledWith(`${window.location.origin}/s/Xk3mN9pQ2a`));
});

it('stop sharing clears the token and closes the window', async () => {
  const onChange = renderControl('Xk3mN9pQ2a');
  fireEvent.click(screen.getByRole('button', { name: /shared/i }));
  fireEvent.click(await screen.findByRole('button', { name: 'Stop sharing' }));
  await waitFor(() => expect(onChange).toHaveBeenCalledWith({ share_token: null, shared_at: null }));
  await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop sharing' })).not.toBeInTheDocument());
});

it('says so when the link could not be stored', async () => {
  renderControl(null, vi.fn().mockRejectedValue(new Error('offline')));
  fireEvent.click(screen.getByRole('button', { name: 'Share' }));
  expect(await screen.findByText(/couldn't update the link/)).toBeInTheDocument();
  expect(writeText).not.toHaveBeenCalled();
});
