
import React, { useMemo, useEffect, useRef } from 'react';
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
import { toast } from 'sonner';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
  itemId?: string;
  editorInstanceKey?: string; // External key to control when editor recreates
}

const EditItemContentEditor = ({ content, onContentChange, itemId, editorInstanceKey }: EditItemContentEditorProps) => {
  const { user, session } = useAuth();
  const editorRef = useRef<EditorInstance | null>(null);

  const handleImageUpload = async (file: File): Promise<string> => {
    console.log('EditItemContentEditor: Starting image upload', { 
      fileName: file.name, 
      fileSize: file.size, 
      hasUser: !!user,
      hasSession: !!session,
      userId: user?.id 
    });

    // Enhanced authentication validation
    if (!user || !session) {
      console.error('EditItemContentEditor: No user or session found');
      toast.error('Please log in to upload images');
      throw new Error('User not authenticated');
    }

    // Validate session is still active
    const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();
    if (sessionError || !currentSession) {
      console.error('EditItemContentEditor: Session validation failed', sessionError);
      toast.error('Your session has expired. Please log in again.');
      throw new Error('Session expired');
    }

    const fileExt = file.name.split('.').pop();
    const fileName = `${Date.now()}.${fileExt}`;
    const filePath = `${user.id}/${fileName}`;

    console.log('EditItemContentEditor: Uploading to path', { filePath });

    // Retry mechanism with exponential backoff
    const maxRetries = 3;
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        console.log(`EditItemContentEditor: Upload attempt ${attempt}/${maxRetries}`);
        
        const { error: uploadError } = await supabase.storage
          .from('stash-media')
          .upload(filePath, file);

        if (uploadError) {
          console.error(`EditItemContentEditor: Upload error (attempt ${attempt}):`, uploadError);
          lastError = uploadError;
          
          if (attempt < maxRetries) {
            const delay = Math.pow(2, attempt) * 1000; // Exponential backoff
            console.log(`EditItemContentEditor: Retrying in ${delay}ms...`);
            await new Promise(resolve => setTimeout(resolve, delay));
            continue;
          }
          throw uploadError;
        }

        console.log('EditItemContentEditor: Upload successful');
        
        const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
        console.log('EditItemContentEditor: Generated public URL', { url: data.publicUrl });
        
        toast.success('Image uploaded successfully!');
        return data.publicUrl;
        
      } catch (error) {
        console.error(`EditItemContentEditor: Upload attempt ${attempt} failed:`, error);
        lastError = error as Error;
        
        if (attempt < maxRetries) {
          const delay = Math.pow(2, attempt) * 1000;
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    }

    console.error('EditItemContentEditor: All upload attempts failed');
    toast.error('Failed to upload image. Please try again.');
    throw lastError || new Error('Upload failed after all retries');
  };

  const extensions = createEditorExtensions(handleImageUpload);

  // Only recreate editor when itemId or editorInstanceKey changes, NOT on content changes
  const { initialContent, editorKey } = useMemo(() => {
    console.log('EditItemContentEditor: Processing content', { 
      itemId,
      editorInstanceKey,
      contentLength: content.length,
      contentPreview: content.slice(0, 50)
    });
    
    const jsonContent = convertToJsonContent(content);
    console.log('EditItemContentEditor: Converted to JSON', { jsonContent });
    
    // Use stable key based only on itemId and editorInstanceKey, NOT content
    const key = `editor-${itemId || 'new'}-${editorInstanceKey || 'default'}`;
    
    console.log('EditItemContentEditor: Generated stable key', { key });
    
    return {
      initialContent: jsonContent,
      editorKey: key
    };
  }, [itemId, editorInstanceKey]); // Remove content from dependencies

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
              editorRef.current = editor;
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
