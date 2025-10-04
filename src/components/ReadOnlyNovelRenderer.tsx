import React, { useMemo } from 'react';
import { EditorRoot, EditorContent } from 'novel';
import { createReadOnlyEditorExtensions } from './editor/EditorExtensions';
import ReactMarkdown from 'react-markdown';

interface ReadOnlyNovelRendererProps {
  content: string;
  maxLines?: number;
  className?: string;
}

const isNovelContent = (content: string): boolean => {
  if (!content) return false;
  try {
    const parsed = JSON.parse(content);
    return parsed?.type === 'doc' && Array.isArray(parsed.content);
  } catch {
    return false;
  }
};

const ReadOnlyNovelRenderer: React.FC<ReadOnlyNovelRendererProps> = ({ 
  content, 
  maxLines = 3,
  className = ''
}) => {
  const extensions = useMemo(() => createReadOnlyEditorExtensions(), []);
  const isNovel = useMemo(() => isNovelContent(content), [content]);
  
  // Calculate max height based on lines (assuming ~1.5rem line height)
  const maxHeight = `${maxLines * 1.5}rem`;

  if (!content) return null;

  // Render Novel content with read-only editor
  if (isNovel) {
    let parsedContent;
    try {
      parsedContent = JSON.parse(content);
    } catch {
      return null;
    }

    return (
      <div 
        className={`overflow-hidden ${className}`}
        style={{ maxHeight }}
      >
        <EditorRoot>
          <EditorContent
            editable={false}
            extensions={extensions}
            initialContent={parsedContent}
            editorProps={{
              attributes: {
                class: 'prose prose-sm max-w-none focus:outline-none cursor-default select-text text-muted-foreground',
              },
            }}
          />
        </EditorRoot>
      </div>
    );
  }

  // Fallback: Check if it looks like markdown (has markdown syntax)
  const hasMarkdownSyntax = /[*_#\[\]`]/.test(content);
  
  if (hasMarkdownSyntax) {
    return (
      <div 
        className={`overflow-hidden ${className}`}
        style={{ maxHeight }}
      >
        <div className="prose prose-sm max-w-none text-muted-foreground">
          <ReactMarkdown
            components={{
              h1: ({node, ...props}) => <h1 className="text-base font-bold mt-2 mb-1" {...props} />,
              h2: ({node, ...props}) => <h2 className="text-base font-semibold mt-2 mb-1" {...props} />,
              h3: ({node, ...props}) => <h3 className="text-sm font-semibold mt-1 mb-1" {...props} />,
              p: ({node, ...props}) => <p className="mb-1" {...props} />,
              ul: ({node, ...props}) => <ul className="list-disc list-inside mb-1" {...props} />,
              ol: ({node, ...props}) => <ol className="list-decimal list-inside mb-1" {...props} />,
              li: ({node, ...props}) => <li className="ml-2" {...props} />,
              strong: ({node, ...props}) => <strong className="font-semibold" {...props} />,
              em: ({node, ...props}) => <em className="italic" {...props} />,
              a: ({node, ...props}) => <a className="text-blue-600 hover:underline" target="_blank" rel="noopener noreferrer" {...props} />,
            }}
          >
            {content}
          </ReactMarkdown>
        </div>
      </div>
    );
  }

  // Plain text fallback
  return (
    <p 
      className={`text-muted-foreground text-sm ${className}`}
      style={{ 
        maxHeight,
        overflow: 'hidden',
        display: '-webkit-box',
        WebkitLineClamp: maxLines,
        WebkitBoxOrient: 'vertical'
      }}
    >
      {content}
    </p>
  );
};

export default ReadOnlyNovelRenderer;
