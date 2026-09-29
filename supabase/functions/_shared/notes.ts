// supabase/functions/_shared/notes.ts
//
// The user's own words about an item live in `items.content` in one of three
// shapes: a Novel/TipTap JSON document (web + iOS editors), plain text (SMS,
// share sheet, older saves) or, rarely, legacy HTML. Every place that shows
// notes to a model — Ask Stash search results and get_item, the MCP tools —
// must render the words, never the JSON scaffolding. Mirrors the web's
// src/utils/contentExtractor.ts; keep the two in step.

interface DocNode {
  type?: string;
  text?: string;
  content?: DocNode[];
}

// Nodes whose children are inline runs joined without separators.
const INLINE_CONTAINERS = new Set(['paragraph', 'heading', 'codeBlock']);

const walk = (node: DocNode): string => {
  if (node.type === 'hardBreak') return '\n';
  if (node.type === 'text') return node.text ?? '';
  const children = Array.isArray(node.content) ? node.content : [];
  return children.map(walk).join(INLINE_CONTAINERS.has(node.type ?? '') ? '' : '\n');
};

const stripHtml = (text: string): string =>
  text.replace(/<[^>]+>/g, ' ').replace(/[^\S\n]+/g, ' ').replace(/\s*\n\s*/g, '\n').trim();

/** Plain text of a note: block nodes on their own lines, formatting dropped. */
export const plainNotes = (content: string | null | undefined): string => {
  if (typeof content !== 'string') return '';
  const trimmed = content.trim();
  if (!trimmed) return '';

  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed) as DocNode;
      if (parsed && parsed.type === 'doc' && Array.isArray(parsed.content)) {
        return walk(parsed).replace(/\n{2,}/g, '\n').trim();
      }
    } catch {
      // Not a document — fall through and show the raw text
    }
    return trimmed;
  }

  if (/<[a-zA-Z][^>]*>/.test(trimmed)) return stripHtml(trimmed);
  return trimmed;
};

/** One-line rendering for result lists: whitespace collapsed, capped. */
export const notesSnippet = (content: string | null | undefined, maxChars: number): string | null => {
  const text = plainNotes(content).replace(/\s+/g, ' ').trim();
  return text ? text.slice(0, maxChars) : null;
};
