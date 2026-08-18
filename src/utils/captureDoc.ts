import { type JSONContent } from 'novel';

/**
 * Helpers for working with the capture panel's rich editor document.
 *
 * The capture box accepts anything from a one-line note to a full rich doc
 * (task lists, headings, inline images). At submit time we decide whether the
 * note can be stored as plain text (parity with the old textarea) or needs to
 * be persisted as Novel JSON — the same format the edit panel's notes tab
 * already writes to items.content.
 */

const INLINE_TEXT_TYPES = new Set(['text', 'hardBreak']);
const BLOCK_JOIN_TYPES = new Set([
  'doc',
  'bulletList',
  'orderedList',
  'taskList',
  'blockquote',
  'listItem',
  'taskItem',
]);
/** Leaf nodes that carry meaning without any text (keep the doc "non-empty") */
const CONTENT_LEAF_TYPES = new Set(['image', 'horizontalRule']);

/** Flatten a Novel/Tiptap doc to plain text. Blocks join with newlines. */
export const docToPlainText = (node: JSONContent | null | undefined): string => {
  if (!node) return '';
  if (node.type === 'text') return node.text ?? '';
  if (node.type === 'hardBreak') return '\n';

  const children = node.content ?? [];
  if (children.length === 0) return '';

  const parts = children.map(docToPlainText);
  if (BLOCK_JOIN_TYPES.has(node.type ?? '')) {
    return parts.filter((part) => part.length > 0).join('\n');
  }
  return parts.join('');
};

/** True when the doc has no text and no meaningful leaf nodes (images, rules). */
export const docIsEmpty = (node: JSONContent | null | undefined): boolean => {
  if (!node) return true;
  if (docToPlainText(node).trim().length > 0) return false;

  let hasLeaf = false;
  const walk = (current: JSONContent) => {
    if (hasLeaf) return;
    if (CONTENT_LEAF_TYPES.has(current.type ?? '')) {
      hasLeaf = true;
      return;
    }
    current.content?.forEach(walk);
  };
  walk(node);
  return !hasLeaf;
};

/**
 * True when the doc is just unformatted paragraphs (no marks, no lists,
 * headings, images…) and can round-trip through a plain string.
 */
export const docIsPlainText = (node: JSONContent | null | undefined): boolean => {
  if (!node?.content) return true;

  const inlineIsPlain = (inline: JSONContent): boolean => {
    if (!INLINE_TEXT_TYPES.has(inline.type ?? '')) return false;
    if (inline.marks && inline.marks.length > 0) return false;
    return true;
  };

  return node.content.every((block) => {
    if (block.type !== 'paragraph') return false;
    return (block.content ?? []).every(inlineIsPlain);
  });
};

/**
 * Remove URL strings from every text node (they live on link chips instead, so
 * keeping them in the note would save the URL twice). Text nodes that end up
 * empty are dropped, as are leading/trailing paragraphs left with nothing in
 * them.
 */
export const stripUrlsFromDoc = (node: JSONContent, urls: string[]): JSONContent => {
  if (urls.length === 0) return node;

  const stripFromNode = (current: JSONContent): JSONContent | null => {
    if (current.type === 'text') {
      const stripped = urls.reduce(
        (text, url) => text.split(url).join(''),
        current.text ?? ''
      );
      if (stripped.length === 0) return null;
      return { ...current, text: stripped };
    }

    if (!current.content) return current;

    const children = current.content
      .map(stripFromNode)
      .filter((child): child is JSONContent => child !== null);
    return { ...current, content: children };
  };

  const stripped = stripFromNode(node) ?? { type: 'doc', content: [] };
  const content = [...(stripped.content ?? [])];

  const paragraphIsBlank = (block: JSONContent) =>
    block.type === 'paragraph' && docToPlainText(block).trim() === '' && docIsEmpty(block);

  while (content.length > 0 && paragraphIsBlank(content[0])) content.shift();
  while (content.length > 0 && paragraphIsBlank(content[content.length - 1])) content.pop();

  return { ...stripped, content };
};

