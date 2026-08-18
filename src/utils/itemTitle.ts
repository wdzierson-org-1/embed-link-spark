import { extractPlainTextFromNovelContent } from '@/utils/contentExtractor';

/**
 * Title hygiene for saved items. Rich capture notes are stored as Novel JSON;
 * any path that derives a title from content (or echoes user text through an
 * AI prompt) must never let raw editor markup become the visible title.
 */

export const looksLikeNovelJson = (value: string | null | undefined): boolean =>
  Boolean(value && value.trim().startsWith('{"type":"doc"'));

/** First line of the human-readable text, truncated to title length */
export const plainTitleFromContent = (content: string, maxLength = 60): string => {
  const plain = extractPlainTextFromNovelContent(content) || content;
  const firstLine = plain.trim().split('\n')[0].trim();
  if (firstLine.length <= maxLength) return firstLine;
  return `${firstLine.slice(0, maxLength - 3)}...`;
};

/**
 * Use the candidate title unless it's missing or is leaked editor markup; in
 * that case fall back to a title derived from the content text.
 */
export const sanitizeItemTitle = (
  candidate: string | null | undefined,
  content: string | null | undefined,
  fallback: string
): string => {
  if (candidate && !looksLikeNovelJson(candidate)) return candidate;
  if (content) {
    const derived = plainTitleFromContent(content);
    if (derived) return derived;
  }
  return fallback;
};
