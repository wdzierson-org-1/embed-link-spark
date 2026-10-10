import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import EditItemDescriptionSection from './EditItemDescriptionSection';

const LONG =
  '2,322 likes, 15 comments - therohanreport on September 16, 2026: "The future of design may look a lot like this scene from Denis Villeneuve’s Blade Runner 2049. Here, a memory designer is busy creating a detailed memory, each artifact generated on the fly."';

describe('EditItemDescriptionSection', () => {
  it('rests as a three-line clamped block, not an input', () => {
    render(<EditItemDescriptionSection description={LONG} onDescriptionChange={vi.fn()} onSave={vi.fn()} />);
    const rest = screen.getByRole('button', { name: /edit description/i });
    expect(rest).toHaveTextContent(LONG);
    expect(rest.className).toContain('line-clamp-3');
    // line-clamp needs display:-webkit-box; a display utility would override it
    expect([...rest.classList].some((c) => ['block', 'flex', 'inline-block', 'grid'].includes(c))).toBe(false);
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  });

  it('invites a description when there is none', () => {
    render(<EditItemDescriptionSection description="" onDescriptionChange={vi.fn()} onSave={vi.fn()} />);
    expect(screen.getByRole('button', { name: /edit description/i })).toHaveTextContent('Add a description…');
  });

  it('opens the full description in a focused textarea on click', () => {
    render(<EditItemDescriptionSection description={LONG} onDescriptionChange={vi.fn()} onSave={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /edit description/i }));
    const box = screen.getByRole('textbox', { name: /description/i }) as HTMLTextAreaElement;
    expect(box.value).toBe(LONG);
    expect(box).toHaveFocus();
    expect(box.className).not.toContain('line-clamp-3');
    expect(screen.queryByRole('button', { name: /edit description/i })).not.toBeInTheDocument();
  });

  it('saves the trimmed description on blur and returns to the clamped view', () => {
    const onDescriptionChange = vi.fn();
    const onSave = vi.fn().mockResolvedValue(undefined);
    const { rerender } = render(
      <EditItemDescriptionSection description={LONG} onDescriptionChange={onDescriptionChange} onSave={onSave} />,
    );
    fireEvent.click(screen.getByRole('button', { name: /edit description/i }));
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '  Two lines\nof description  ' } });
    expect(onDescriptionChange).toHaveBeenCalledWith('  Two lines\nof description  ');
    rerender(
      <EditItemDescriptionSection description={'  Two lines\nof description  '} onDescriptionChange={onDescriptionChange} onSave={onSave} />,
    );
    fireEvent.blur(screen.getByRole('textbox'));
    expect(onSave).toHaveBeenCalledWith('Two lines\nof description');
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /edit description/i })).toBeInTheDocument();
  });

  it('keeps Enter as a new line: a description may run to several', () => {
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<EditItemDescriptionSection description="One" onDescriptionChange={vi.fn()} onSave={onSave} />);
    fireEvent.click(screen.getByRole('button', { name: /edit description/i }));
    const allowed = fireEvent.keyDown(screen.getByRole('textbox'), { key: 'Enter' });
    expect(allowed).toBe(true);
    expect(onSave).not.toHaveBeenCalled();
    expect(screen.getByRole('textbox')).toBeInTheDocument();
  });
});
