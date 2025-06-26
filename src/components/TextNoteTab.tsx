
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent } from '@/components/ui/card';
import { FileText } from 'lucide-react';
import TagInput from '@/components/TagInput';
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
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [tags, setTags] = useState<string[]>([]);
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

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!content.trim()) return;

    setIsLoading(true);
    try {
      await onAddContent('text', {
        title: title.trim() || undefined,
        content: content.trim(),
        tags
      });
      setTitle('');
      setContent('');
      setTags([]);
    } catch (error) {
      console.error('Error adding note:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleGetSuggestedTags = async () => {
    if (!content.trim()) return [];
    return await getSuggestedTags({
      title: title.trim() || undefined,
      content: content.trim()
    });
  };

  return (
    <Card>
      <CardContent className="p-6">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="flex items-center gap-2 mb-4">
            <FileText className="h-5 w-5 text-blue-600" />
            <h3 className="text-lg font-medium">Create New Note</h3>
          </div>

          <div>
            <Label htmlFor="note-title">Title (optional)</Label>
            <Input
              id="note-title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Enter a title for your note..."
              className="mt-1"
            />
          </div>

          <div>
            <Label className="text-base font-medium mb-3 block">Content</Label>
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
                      class: 'prose prose-sm dark:prose-invert prose-headings:font-title font-default focus:outline-none max-w-full p-4 prose-h1:text-3xl prose-h1:font-bold prose-h2:text-2xl prose-h2:font-bold prose-h3:text-xl prose-h3:font-bold prose-h4:text-lg prose-h4:font-bold prose-h5:text-base prose-h5:font-bold prose-h6:text-sm prose-h6:font-bold'
                    }
                  }}
                  onUpdate={({ editor }: { editor: EditorInstance }) => {
                    // Save as JSON to preserve formatting
                    const json = editor.getJSON();
                    setContent(JSON.stringify(json));
                  }}
                  placeholder="Press '/' for commands or start typing..."
                >
                  <EditorCommandMenu />
                </EditorContent>
              </EditorRoot>
            </div>
          </div>

          <TagInput
            tags={tags}
            onTagsChange={setTags}
            getSuggestedTags={handleGetSuggestedTags}
            placeholder="Add tags (optional)..."
          />

          <Button 
            type="submit" 
            disabled={!content.trim() || isLoading}
            className="w-full"
          >
            {isLoading ? 'Adding Note...' : 'Add Note'}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
};

export default TextNoteTab;
