// Whether a document item's text extraction is still in flight.
//
// extract-pdf-text writes `summary` (falling back to the description) in the
// same update as `page_body`, so a missing summary is the one reliable
// "still extracting" signal. `content` holds only the user's own notes and
// says nothing about extraction — it is null for every fresh upload.
export const isDocumentProcessing = (item: {
  type?: string;
  summary?: string | null;
}): boolean => item.type === 'document' && !item.summary;
