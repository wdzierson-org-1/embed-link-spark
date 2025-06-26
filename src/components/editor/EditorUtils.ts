
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

  // Handle HTML content (strip tags and create simple paragraph)
  // In a full implementation, you'd want proper HTML to ProseMirror parsing
  const textContent = input.replace(/<[^>]*>/g, '').trim();
  
  if (!textContent) {
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

  // For markdown content, create basic structure
  // This is a simplified approach - for full markdown support, 
  // you'd want to use a proper markdown to ProseMirror parser
  if (textContent.includes('•') || textContent.includes('-') || textContent.includes('*')) {
    // Simple bullet list detection
    const lines = textContent.split('\n').filter(line => line.trim());
    const listItems = lines.map(line => ({
      type: 'listItem',
      content: [
        {
          type: 'paragraph',
          content: [
            {
              type: 'text',
              text: line.replace(/^[•\-\*]\s*/, '').trim()
            }
          ]
        }
      ]
    }));

    return {
      type: 'doc',
      content: [
        {
          type: 'bulletList',
          content: listItems
        }
      ]
    };
  }

  // Default: create paragraph with text content
  return {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: [
          {
            type: 'text',
            text: textContent
          }
        ]
      }
    ]
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
