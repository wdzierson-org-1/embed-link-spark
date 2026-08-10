import { describe, it, expect } from 'vitest';
import { isDocumentProcessing } from './documentProcessing';

describe('isDocumentProcessing', () => {
  it('marks a document without a summary as still processing', () => {
    expect(isDocumentProcessing({ type: 'document' })).toBe(true);
    expect(isDocumentProcessing({ type: 'document', summary: '' })).toBe(true);
  });

  it('marks a document with a summary as done', () => {
    expect(isDocumentProcessing({ type: 'document', summary: 'A summary.' })).toBe(false);
  });

  it('ignores content: user notes must not affect processing state', () => {
    // content is the user's own notes (empty for fresh uploads); extraction
    // completion is signalled by summary, written by extract-pdf-text
    const finished: { type: string; content?: string; summary?: string } = {
      type: 'document',
      content: undefined,
      summary: 'Done.',
    };
    const extracting: { type: string; content?: string; summary?: string } = {
      type: 'document',
      content: 'long user notes '.repeat(20),
    };
    expect(isDocumentProcessing(finished)).toBe(false);
    expect(isDocumentProcessing(extracting)).toBe(true);
  });

  it('never marks non-document types as processing', () => {
    for (const type of ['text', 'link', 'image', 'audio', 'video', 'collection', undefined]) {
      expect(isDocumentProcessing({ type })).toBe(false);
    }
  });
});
