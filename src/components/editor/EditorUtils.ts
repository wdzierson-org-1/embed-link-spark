
import { type JSONContent } from 'novel';

export const convertToJsonContent = (input: string): JSONContent => {
  // If input is empty or null, return empty document
  if (!input || input.trim() === '') {
    return {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: []
        }
      ]
    };
  }

  // Try to parse as JSON first (for content saved by the editor)
  try {
    const parsed = JSON.parse(input);
    // Validate it's a proper Tiptap document structure
    if (parsed && parsed.type === 'doc' && Array.isArray(parsed.content)) {
      return parsed;
    }
  } catch (e) {
    // Not JSON, continue to HTML/Markdown parsing
  }

  // Enhanced markdown parsing
  const lines = input.split('\n');
  const content: any[] = [];
  let currentList: any = null;
  let listType: 'bulletList' | 'orderedList' | 'taskList' | null = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmedLine = line.trim();

    if (trimmedLine === '') {
      // Close any open list
      if (currentList) {
        content.push(currentList);
        currentList = null;
        listType = null;
      }
      continue;
    }

    // Check for headings (markdown style)
    const headingMatch = trimmedLine.match(/^(#{1,6})\s+(.+)$/);
    if (headingMatch) {
      // Close any open list
      if (currentList) {
        content.push(currentList);
        currentList = null;
        listType = null;
      }
      
      content.push({
        type: 'heading',
        attrs: { level: headingMatch[1].length },
        content: [{ type: 'text', text: headingMatch[2] }]
      });
      continue;
    }

    // Check for bold text (**text** or __text__)
    const processBoldText = (text: string) => {
      const boldRegex = /(\*\*|__)(.*?)\1/g;
      const parts: any[] = [];
      let lastIndex = 0;
      let match;

      while ((match = boldRegex.exec(text)) !== null) {
        // Add text before the bold part
        if (match.index > lastIndex) {
          const beforeText = text.slice(lastIndex, match.index);
          if (beforeText) {
            parts.push({ type: 'text', text: beforeText });
          }
        }
        
        // Add bold text
        parts.push({
          type: 'text',
          text: match[2],
          marks: [{ type: 'bold' }]
        });
        
        lastIndex = match.index + match[0].length;
      }

      // Add remaining text
      if (lastIndex < text.length) {
        const remainingText = text.slice(lastIndex);
        if (remainingText) {
          parts.push({ type: 'text', text: remainingText });
        }
      }

      return parts.length > 0 ? parts : [{ type: 'text', text: text }];
    };

    // Check for task list items (- [ ] or - [x])
    const taskMatch = trimmedLine.match(/^[-*]\s+\[([ x])\]\s+(.+)$/);
    if (taskMatch) {
      const isChecked = taskMatch[1].toLowerCase() === 'x';
      const taskText = taskMatch[2];

      if (listType !== 'taskList') {
        if (currentList) {
          content.push(currentList);
        }
        currentList = { type: 'taskList', content: [] };
        listType = 'taskList';
      }

      currentList.content.push({
        type: 'taskItem',
        attrs: { checked: isChecked },
        content: [{
          type: 'paragraph',
          content: processBoldText(taskText)
        }]
      });
      continue;
    }

    // Check for bullet list items (- or *)
    const bulletMatch = trimmedLine.match(/^[-*]\s+(.+)$/);
    if (bulletMatch) {
      const bulletText = bulletMatch[1];

      if (listType !== 'bulletList') {
        if (currentList) {
          content.push(currentList);
        }
        currentList = { type: 'bulletList', content: [] };
        listType = 'bulletList';
      }

      currentList.content.push({
        type: 'listItem',
        content: [{
          type: 'paragraph',
          content: processBoldText(bulletText)
        }]
      });
      continue;
    }

    // Check for numbered list items (1. 2. etc.)
    const numberedMatch = trimmedLine.match(/^\d+\.\s+(.+)$/);
    if (numberedMatch) {
      const numberedText = numberedMatch[1];

      if (listType !== 'orderedList') {
        if (currentList) {
          content.push(currentList);
        }
        currentList = { type: 'orderedList', content: [] };
        listType = 'orderedList';
      }

      currentList.content.push({
        type: 'listItem',
        content: [{
          type: 'paragraph',
          content: processBoldText(numberedText)
        }]
      });
      continue;
    }

    // Regular paragraph
    if (currentList) {
      content.push(currentList);
      currentList = null;
      listType = null;
    }

    if (trimmedLine) {
      content.push({
        type: 'paragraph',
        content: processBoldText(trimmedLine)
      });
    }
  }

  // Don't forget to add any remaining list
  if (currentList) {
    content.push(currentList);
  }

  // If no content was parsed, create a simple paragraph
  if (content.length === 0) {
    content.push({
      type: 'paragraph',
      content: [{ type: 'text', text: input }]
    });
  }

  return {
    type: 'doc',
    content
  };
};

// Helper function to convert JSON back to HTML for display purposes
export const convertJsonToHtml = (jsonContent: JSONContent): string => {
  // This is a simplified converter - in practice you'd use Tiptap's generateHTML
  if (!jsonContent || !jsonContent.content) return '';
  
  const convertNode = (node: any): string => {
    switch (node.type) {
      case 'doc':
        return node.content?.map(convertNode).join('') || '';
      case 'paragraph':
        const paragraphContent = node.content?.map(convertNode).join('') || '';
        return `<p>${paragraphContent}</p>`;
      case 'heading':
        const headingContent = node.content?.map(convertNode).join('') || '';
        const level = node.attrs?.level || 1;
        return `<h${level}>${headingContent}</h${level}>`;
      case 'bulletList':
        const listItems = node.content?.map(convertNode).join('') || '';
        return `<ul>${listItems}</ul>`;
      case 'orderedList':
        const orderedItems = node.content?.map(convertNode).join('') || '';
        return `<ol>${orderedItems}</ol>`;
      case 'listItem':
        const itemContent = node.content?.map(convertNode).join('') || '';
        return `<li>${itemContent}</li>`;
      case 'taskList':
        const taskItems = node.content?.map(convertNode).join('') || '';
        return `<ul class="task-list">${taskItems}</ul>`;
      case 'taskItem':
        const taskContent = node.content?.map(convertNode).join('') || '';
        const checked = node.attrs?.checked ? 'checked' : '';
        return `<li class="task-item"><input type="checkbox" ${checked} disabled>${taskContent}</li>`;
      case 'blockquote':
        const quoteContent = node.content?.map(convertNode).join('') || '';
        return `<blockquote>${quoteContent}</blockquote>`;
      case 'codeBlock':
        const codeContent = node.content?.map(convertNode).join('') || '';
        return `<pre><code>${codeContent}</code></pre>`;
      case 'text':
        let text = node.text || '';
        if (node.marks) {
          node.marks.forEach((mark: any) => {
            switch (mark.type) {
              case 'bold':
                text = `<strong>${text}</strong>`;
                break;
              case 'italic':
                text = `<em>${text}</em>`;
                break;
              case 'code':
                text = `<code>${text}</code>`;
                break;
            }
          });
        }
        return text;
      default:
        return node.content?.map(convertNode).join('') || '';
    }
  };

  return convertNode(jsonContent);
};
