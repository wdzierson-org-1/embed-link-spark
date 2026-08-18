// Whether a document item's text extraction is still in flight.
//
// Only PDFs have an extraction pipeline (extract-pdf-text writes `summary` in
// the same update as `page_body`, so a missing summary is the "still
// extracting" signal). Office formats (pptx/docx/xlsx…) have no extractor yet
// — they must NEVER read as processing, or they hang in that state forever
// and block their own edit sheet. `content` holds only the user's own notes
// and says nothing about extraction — it is null for every fresh upload.

export const PDF_MIME = 'application/pdf';

export const isPdfDocument = (item: { mime_type?: string | null; file_path?: string | null }): boolean =>
  item.mime_type === PDF_MIME ||
  (!item.mime_type && Boolean(item.file_path?.toLowerCase().endsWith('.pdf')));

export const isDocumentProcessing = (item: {
  type?: string;
  summary?: string | null;
  mime_type?: string | null;
  file_path?: string | null;
}): boolean => item.type === 'document' && isPdfDocument(item) && !item.summary;
