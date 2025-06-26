
import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
} from 'novel';
import { createEditorExtensions } from './editor/EditorExtensions';
import EditorCommandMenu from './editor/EditorCommandMenu';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { toast } from 'sonner';

interface TextNoteTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: { title?: string; content?: string; description?: string }) => Promise<string[]>;
}

const TextNoteTab = ({ onAddContent, getSuggestedTags }: TextNoteTabProps) => {
  const [content, setContent] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [editorInstance, setEditorInstance] = useState<EditorInstance | null>(null);
  const { user, session } = useAuth();

  const handleImageUpload = async (file: File): Promise<string> => {
    console.log('TextNoteTab: Starting image upload', { 
      fileName: file.name, 
      fileSize: file.size, 
      hasUser: !!user,
      hasSession: !!session,
      userId: user?.id 
    });

    // Enhanced authentication validation
    if (!user || !session) {
      console.error('TextNoteTab: No user or session found');
      toast.error('Please log in to upload images');
      throw new Error('User not authenticated');
    }

    // Validate session is still active
    const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession();
    if (sessionError || !currentSession) {
      console.error('TextNoteTab: Session validation failed', sessionError);
      toast.error('Your session has expired. Please log in again.');
      throw new Error('Session expired');
    }

    const fileExt = file.name.split('.').pop();
    const fileName = `${Date.now()}.${fileExt}`;
    const filePath = `${user.id}/${fileName}`;

    console.log('TextNoteTab: Uploading to path', { filePath });

    // Retry mechanism with exponential backoff
    const maxRetries = 3;
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        console.log(`TextNoteTab: Upload attempt ${attempt}/${maxRetries}`);
        
        const { error: uploadError } = await supabase.storage
          .from('stash-media')
          .upload(filePath, file);

        if (uploadError) {
          console.error(`TextNoteTab: Upload error (attempt ${attempt}):`, uploadError);
          lastError = uploadError;
          
          if (attempt < maxRetries) {
            const delay = Math.pow(2, attempt) * 1000; // Exponential backoff
            console.log(`TextNoteTab: Retrying in ${delay}ms...`);
            await new Promise(resolve => setTimeout(resolve, delay));
            continue;
          }
          throw uploadError;
        }

        console.log('TextNoteTab: Upload successful');
        
        const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
        console.log('TextNoteTab: Generated public URL', { url: data.publicUrl });
        
        toast.success('Image uploaded successfully!');
        return data.publicUrl;
        
      } catch (error) {
        console.error(`TextNoteTab: Upload attempt ${attempt} failed:`, error);
        lastError = error as Error;
        
        if (attempt < maxRetries) {
          const delay = Math.pow(2, attempt) * 1000;
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    }

    console.error('TextNoteTab: All upload attempts failed');
    toast.error('Failed to upload image. Please try again.');
    throw lastError || new Error('Upload failed after all retries');
  };

  const extensions = createEditorExtensions(handleImageUpload);

  const initialContent: JSONContent = {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: []
      }
    ]
  };

  const clearEditor = () => {
    if (editorInstance) {
      editorInstance.commands.setContent(initialContent);
    }
    setContent('');
  };

  const handleSubmit = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!content.trim()) return;

    setIsLoading(true);
    try {
      await onAddContent('text', {
        content: content.trim(),
        tags: []
      });
      clearEditor();
    } catch (error) {
      console.error('Error adding note:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleContentChange = (newContent: string) => {
    setContent(newContent);
  };

  const handleKeyDown = (e: KeyboardEvent) => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault();
      handleSubmit();
    }
  };

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [content]);

  const hasContent = content.trim().length > 0;

  return (
    <Card>
      <CardContent className="p-6">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="relative">
            <div className="border rounded-md">
              <EditorRoot>
                <EditorContent
                  initialContent={initialContent}
                  extensions={extensions}
                  className="min-h-[200px] w-full max-w-none"
                  editorProps={{
                    handleDOMEvents: {
                      keydown: (_view, event) => handleCommandNavigation(event),
                    },
                    attributes: {
                      class: 'prose prose-sm dark:prose-invert prose-headings:font-title font-default focus:outline-none max-w-full p-4 prose-h1:text-3xl prose-h1:font-bold prose-h2:text-2xl prose-h2:font-bold prose-h3:text-xl prose-h3:font-bold prose-h4:text-lg prose-h4:font-bold prose-h5:text-base prose-h5:font-bold prose-h6:text-sm prose-h6:font-bold',
                      'data-placeholder': 'Start typing...'
                    }
                  }}
                  onUpdate={({ editor }: { editor: EditorInstance }) => {
                    setEditorInstance(editor);
                    // Save as JSON to preserve formatting
                    const json = editor.getJSON();
                    handleContentChange(JSON.stringify(json));
                  }}
                >
                  <EditorCommandMenu />
                </EditorContent>
              </EditorRoot>
            </div>
            <div className="absolute bottom-2 right-2 text-xs text-gray-400 pointer-events-none">
              Press / for formatting options
            </div>
          </div>

          <div className="text-xs text-gray-500">
            Press cmd + enter to save quickly
          </div>

          {hasContent && (
            <Button 
              type="submit" 
              disabled={isLoading}
              className="w-full"
            >
              {isLoading ? 'Adding Note...' : 'Add Note'}
            </Button>
          )}
        </form>
      </CardContent>
    </Card>
  );
};

export default TextNoteTab;
