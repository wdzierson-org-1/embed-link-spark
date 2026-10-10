import { fireEvent, render, screen } from '@testing-library/react';
import EditItemImageStage from './EditItemImageStage';

// The stage's full-size / full-screen cells carry tooltips; no provider is mounted here
vi.mock('@/components/ui/tooltip', () => ({
  TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipContent: () => null,
}));

it('reserves its full height before the picture arrives, showing the mosaic, then the picture', () => {
  render(<EditItemImageStage src="/cover.jpg" alt="Cover" />);
  const stage = screen.getByTestId('image-stage');
  expect(stage.className).toContain('h-[448px]');
  expect(screen.getByTestId('image-stage-mosaic')).toBeInTheDocument();
  const img = screen.getByAltText('Cover');
  expect(img.className).toContain('opacity-0');

  fireEvent.load(img);
  expect(stage.className).toContain('h-[448px]');
  expect(screen.queryByTestId('image-stage-mosaic')).not.toBeInTheDocument();
  expect(img.className).toContain('opacity-100');
});

it('shows its controls only once the picture is there', () => {
  render(<EditItemImageStage src="/cover.jpg" alt="Cover" controls={<button>Replace image</button>} />);
  expect(screen.queryByRole('button', { name: 'Replace image' })).not.toBeInTheDocument();
  fireEvent.load(screen.getByAltText('Cover'));
  expect(screen.getByRole('button', { name: 'Replace image' })).toBeInTheDocument();
});

it('takes the stage away when the picture fails to load', () => {
  render(<EditItemImageStage src="/gone.jpg" alt="Cover" />);
  fireEvent.error(screen.getByAltText('Cover'));
  expect(screen.queryByTestId('image-stage')).not.toBeInTheDocument();
});

it('starts over for a new picture', () => {
  const { rerender } = render(<EditItemImageStage src="/one.jpg" alt="Cover" />);
  fireEvent.load(screen.getByAltText('Cover'));
  rerender(<EditItemImageStage src="/two.jpg" alt="Cover" />);
  expect(screen.getByTestId('image-stage-mosaic')).toBeInTheDocument();
});
