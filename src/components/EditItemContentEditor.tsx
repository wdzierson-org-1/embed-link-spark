
import React, { useState, useEffect, useMemo } from 'react';
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
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
}

const EditItemContentEditor = ({ content, onContentChange }: EditItemContentEditorProps) => {
  const [initialContent, setInitialContent] = useState<JSONContent | null>(null);
  const { user } = useAuth();

  const handleImageUpload = async (file: File): Promise<string> => {
    if (!user) {
      throw new Error('User not authenticated');
    }

    const fileExt = file.name.split('.').pop();
    const fileName = `${Date.now()}.${fileExt}`;
    const filePath = `${user.id}/${fileName}`;

    const { error: uploadError } = await supabase.storage
      .from('stash-media')
      .upload(filePath, file);

    if (uploadError) {
      throw uploadError;
    }

    const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
    return data.publicUrl;
  };

  const extensions = createEditorExtensions(handleImageUpload);

  // Create a unique key based on content to force re-render when content changes
  const editorKey = useMemo(() => {
    return `editor-${Date.now()}-${content.length}`;
  }, [content]);

  useEffect(() => {
    const jsonContent = convertToJsonContent(content);
    setInitialContent(jsonContent);
  }, [content]);

  if (!initialContent) {
    return (
      <div>
        <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
          Loading editor...
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="border rounded-md">
        <EditorRoot key={editorKey}>
          <EditorContent
            initialContent={initialContent}
            extensions={extensions}
            className="min-h-[300px] w-full max-w-none"
            editorProps={{
              handleDOMEvents: {
                keydown: (_view, event) => handleCommandNavigation(event),
              },
              attributes: {
                class: 'prose prose-lg dark:prose-invert prose-headings:font-title font-default focus:outline-none max-w-full p-4 prose-h1:text-4xl prose-h1:font-bold prose-h2:text-3xl prose-h2:font-bold prose-h3:text-2xl prose-h3:font-bold prose-h4:text-xl prose-h4:font-bold prose-h5:text-lg prose-h5:font-bold prose-h6:text-base prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800'
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
