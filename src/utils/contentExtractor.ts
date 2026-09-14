
import { type JSONContent } from 'novel';

/**
 * Extracts plain text from Novel editor JSON content, stripping all formatting
 */
export const extractPlainTextFromNovelContent = (content: string): string => {
  if (!content || content.trim() === '') {
    return '';
  }

  // Try to parse as JSON first (Novel editor format)
  try {
    const parsed = JSON.parse(content);
    if (parsed && parsed.type === 'doc' && Array.isArray(parsed.content)) {
      return extractTextFromJsonContent(parsed);
    }
  } catch (e) {
    // Not JSON, treat as plain text
    return content;
  }

  // Fallback to original content if parsing fails
  return content;
};

/**
 * Recursively extracts text from Novel editor JSON content
 */
const extractTextFromJsonContent = (node: JSONContent): string => {
  if (node.type === 'hardBreak') return '\n';
  if (node.type === 'text') return node.text ?? '';
  const children = node.content ?? [];
  const inline = ['paragraph', 'heading', 'codeBlock'].includes(node.type ?? '');
  return children.map(extractTextFromJsonContent).join(inline ? '' : '\n');
};
