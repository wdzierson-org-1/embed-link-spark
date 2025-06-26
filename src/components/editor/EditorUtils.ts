
import { type JSONContent } from 'novel';

export const convertHtmlToJson = (htmlString: string): JSONContent => {
  if (!htmlString || htmlString.trim() === '') {
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
  
  // Create a simple paragraph with the text content
  // Strip HTML tags for now - in a real implementation you'd want proper HTML parsing
  const textContent = htmlString.replace(/<[^>]*>/g, '');
  
  return {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: textContent ? [
          {
            type: 'text',
            text: textContent
          }
        ] : []
      }
    ]
  };
};
