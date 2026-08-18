import {
  docIsEmpty,
  docIsPlainText,
  docToPlainText,
  stripUrlsFromDoc,
} from './captureDoc';
import type { JSONContent } from 'novel';

const paragraph = (text: string): JSONContent => ({
  type: 'paragraph',
  content: text ? [{ type: 'text', text }] : [],
});

const doc = (...content: JSONContent[]): JSONContent => ({ type: 'doc', content });

describe('docToPlainText', () => {
  it('joins paragraphs with newlines', () => {
    expect(docToPlainText(doc(paragraph('one'), paragraph('two')))).toBe('one\ntwo');
  });

  it('converts hard breaks to newlines', () => {
    expect(
      docToPlainText(
        doc({
          type: 'paragraph',
          content: [
            { type: 'text', text: 'one' },
            { type: 'hardBreak' },
            { type: 'text', text: 'two' },
          ],
        })
      )
    ).toBe('one\ntwo');
  });

  it('collects text from nested list structures', () => {
    const taskList: JSONContent = {
      type: 'taskList',
      content: [
        {
          type: 'taskItem',
          attrs: { checked: false },
          content: [paragraph('buy milk')],
        },
        {
          type: 'taskItem',
          attrs: { checked: true },
          content: [paragraph('call mom')],
        },
      ],
    };
    expect(docToPlainText(doc(taskList))).toBe('buy milk\ncall mom');
  });
});

describe('docIsEmpty', () => {
  it('treats a blank doc as empty', () => {
    expect(docIsEmpty(doc(paragraph('')))).toBe(true);
  });

  it('treats whitespace-only text as empty', () => {
    expect(docIsEmpty(doc(paragraph('   ')))).toBe(true);
  });

  it('counts an image as content even with no text', () => {
    expect(
      docIsEmpty(doc({ type: 'image', attrs: { src: 'https://x/img.png' } }))
    ).toBe(false);
  });

  it('is non-empty with text', () => {
    expect(docIsEmpty(doc(paragraph('note')))).toBe(false);
  });
});

describe('docIsPlainText', () => {
  it('accepts unformatted paragraphs', () => {
    expect(docIsPlainText(doc(paragraph('one'), paragraph('two')))).toBe(true);
  });

  it('rejects marks like bold', () => {
    expect(
      docIsPlainText(
        doc({
          type: 'paragraph',
          content: [{ type: 'text', text: 'loud', marks: [{ type: 'bold' }] }],
        })
      )
    ).toBe(false);
  });

  it('rejects task lists and headings', () => {
    expect(docIsPlainText(doc({ type: 'taskList', content: [] }))).toBe(false);
    expect(
      docIsPlainText(doc({ type: 'heading', attrs: { level: 1 }, content: [] }))
    ).toBe(false);
  });
});

describe('stripUrlsFromDoc', () => {
  it('removes the URL text but keeps the note', () => {
    const stripped = stripUrlsFromDoc(
      doc(paragraph('great read https://example.com')),
      ['https://example.com']
    );
    expect(docToPlainText(stripped).trim()).toBe('great read');
  });

  it('drops paragraphs that only contained the URL', () => {
    const stripped = stripUrlsFromDoc(
      doc(paragraph('my note'), paragraph('https://example.com')),
      ['https://example.com']
    );
    expect(stripped.content).toHaveLength(1);
    expect(docToPlainText(stripped)).toBe('my note');
  });

  it('preserves rich structure around the removed URL', () => {
    const stripped = stripUrlsFromDoc(
      doc(
        {
          type: 'taskList',
          content: [
            {
              type: 'taskItem',
              attrs: { checked: false },
              content: [paragraph('read https://example.com later')],
            },
          ],
        }
      ),
      ['https://example.com']
    );
    expect(stripped.content?.[0].type).toBe('taskList');
    expect(docToPlainText(stripped)).toBe('read  later');
  });
});

