import { describe, expect, it } from 'vitest';
import { cn } from './utils';

describe('cn (tailwind-merge with the DESIGN-v2 scale)', () => {
  it('keeps a v2 font size beside a text colour', () => {
    expect(cn('font-pixel text-pixel', 'text-white')).toBe('font-pixel text-pixel text-white');
    expect(cn('text-object-title text-ink', 'text-muted-foreground')).toBe('text-object-title text-muted-foreground');
  });

  it('lets a later v2 size win over an earlier one', () => {
    expect(cn('text-sm', 'text-pixel')).toBe('text-pixel');
  });

  it('treats the v2 shadows and radius as their own groups', () => {
    expect(cn('shadow-lg', 'shadow-print')).toBe('shadow-print');
    expect(cn('rounded-2xl', 'rounded-object')).toBe('rounded-object');
  });
});
