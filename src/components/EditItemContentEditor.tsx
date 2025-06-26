
import React, { useState, useEffect } from 'react';
import { Label } from '@/components/ui/label';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
} from 'novel';
import { createEditorExtensions } from './editor/EditorExtensions';
import { convertToJsonContent } from './editor/EditorUtils';
import EditorCommandMenu from './editor/EditorCommandMenu';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
}

const EditItemContentEditor = ({ content, onContentChange }: EditItemContentEditorProps) => {
  const [initialContent, setInitialContent] = useState<JSONContent | null>(null);
  const extensions = createEditorExtensions();

  useEffect(() => {
    const jsonContent = convertToJsonContent(content);
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
            extensions={extensions}
            className="min-h-[300px] w-full max-w-none"
            editorProps={{
              handleDOMEvents: {
                keydown: (_view, event) => handleCommandNavigation(event),
              },
              attributes: {
                class: 'prose prose-sm dark:prose-invert prose-headings:font-title font-default focus:outline-none max-w-full p-4 prose-h1:text-3xl prose-h1:font-bold prose-h2:text-2xl prose-h2:font-bold prose-h3:text-xl prose-h3:font-bold prose-h4:text-lg prose-h4:font-bold prose-h5:text-base prose-h5:font-bold prose-h6:text-sm prose-h6:font-bold'
              }
            }}
            onUpdate={({ editor }: { editor: EditorInstance }) => {
              // Save as JSON to preserve formatting
              const json = editor.getJSON();
              onContentChange(JSON.stringify(json));
            }}
          >
            <EditorCommandMenu />
          </EditorContent>
        </EditorRoot>
      </div>
    </div>
  );
};

export default EditItemContentEditor;
