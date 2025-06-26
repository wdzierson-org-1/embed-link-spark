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
import { useAuth } from '@/hooks/useAuth';
import { uploadImage } from '@/services/imageUploadService';

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
      userId: user?.id,
      itemId,
      sessionExpiry: session?.expires_at,
      currentTime: new Date().toISOString()
    });

    if (!user || !session) {
      console.error('EditItemContentEditor: No user or session found');
      throw new Error('User not authenticated');
    }

    // Check if session is close to expiry
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

      // If session expires in less than 5 minutes, warn but continue
      if (timeUntilExpiry < 5 * 60 * 1000) {
        console.warn('EditItemContentEditor: Session expires soon, upload may fail');
      }
    }

    try {
      const result = await uploadImage({
        file,
        userId: user.id,
        itemId: itemId // This will trigger database update if provided
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
      throw error;
    }
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
