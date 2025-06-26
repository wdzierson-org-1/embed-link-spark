
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
import { useAuth } from '@/hooks/useAuth';
import { uploadImage } from '@/services/imageUploadService';

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

    if (!user || !session) {
      console.error('TextNoteTab: No user or session found');
      throw new Error('User not authenticated');
    }

    try {
      const result = await uploadImage({
        file,
        userId: user.id
        // No itemId provided since this is for new content creation
      });
      
      return result.publicUrl;
    } catch (error) {
      console.error('TextNoteTab: Upload failed', error);
      throw error;
    }
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
