
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
import EditorBubbleMenu from './editor/EditorBubbleMenu';
import { useAuth } from '@/hooks/useAuth';
import { uploadImage } from '@/services/imageUploadService';
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
  itemId?: string;
  editorInstanceKey?: string;
  isMaximized?: boolean;
}

const EditItemContentEditor = ({ content, onContentChange, itemId, editorInstanceKey, isMaximized = false }: EditItemContentEditorProps) => {
  const { user, session } = useAuth();
  const editorRef = useRef<EditorInstance | null>(null);
  const lastContentRef = useRef<string>('');

  const handleImageUpload = async (file: File): Promise<string> => {
    console.log('EditItemContentEditor: Starting image upload', { 
      fileName: file.name, 
      fileSize: file.size, 
      hasUser: !!user,
      hasSession: !!session,
      userId: user?.id,
      itemId,
      sessionExpiry: session?.expires_at,
      currentTime: new Date().toISOString()
    });

    if (!user || !session) {
      console.error('EditItemContentEditor: No user or session found');
      toast.error('Please log in to upload images');
      throw new Error('User not authenticated');
    }

    if (session.expires_at) {
      const expiryTime = new Date(session.expires_at * 1000);
      const currentTime = new Date();
      const timeUntilExpiry = expiryTime.getTime() - currentTime.getTime();
      
      console.log('EditItemContentEditor: Session timing', {
        expiryTime: expiryTime.toISOString(),
        currentTime: currentTime.toISOString(),
        timeUntilExpiryMs: timeUntilExpiry,
        timeUntilExpiryMin: Math.floor(timeUntilExpiry / 1000 / 60)
      });

      if (timeUntilExpiry < 5 * 60 * 1000) {
        console.log('EditItemContentEditor: Session expires soon, refreshing...');
        try {
          const { error } = await supabase.auth.refreshSession();
          if (error) {
            console.error('EditItemContentEditor: Failed to refresh session', error);
            toast.error('Session expired. Please refresh the page and try again.');
            throw new Error('Session expired');
          }
        } catch (refreshError) {
          console.error('EditItemContentEditor: Session refresh failed', refreshError);
          toast.error('Session expired. Please refresh the page and try again.');
          throw refreshError;
        }
      }
    }

    try {
      const result = await uploadImage({
        file,
        userId: user.id,
        itemId: itemId
      });
      
      console.log('EditItemContentEditor: Upload completed successfully', {
        publicUrl: result.publicUrl,
        filePath: result.filePath
      });
      
      return result.publicUrl;
    } catch (error) {
      console.error('EditItemContentEditor: Upload failed', {
        error,
        errorMessage: error instanceof Error ? error.message : 'Unknown error',
        userId: user.id,
        itemId,
        fileName: file.name
      });
      
      if (error instanceof Error) {
        if (error.message.includes('RLS') || 
            error.message.includes('policy') || 
            error.message.includes('Unauthorized') ||
            error.message.includes('row-level security')) {
          toast.error('Permission denied. Please refresh the page and try again.');
        } else if (error.message.includes('Session expired')) {
          toast.error('Session expired. Please refresh the page and try again.');
        } else if (error.message.includes('User ID mismatch')) {
          toast.error('Authentication error. Please refresh the page and try again.');
        } else {
          toast.error(`Upload failed: ${error.message}`);
        }
      } else {
        toast.error('Failed to upload image. Please try again.');
      }
      
      throw error;
    }
  };

  const extensions = createEditorExtensions(handleImageUpload);

  const { initialContent, effectiveEditorKey } = useMemo(() => {
    console.log('EditItemContentEditor: Processing content for editor recreation', { 
      itemId,
      editorInstanceKey,
      contentLength: content.length,
      contentPreview: content.slice(0, 100)
    });
    
    const jsonContent = convertToJsonContent(content);
    console.log('EditItemContentEditor: Converted to JSON', { jsonContent });
    
    const key = editorInstanceKey || `editor-${itemId || 'new'}-${Date.now()}`;
    
    console.log('EditItemContentEditor: Generated editor key', { key });
    
    // Store the initial content for comparison
    lastContentRef.current = content;
    
    return {
      initialContent: jsonContent,
      effectiveEditorKey: key
    };
  }, [editorInstanceKey, itemId, content]);

  console.log('EditItemContentEditor: Rendering with key', { 
    effectiveEditorKey,
    hasInitialContent: !!initialContent,
    contentPreview: content.slice(0, 50)
  });

  if (!initialContent) {
    console.log('EditItemContentEditor: No initial content, showing loading');
    return (
      <div>
        <div className={`flex items-center justify-center text-muted-foreground ${isMaximized ? 'h-96' : 'border rounded-md p-4 min-h-[300px]'}`}>
          Loading editor...
        </div>
      </div>
    );
  }

  return (
    <div className={isMaximized ? "h-full flex flex-col" : "border rounded-md"}>
      <EditorRoot key={effectiveEditorKey}>
        <EditorContent
          initialContent={initialContent}
          extensions={extensions}
          className={isMaximized ? "flex-1 w-full max-w-none overflow-y-auto" : "min-h-[300px] w-full max-w-none"}
          editorProps={{
            handleDOMEvents: {
              keydown: (_view, event) => handleCommandNavigation(event),
            },
            attributes: {
              class: 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-4 prose-h1:text-4xl prose-h1:font-bold prose-h2:text-3xl prose-h2:font-bold prose-h3:text-2xl prose-h3:font-bold prose-h4:text-xl prose-h4:font-bold prose-h5:text-lg prose-h5:font-bold prose-h6:text-base prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 prose-ul:leading-normal prose-ol:leading-normal prose-li:leading-normal prose-li:mb-1 prose-p:leading-normal prose-p:mb-2'
            }
          }}
          onUpdate={({ editor }: { editor: EditorInstance }) => {
            console.log('EditItemContentEditor: Content updated in editor');
            editorRef.current = editor;
            const json = editor.getJSON();
            const jsonString = JSON.stringify(json);
            
            // Only call onContentChange if content actually changed
            if (jsonString !== lastContentRef.current) {
              console.log('EditItemContentEditor: Content changed, calling onContentChange', {
                previousLength: lastContentRef.current.length,
                newLength: jsonString.length,
                preview: jsonString.slice(0, 100)
              });
              
              lastContentRef.current = jsonString;
              onContentChange(jsonString);
            } else {
              console.log('EditItemContentEditor: Content unchanged, skipping onContentChange');
            }
          }}
        >
          <EditorCommandMenu />
          <EditorBubbleMenu />
        </EditorContent>
      </EditorRoot>
    </div>
  );
};

export default EditItemContentEditor;
