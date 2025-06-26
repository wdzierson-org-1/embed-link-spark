
import React, { useMemo } from 'react';
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

// Simple hash function for strings (safe for Unicode)
const simpleHash = (str: string): string => {
  let hash = 0;
  if (str.length === 0) return 'empty';
  
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  
  return Math.abs(hash).toString(36);
};

const EditItemContentEditor = ({ content, onContentChange }: EditItemContentEditorProps) => {
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

  // Convert content to JSON synchronously and create a stable key
  const { initialContent, editorKey } = useMemo(() => {
    console.log('EditItemContentEditor: Processing content', { content, contentLength: content.length });
    
    const jsonContent = convertToJsonContent(content);
    console.log('EditItemContentEditor: Converted to JSON', { jsonContent });
    
    // Create a stable key based on content hash - only change when content structure changes
    const contentHash = simpleHash(content);
    const key = `editor-${contentHash}`;
    
    console.log('EditItemContentEditor: Generated key', { key });
    
    return {
      initialContent: jsonContent,
      editorKey: key
    };
  }, [content]);

  console.log('EditItemContentEditor: Rendering', { 
    hasInitialContent: !!initialContent,
    editorKey,
    contentPreview: content.slice(0, 50)
  });

  if (!initialContent) {
    console.log('EditItemContentEditor: No initial content, showing loading');
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
              console.log('EditItemContentEditor: Content updated');
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
