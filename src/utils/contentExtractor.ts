
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
  let text = '';

  // If this node has text content, add it
  if (node.text) {
    text += node.text;
  }

  // If this node has content (children), process them recursively
  if (node.content && Array.isArray(node.content)) {
    node.content.forEach(child => {
      const childText = extractTextFromJsonContent(child);
      if (childText) {
        // Add spacing between different content blocks
        if (text && !text.endsWith(' ') && !text.endsWith('\n')) {
          if (child.type === 'paragraph' || child.type === 'heading') {
            text += '\n';
          } else {
            text += ' ';
          }
        }
        text += childText;
      }
    });
  }

  return text;
};
