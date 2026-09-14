import { describe, expect, it } from 'vitest';
import { notesSnippet, plainNotes } from './notes';

const doc = (text: string) =>
  JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text }] }] });

describe('plainNotes', () => {
  it('returns empty for missing or blank content', () => {
    expect(plainNotes(null)).toBe('');
    expect(plainNotes(undefined)).toBe('');
    expect(plainNotes('   ')).toBe('');
  });

  it('extracts text from a Novel/TipTap JSON document', () => {
    expect(plainNotes(doc('potential investor for Stash'))).toBe('potential investor for Stash');
  });

  it('joins block nodes with newlines and keeps hard breaks', () => {
    const content = JSON.stringify({
      type: 'doc',
      content: [
        { type: 'heading', content: [{ type: 'text', text: 'Chicken' }] },
        { type: 'paragraph', content: [{ type: 'text', text: 'line one' }, { type: 'hardBreak' }, { type: 'text', text: 'line two' }] },
        { type: 'bulletList', content: [
          { type: 'listItem', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'olives' }] }] },
          { type: 'listItem', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'onion' }] }] },
        ] },
      ],
    });
    expect(plainNotes(content)).toBe('Chicken\nline one\nline two\nolives\nonion');
  });

  it('passes plain text through unchanged', () => {
    expect(plainNotes('Band my mom liked')).toBe('Band my mom liked');
    expect(plainNotes('Chicken and Potatoes\nIngredients:\n4 chicken legs')).toBe('Chicken and Potatoes\nIngredients:\n4 chicken legs');
  });

  it('strips tags from legacy HTML notes', () => {
    expect(plainNotes('<p>Call <b>Sally</b></p><p>tomorrow</p>')).toBe('Call Sally tomorrow');
  });

  it('never leaks JSON structure for malformed or non-doc JSON', () => {
    expect(plainNotes('{"type":"doc","content":[')).toBe('{"type":"doc","content":[');
    expect(plainNotes('{"foo":"bar"}')).toBe('{"foo":"bar"}');
  });
});

describe('notesSnippet', () => {
  it('collapses whitespace and caps length', () => {
    expect(notesSnippet(doc('  a   b\n\nc  '), 200)).toBe('a b c');
    expect(notesSnippet('x'.repeat(50), 10)).toBe('x'.repeat(10));
  });

  it('returns null when there is nothing to show', () => {
    expect(notesSnippet(null, 200)).toBeNull();
    expect(notesSnippet(doc('   '), 200)).toBeNull();
  });
});
