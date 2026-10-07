import { render, screen } from '@testing-library/react';
import { GLYPHS } from './glyphs';
import { StatusLine, Tag } from './Machine';
import { kindGlyph, kindLabel } from '@/components/cards/ItemTypeChip';
import ContentItemSkeleton from '@/components/ContentItemSkeleton';
import EditItemAutoSaveIndicator from '@/components/EditItemAutoSaveIndicator';

describe('pixel glyphs', () => {
  it('are all 14×14 bitmaps of ink and paper', () => {
    for (const [name, rows] of Object.entries(GLYPHS)) {
      expect(rows, name).toHaveLength(14);
      for (const row of rows) {
        expect(row, `${name}: ${row}`).toMatch(/^[#.]{14}$/);
      }
    }
  });
});

describe('kind labels and glyphs', () => {
  it('names each kind of save in the machine voice, lowercase', () => {
    expect(kindLabel({ type: 'text' })).toBe('note');
    expect(kindLabel({ type: 'audio', attributes: { media: { kind: 'voice_note' } } })).toBe('voice note');
    expect(kindLabel({ type: 'audio', attributes: { media: { duration_s: 1200 } } })).toBe('recording');
    expect(kindLabel({ type: 'image', title: 'Screenshot of a receipt' })).toBe('screenshot');
    expect(kindLabel({ type: 'image', title: 'A cat on a wall' })).toBe('photo');
    expect(kindLabel({ type: 'document', mime_type: 'application/pdf' })).toBe('pdf');
    expect(kindLabel({ type: 'link', attributes: { link: { flavor: 'social' } } })).toBe('post');
    expect(kindLabel({ type: 'link' })).toBe('link');
  });

  it('picks a placeholder glyph per kind, places by host', () => {
    expect(kindGlyph({ type: 'link', url: 'https://github.com/a/b', attributes: { link: { flavor: 'repo' } } })).toBe('repo');
    expect(kindGlyph({ type: 'link', url: 'https://maps.apple.com/?q=cafe' })).toBe('place');
    expect(kindGlyph({ type: 'link', url: 'https://example.com' })).toBe('page');
    expect(kindGlyph({ type: 'image' })).toBe('photo');
    expect(kindGlyph({ type: 'audio' })).toBe('voice');
  });
});

describe('machine voice pieces', () => {
  it('announces a busy status with its words, the cursor hidden from screen readers', () => {
    render(<StatusLine tone="busy">gathering more info…</StatusLine>);
    const status = screen.getByRole('status');
    expect(status).toHaveTextContent('gathering more info…');
    expect(status.querySelector('[aria-hidden]')).not.toBeNull();
  });

  it('marks a finished status with a check', () => {
    render(<StatusLine tone="done">filled in</StatusLine>);
    expect(screen.getByRole('status')).toHaveTextContent('✓filled in');
  });

  it('sets tags in the pixel face', () => {
    render(<Tag>repo</Tag>);
    expect(screen.getByText('repo').className).toContain('font-pixel');
  });
});

describe('a save on its way in', () => {
  it('says only that it is saving, never the old rotating guesses', () => {
    render(<ContentItemSkeleton type="audio" title="Processing audio..." />);
    expect(screen.getByRole('status')).toHaveTextContent('saving…');
    expect(screen.queryByText(/processing/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/transcribing|almost done/i)).not.toBeInTheDocument();
  });

  it('keeps a real title while it saves', () => {
    render(<ContentItemSkeleton type="link" title="How to remember more of what you read" />);
    expect(screen.getByText('How to remember more of what you read')).toBeInTheDocument();
  });
});

describe('the detail panel save line', () => {
  it('reports saving, saved and idle in the machine voice', () => {
    const { rerender } = render(<EditItemAutoSaveIndicator saveStatus="saving" />);
    expect(screen.getByRole('status')).toHaveTextContent('saving…');
    rerender(<EditItemAutoSaveIndicator saveStatus="saved" lastSaved={new Date(2026, 9, 6, 21, 41)} />);
    expect(screen.getByRole('status')).toHaveTextContent(/saved 9:41\s?pm/);
    rerender(<EditItemAutoSaveIndicator saveStatus="idle" />);
    expect(screen.getByText('changes save automatically')).toBeInTheDocument();
  });
});
