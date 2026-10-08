import { fireEvent, render, screen } from '@testing-library/react';
import { VideoPosterHero } from './CardHero';

beforeEach(() => {
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue(undefined);
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined);
});
afterEach(() => vi.restoreAllMocks());

const video = () => document.querySelector('video') as HTMLVideoElement;

it('rests on its first frame with a play button and the duration, and no full-screen lightbox', () => {
  render(<VideoPosterHero src="/clip.mp4" durationS={45} />);
  expect(screen.getByRole('button', { name: 'Play' })).toBeInTheDocument();
  expect(screen.getByText('0:45')).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: /expand/i })).not.toBeInTheDocument();
  expect(video().controls).toBe(false);
});

it('plays in place in the card, with a close that stops it and brings the poster back', () => {
  render(<VideoPosterHero src="/clip.mp4" durationS={45} />);
  fireEvent.click(screen.getByRole('button', { name: 'Play' }));
  expect(HTMLMediaElement.prototype.play).toHaveBeenCalled();
  expect(video().controls).toBe(true);

  fireEvent.click(screen.getByRole('button', { name: 'Close video' }));
  expect(HTMLMediaElement.prototype.pause).toHaveBeenCalled();
  expect(video().controls).toBe(false);
  expect(screen.queryByRole('button', { name: 'Close video' })).not.toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Play' })).toHaveFocus();
});

it('keeps its clicks to itself, so the card behind it never opens', () => {
  const onCard = vi.fn();
  render(
    <div onClick={onCard}>
      <VideoPosterHero src="/clip.mp4" />
    </div>,
  );
  fireEvent.click(screen.getByRole('button', { name: 'Play' }));
  fireEvent.click(screen.getByRole('button', { name: 'Close video' }));
  expect(onCard).not.toHaveBeenCalled();
});
