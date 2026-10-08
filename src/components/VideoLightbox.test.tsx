import { fireEvent, render, screen } from '@testing-library/react';
import VideoLightbox from './VideoLightbox';

beforeEach(() => {
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue(undefined);
});
afterEach(() => vi.restoreAllMocks());

it('opens over the page, outside the card that asked for it, so a card’s hover lift can’t trap it', () => {
  const { container } = render(
    <div style={{ transform: 'translate(-2px, -2px)' }}>
      <VideoLightbox src="/clip.mp4" fileName="clip.mp4" isOpen onClose={vi.fn()} />
    </div>,
  );
  const dialog = screen.getByRole('dialog', { name: 'clip.mp4' });
  expect(container.contains(dialog)).toBe(false);
  expect(dialog.parentElement).toBe(document.body);
});

it('closes from its button and from Escape', () => {
  const onClose = vi.fn();
  render(<VideoLightbox src="/clip.mp4" fileName="clip.mp4" isOpen onClose={onClose} />);
  fireEvent.click(screen.getByRole('button', { name: 'Close video' }));
  fireEvent.keyDown(window, { key: 'Escape' });
  expect(onClose).toHaveBeenCalledTimes(2);
});

it('renders nothing while closed', () => {
  render(<VideoLightbox src="/clip.mp4" fileName="clip.mp4" isOpen={false} onClose={vi.fn()} />);
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
});
