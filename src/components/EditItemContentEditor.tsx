
import React, { useState, useEffect } from 'react';
import { Label } from '@/components/ui/label';
import {
  EditorRoot,
  EditorContent,
  EditorCommand,
  EditorCommandItem,
  EditorCommandList,
  EditorCommandEmpty,
  EditorBubble,
  EditorBubbleItem,
  type JSONContent,
  type EditorInstance,
} from 'novel';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
}

const EditItemContentEditor = ({ content, onContentChange }: EditItemContentEditorProps) => {
  const [initialContent, setInitialContent] = useState<JSONContent | null>(null);

  // Convert HTML string to JSONContent for the editor
  const convertHtmlToJson = (htmlString: string): JSONContent => {
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

  useEffect(() => {
    const jsonContent = convertHtmlToJson(content);
    setInitialContent(jsonContent);
  }, [content]);

  if (!initialContent) {
    return (
      <div>
        <Label className="text-base font-medium mb-3 block">Content</Label>
        <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
          Loading editor...
        </div>
      </div>
    );
  }

  return (
    <div>
      <Label className="text-base font-medium mb-3 block">Content</Label>
      <div className="border rounded-md">
        <EditorRoot>
          <EditorContent
            initialContent={initialContent}
            className="min-h-[300px] p-4 prose prose-sm max-w-none"
            editorProps={{
              attributes: {
                class: 'focus:outline-none'
              }
            }}
            onUpdate={({ editor }: { editor: EditorInstance }) => {
              const html = editor.getHTML();
              onContentChange(html);
            }}
          >
            <EditorCommand className="z-50 h-auto max-h-[330px] overflow-y-auto rounded-md border border-muted bg-background px-1 py-2 shadow-md transition-all">
              <EditorCommandEmpty className="px-2 text-muted-foreground">No results</EditorCommandEmpty>
              <EditorCommandList>
                <EditorCommandItem
                  value="paragraph"
                  onCommand={(val) => console.log('Paragraph command:', val)}
                  className="flex w-full items-center space-x-2 rounded-md px-2 py-1 text-left text-sm hover:bg-accent aria-selected:bg-accent"
                >
                  <div className="flex h-8 w-8 items-center justify-center rounded-md border border-muted bg-background">
                    ¶
                  </div>
                  <div>
                    <p className="font-medium">Paragraph</p>
                    <p className="text-xs text-muted-foreground">Start writing with plain text</p>
                  </div>
                </EditorCommandItem>
              </EditorCommandList>
            </EditorCommand>
            
            <EditorBubble className="flex w-fit max-w-[90vw] overflow-hidden rounded-md border border-muted bg-background shadow-xl">
              <EditorBubbleItem>Bold</EditorBubbleItem>
              <EditorBubbleItem>Italic</EditorBubbleItem>
            </EditorBubble>
          </EditorContent>
        </EditorRoot>
      </div>
    </div>
  );
};

export default EditItemContentEditor;
