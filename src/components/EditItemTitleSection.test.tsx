import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import EditItemTitleSection from './EditItemTitleSection';

const LONG = 'Elise Loehnen (Fissmer) on Instagram: "Comment HAMSTER and I’ll DM you a link to this month’s solo episode of PULLING THE THREAD."';

describe('EditItemTitleSection', () => {
  it('rests as a two-line clamped title, not an input', () => {
    render(<EditItemTitleSection title={LONG} onTitleChange={vi.fn()} onSave={vi.fn()} />);
    const rest = screen.getByRole('button', { name: /edit title/i });
    expect(rest).toHaveTextContent(LONG);
    expect(rest).toHaveAttribute('title', LONG);
    expect(rest.className).toContain('line-clamp-2');
    // line-clamp needs display:-webkit-box; a display utility would override it
    expect([...rest.classList].some((c) => ['block', 'flex', 'inline-block', 'grid'].includes(c))).toBe(false);
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  });

  it('shows "Untitled" at rest when there is no title', () => {
    render(<EditItemTitleSection title="" onTitleChange={vi.fn()} onSave={vi.fn()} />);
    expect(screen.getByRole('button', { name: /edit title/i })).toHaveTextContent('Untitled');
  });

  it('opens the full title in a focused textarea on click', () => {
    render(<EditItemTitleSection title={LONG} onTitleChange={vi.fn()} onSave={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /edit title/i }));
    const box = screen.getByRole('textbox', { name: /title/i }) as HTMLTextAreaElement;
    expect(box.value).toBe(LONG);
    expect(box).toHaveFocus();
    expect(box.className).not.toContain('line-clamp-2');
    expect(screen.queryByRole('button', { name: /edit title/i })).not.toBeInTheDocument();
  });

  it('saves the trimmed title on blur and returns to the clamped view', async () => {
    const onTitleChange = vi.fn();
    const onSave = vi.fn().mockResolvedValue(undefined);
    const { rerender } = render(<EditItemTitleSection title={LONG} onTitleChange={onTitleChange} onSave={onSave} />);
    fireEvent.click(screen.getByRole('button', { name: /edit title/i }));
    fireEvent.change(screen.getByRole('textbox'), { target: { value: '  New title  ' } });
    expect(onTitleChange).toHaveBeenCalledWith('  New title  ');
    rerender(<EditItemTitleSection title="  New title  " onTitleChange={onTitleChange} onSave={onSave} />);
    fireEvent.blur(screen.getByRole('textbox'));
    expect(onSave).toHaveBeenCalledWith('New title');
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /edit title/i })).toBeInTheDocument();
  });

  it('flattens pasted newlines and treats Enter as done', () => {
    const onTitleChange = vi.fn();
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<EditItemTitleSection title="One" onTitleChange={onTitleChange} onSave={onSave} />);
    fireEvent.click(screen.getByRole('button', { name: /edit title/i }));
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'One\ntwo' } });
    expect(onTitleChange).toHaveBeenCalledWith('One two');
    fireEvent.keyDown(screen.getByRole('textbox'), { key: 'Enter' });
    expect(onSave).toHaveBeenCalledWith('One');
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  });
});
