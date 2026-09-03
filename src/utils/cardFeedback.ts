/**
 * Card feedback (ui-changes.md 2026-09-03): a lightweight beta-tester report
 * on a single card — which things look wrong, plus an optional note. Rows
 * land in `card_feedback` with a snapshot of what the card showed, so a
 * report stays readable after the item is re-enriched or deleted.
 *
 * Codes are the contract; every client sends these exact strings.
 */

export const CARD_FEEDBACK_ISSUES = [
  { code: 'image_crop', label: "Image is cropped badly or the subject isn't visible" },
  { code: 'image_wrong', label: 'Wrong or missing image' },
  { code: 'title', label: 'Title is messy or unhelpful' },
  { code: 'description', label: 'Description is messy or unhelpful' },
  { code: 'summary', label: 'Summary is wrong or unhelpful' },
  { code: 'type', label: 'Saved as the wrong kind of thing' },
  { code: 'other', label: 'Something else' },
] as const;

export type CardFeedbackIssue = (typeof CARD_FEEDBACK_ISSUES)[number]['code'];

// Type alias (not interface) so it gets the implicit index signature the
// generated `Json` insert type requires — same convention as itemAttributes.ts
export type CardFeedbackSnapshot = {
  type?: string;
  title?: string;
  description?: string;
  url?: string;
  file_path?: string;
  flavor?: string;
  has_summary: boolean;
};

/** Freeze the fields a reviewer needs to see what the card looked like */
export const buildCardFeedbackSnapshot = (item: {
  type?: string;
  title?: string;
  description?: string;
  url?: string;
  file_path?: string;
  summary?: string;
  attributes?: { link?: { flavor?: string } };
}): CardFeedbackSnapshot => ({
  type: item.type,
  title: item.title?.slice(0, 300),
  description: item.description?.slice(0, 500),
  url: item.url,
  file_path: item.file_path,
  flavor: item.attributes?.link?.flavor,
  has_summary: Boolean(item.summary && item.summary.trim().length > 0),
});
