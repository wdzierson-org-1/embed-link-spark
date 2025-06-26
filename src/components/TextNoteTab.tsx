
import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Card, CardContent } from '@/components/ui/card';
import { FileText } from 'lucide-react';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
} from 'novel';
import { createEditorExtensions } from './editor/EditorExtensions';
import EditorCommandMenu from './editor/EditorCommandMenu';

interface TextNoteTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (content: { title?: string; content?: string; description?: string }) => Promise<string[]>;
}

const TextNoteTab = ({ onAddContent, getSuggestedTags }: TextNoteTabProps) => {
  const [content, setContent] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const extensions = createEditorExtensions();

  const initialContent: JSONContent = {
    type: 'doc',
    content: [
      {
        type: 'paragraph',
        content: []
      }
    ]
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
      setContent('');
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
          <div className="flex items-center gap-2 mb-4">
            <FileText className="h-5 w-5 text-blue-600" />
          </div>

          <div>
            <div className="flex items-center justify-between mb-3">
              <Label className="text-base font-medium">Content</Label>
              <span className="text-sm text-gray-400">Press / for formatting options</span>
            </div>
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
                      'data-placeholder': 'Press \'/\' for commands or start typing...'
                    }
                  }}
                  onUpdate={({ editor }: { editor: EditorInstance }) => {
                    // Save as JSON to preserve formatting
                    const json = editor.getJSON();
                    handleContentChange(JSON.stringify(json));
                  }}
                >
                  <EditorCommandMenu />
                </EditorContent>
              </EditorRoot>
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
