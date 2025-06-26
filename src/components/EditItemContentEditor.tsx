
import React, { useState, useEffect } from 'react';
import { Label } from '@/components/ui/label';
import {
  EditorRoot,
  EditorContent,
  EditorCommand,
  EditorCommandItem,
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
  const [editorContent, setEditorContent] = useState<JSONContent | null>(null);

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
    
    // For now, we'll create a simple paragraph with the text content
    // In a more sophisticated implementation, you'd parse the HTML properly
    return {
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            {
              type: 'text',
              text: htmlString.replace(/<[^>]*>/g, '') // Strip HTML tags for now
            }
          ]
        }
      ]
    };
  };

  useEffect(() => {
    setEditorContent(convertHtmlToJson(content));
  }, [content]);

  return (
    <div>
      <Label className="text-base font-medium mb-3 block">Content</Label>
      <div className="border rounded-md">
        {editorContent && (
          <EditorRoot>
            <EditorContent
              initialContent={editorContent}
              onUpdate={({ editor }: { editor: EditorInstance }) => {
                const html = editor.getHTML();
                onContentChange(html);
              }}
              className="min-h-[300px] p-4"
            >
              <EditorCommand className="z-50 h-auto max-h-[330px] overflow-y-auto rounded-md border border-muted bg-background px-1 py-2 shadow-md transition-all">
                <EditorCommandItem
                  value="paragraph"
                  onCommand={(val) => console.log(val)}
                />
              </EditorCommand>
              <EditorBubble className="flex w-fit max-w-[90vw] overflow-hidden rounded-md border border-muted bg-background shadow-xl">
                <EditorBubbleItem>Bold</EditorBubbleItem>
                <EditorBubbleItem>Italic</EditorBubbleItem>
              </EditorBubble>
            </EditorContent>
          </EditorRoot>
        )}
      </div>
    </div>
  );
};

export default EditItemContentEditor;
