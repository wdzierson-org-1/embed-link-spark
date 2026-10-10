import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import CitationLink from './CitationLink';

describe('CitationLink', () => {
  it('is an inline anchor, so a long title flows and sits left like the text around it', () => {
    render(
      <p>
        <CitationLink href="#item=abc" itemId="abc" onOpen={vi.fn()}>
          Chatbots are not the final interface: OpenAI’s Head of Design on what’s next
        </CitationLink>{' '}
        — interview saved 2026-08-26
      </p>,
    );
    const link = screen.getByRole('link', { name: /Chatbots are not the final interface/ });
    expect(link.tagName).toBe('A');
    expect(link).toHaveAttribute('href', '#item=abc');
    // No block or inline-block display: that is what centred titles before
    expect([...link.classList].some((c) => ['inline', 'inline-block', 'block', 'flex', 'text-center'].includes(c))).toBe(false);
  });

  it('opens the save on click instead of navigating to the hash', () => {
    const onOpen = vi.fn();
    render(
      <CitationLink href="#item=abc" itemId="abc" onOpen={onOpen}>
        A tale of two Agent Builders
      </CitationLink>,
    );
    const defaultAllowed = fireEvent.click(screen.getByRole('link'));
    expect(onOpen).toHaveBeenCalledWith('abc');
    expect(defaultAllowed).toBe(false);
  });
});
