import { looksLikeNovelJson, plainTitleFromContent, sanitizeItemTitle } from './itemTitle';

const richDoc = JSON.stringify({
  type: 'doc',
  content: [
    {
      type: 'taskList',
      content: [
        {
          type: 'taskItem',
          attrs: { checked: false },
          content: [{ type: 'paragraph', content: [{ type: 'text', text: 'this is list item 1' }] }],
        },
      ],
    },
    { type: 'heading', attrs: { level: 1 }, content: [{ type: 'text', text: 'This is heading 1' }] },
  ],
});

describe('looksLikeNovelJson', () => {
  it('detects serialized editor docs', () => {
    expect(looksLikeNovelJson(richDoc)).toBe(true);
    expect(looksLikeNovelJson('  {"type":"doc","content":[]}')).toBe(true);
  });

  it('passes normal titles', () => {
    expect(looksLikeNovelJson('Groceries for the week')).toBe(false);
    expect(looksLikeNovelJson('')).toBe(false);
    expect(looksLikeNovelJson(null)).toBe(false);
  });
});

describe('plainTitleFromContent', () => {
  it('uses the first line of plain text', () => {
    expect(plainTitleFromContent('first line\nsecond line')).toBe('first line');
  });

  it('extracts text from novel JSON', () => {
    expect(plainTitleFromContent(richDoc)).toBe('this is list item 1');
  });

  it('truncates long lines', () => {
    const long = 'x'.repeat(80);
    const title = plainTitleFromContent(long);
    expect(title.length).toBe(60);
    expect(title.endsWith('...')).toBe(true);
  });
});

describe('sanitizeItemTitle', () => {
  it('keeps a good candidate', () => {
    expect(sanitizeItemTitle('React Bits pricing', richDoc, 'Collection')).toBe('React Bits pricing');
  });

  it('replaces leaked editor markup with content-derived text', () => {
    expect(sanitizeItemTitle(richDoc, richDoc, 'Collection')).toBe('this is list item 1');
  });

  it('falls back when there is no usable text', () => {
    expect(sanitizeItemTitle(undefined, '', 'Collection')).toBe('Collection');
  });
});
