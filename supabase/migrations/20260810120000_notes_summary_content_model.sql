-- Notes & Summary content model
--
-- Field semantics after this migration:
--   content    → the user's own notes (rich editor)
--   page_body  → original captured content (scraped page, extracted document
--                text, audio/video transcript, image OCR)
--   summary    → full AI summary (links and documents; images and media keep
--                their summary in description)
--   description → short card description

ALTER TABLE public.items ADD COLUMN IF NOT EXISTS summary text;

-- Audio/video transcripts were stored in content; move them to page_body so
-- the Notes editor starts empty and the transcript survives as source content.
UPDATE public.items
SET page_body = content,
    content = NULL
WHERE type IN ('audio', 'video')
  AND content IS NOT NULL
  AND page_body IS NULL;

-- Documents stored the LLM extraction/analysis in content (duplicated in
-- page_body once extract-pdf-text also began writing page_body). Free content
-- up for user notes; keep the extraction reachable via page_body.
UPDATE public.items
SET page_body = COALESCE(page_body, content),
    content = NULL
WHERE type = 'document'
  AND content IS NOT NULL
  AND (page_body IS NULL OR content = page_body);

-- Legacy extracted documents have a content-derived description; seed summary
-- from it so the Summary tab isn't empty and the "still processing" marker
-- (summary IS NULL) doesn't fire for already-processed documents.
UPDATE public.items
SET summary = description
WHERE type = 'document'
  AND summary IS NULL
  AND page_body IS NOT NULL
  AND description IS NOT NULL;
