import { fireEvent, render, screen } from '@testing-library/react';
import { StageFullProvider, StageRoot, useStage, useStageRef } from './StageFull';

vi.mock('@/components/ui/tooltip', () => ({
  TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipContent: () => null,
}));

const Probe = () => {
  const ref = useStageRef();
  const { full, controls, bar, rootClass } = useStage(ref, 'picture');
  return (
    <StageRoot ref={ref} className={rootClass} data-testid="stage">
      {bar}
      <div key="media" data-testid="media">{full ? 'full' : 'rest'}</div>
      {controls}
    </StageRoot>
  );
};

it('rests on the dotted stage; full size fills the page, names itself in a bar, and Esc returns', () => {
  render(<Probe />);
  const stage = screen.getByTestId('stage');
  expect(stage.className).toContain('v2-dots');
  const media = screen.getByTestId('media');
  fireEvent.click(screen.getByRole('button', { name: 'Full size' }));
  expect(stage.className).toContain('fixed inset-0');
  expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('picture');
  // The media element is the same node: a playing video keeps playing
  expect(screen.getByTestId('media')).toBe(media);
  fireEvent.keyDown(window, { key: 'Escape' });
  expect(stage.className).toContain('v2-dots');
  expect(screen.queryByRole('heading', { level: 2 })).not.toBeInTheDocument();
});

it('inside the panel the stage sits over the sheet and tells the sheet to go wide', () => {
  const onChange = vi.fn();
  render(
    <StageFullProvider onChange={onChange}>
      <Probe />
    </StageFullProvider>,
  );
  fireEvent.click(screen.getByRole('button', { name: 'Full size' }));
  expect(screen.getByTestId('stage').className).toContain('absolute inset-0');
  expect(onChange).toHaveBeenLastCalledWith(true);
  fireEvent.click(screen.getByRole('button', { name: 'Minimize' }));
  expect(onChange).toHaveBeenLastCalledWith(false);
});

it('Esc in full size never reaches the sheet (which would close on it)', () => {
  const heard = vi.fn();
  document.addEventListener('keydown', heard, true);
  render(<Probe />);
  fireEvent.click(screen.getByRole('button', { name: 'Full size' }));
  fireEvent.keyDown(document.body, { key: 'Escape' });
  expect(heard).not.toHaveBeenCalled();
  document.removeEventListener('keydown', heard, true);
});
