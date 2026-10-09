import { act, render, screen } from '@testing-library/react';
import KindTag, { ALL_DONE_MS, GAVE_UP_MS, KIND_HOLD_MS } from './KindTag';

// Reduced motion: the decrypt shows the kind at once, so the sequence can be read step by step
vi.mock('@/components/machine/motion', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/components/machine/motion')>()),
  prefersReducedMotion: () => true,
}));

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

const tag = () => document.querySelector('[data-stage]') as HTMLElement;

it('is the kind, hidden until the card is hovered, on a card that is not being read', () => {
  render(<KindTag kind="video" />);
  expect(screen.getByText('video')).toBeInTheDocument();
  expect(tag()).toHaveAttribute('data-stage', 'settled');
  expect(tag().className).toContain('opacity-0');
  expect(tag().className).toContain('group-hover:opacity-100');
});

it('is the machine’s status while Stash reads, then says all done, decrypts into the kind, and fades', () => {
  const { rerender } = render(<KindTag kind="video" phase="reading" busyLabel="transcribing" />);
  expect(screen.getByRole('status')).toHaveTextContent('transcribing…');
  expect(tag().className).not.toContain('opacity-0');

  rerender(<KindTag kind="video" phase="done" busyLabel="transcribing" />);
  expect(screen.getByRole('status')).toHaveTextContent(/✓\s*all done!/);

  act(() => vi.advanceTimersByTime(ALL_DONE_MS));
  expect(screen.getByText('video')).toBeInTheDocument();
  expect(tag()).toHaveAttribute('data-stage', 'revealing');
  expect(tag().className).not.toContain('opacity-0');

  act(() => vi.advanceTimersByTime(KIND_HOLD_MS));
  expect(tag()).toHaveAttribute('data-stage', 'settled');
  expect(tag().className).toContain('opacity-0');
});

it('says so when Stash gave up, holds it longer, then shows the kind', () => {
  const { rerender } = render(<KindTag kind="link" phase="reading" />);
  rerender(<KindTag kind="link" phase="gave-up" />);
  expect(screen.getByRole('status')).toHaveTextContent('some info unavailable');
  act(() => vi.advanceTimersByTime(GAVE_UP_MS - 1));
  expect(screen.getByText('some info unavailable')).toBeInTheDocument();
  act(() => vi.advanceTimersByTime(1));
  expect(screen.getByText('link')).toBeInTheDocument();
});

it('does not replay the closing sequence for a card that mounts already finished', () => {
  render(<KindTag kind="article" phase="done" />);
  expect(screen.queryByRole('status')).not.toBeInTheDocument();
  expect(tag()).toHaveAttribute('data-stage', 'settled');
});
