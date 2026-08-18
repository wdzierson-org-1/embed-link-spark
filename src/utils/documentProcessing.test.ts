import { describe, it, expect } from 'vitest';
import { isDocumentProcessing, isPdfDocument } from './documentProcessing';

const PPTX_MIME = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

describe('isPdfDocument', () => {
  it('accepts pdf mime and falls back to the file extension', () => {
    expect(isPdfDocument({ mime_type: 'application/pdf' })).toBe(true);
    expect(isPdfDocument({ mime_type: null, file_path: 'u/staging/1-a.PDF' })).toBe(true);
    expect(isPdfDocument({ mime_type: PPTX_MIME, file_path: 'u/staging/1-a.pptx' })).toBe(false);
    expect(isPdfDocument({})).toBe(false);
  });
});

describe('isDocumentProcessing', () => {
  it('marks a PDF without a summary as still processing', () => {
    expect(isDocumentProcessing({ type: 'document', mime_type: 'application/pdf' })).toBe(true);
    expect(isDocumentProcessing({ type: 'document', mime_type: 'application/pdf', summary: '' })).toBe(true);
  });

  it('marks a PDF with a summary as done', () => {
    expect(
      isDocumentProcessing({ type: 'document', mime_type: 'application/pdf', summary: 'A summary.' })
    ).toBe(false);
  });

  it('never marks non-PDF documents as processing — there is no extractor for them', () => {
    // Regression: a pptx with a null summary used to hang in "Extracting…"
    // forever and block its own edit sheet
    expect(isDocumentProcessing({ type: 'document', mime_type: PPTX_MIME })).toBe(false);
    expect(isDocumentProcessing({ type: 'document', mime_type: PPTX_MIME, summary: null })).toBe(false);
    expect(isDocumentProcessing({ type: 'document' })).toBe(false);
  });

  it('ignores content: user notes must not affect processing state', () => {
    const finished = { type: 'document', mime_type: 'application/pdf', content: undefined, summary: 'Done.' };
    const extracting = { type: 'document', mime_type: 'application/pdf', content: 'long user notes '.repeat(20) };
    expect(isDocumentProcessing(finished)).toBe(false);
    expect(isDocumentProcessing(extracting)).toBe(true);
  });

  it('never marks non-document types as processing', () => {
    for (const type of ['text', 'link', 'image', 'audio', 'video', 'collection', undefined]) {
      expect(isDocumentProcessing({ type, mime_type: 'application/pdf' })).toBe(false);
    }
  });
});
