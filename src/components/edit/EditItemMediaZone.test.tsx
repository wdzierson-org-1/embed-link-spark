import { render, screen } from '@testing-library/react';
import EditItemMediaZone from './EditItemMediaZone';

// The stage's full-size / full-screen cells carry tooltips; no provider is mounted here
vi.mock('@/components/ui/tooltip', () => ({
  TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipContent: () => null,
}));

const SRC = 'https://example.supabase.co/storage/v1/object/public/stash-media/u/clip.mp4';

it('shows a video as a video: playable on the stage, with the original to download', () => {
  render(<EditItemMediaZone item={{ id: 'v', type: 'video', attributes: { media: { duration_s: 45 } } }} src={SRC} title="muse-pitch-video.mp4" />);
  const video = screen.getByLabelText('Video: muse-pitch-video.mp4') as HTMLVideoElement;
  expect(video.tagName).toBe('VIDEO');
  expect(video).toHaveAttribute('src', SRC);
  expect(video.controls).toBe(true);
  expect(screen.queryByRole('button', { name: 'Playback speed' })).not.toBeInTheDocument();
  expect(screen.getByRole('link', { name: /download original/i })).toHaveAttribute('href', SRC);
});

it('keeps the player strip for a recording or a voice note', () => {
  render(<EditItemMediaZone item={{ id: 'a', type: 'audio', attributes: { media: { kind: 'voice_note', duration_s: 3 } } }} src={SRC} title="Voice note" />);
  expect(document.querySelector('video')).toBeNull();
  expect(screen.getByRole('button', { name: 'Play' })).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Playback speed' })).toBeInTheDocument();
});
