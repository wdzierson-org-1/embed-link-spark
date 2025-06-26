
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import TagInput from '@/components/TagInput';
import { useToast } from '@/hooks/use-toast';

interface TextNoteTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (limit?: number) => string[];
}

const TextNoteTab = ({ onAddContent, getSuggestedTags }: TextNoteTabProps) => {
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();

  const handleSubmit = async () => {
    if (!content.trim()) {
      toast({
        title: "Content required",
        description: "Please enter some content for your note.",
        variant: "destructive",
      });
      return;
    }

    setIsSubmitting(true);
    try {
      await onAddContent('text', {
        title: title.trim() || 'Untitled Note',
        content: content.trim(),
        tags
      });

      // Reset form
      setTitle('');
      setContent('');
      setTags([]);

      toast({
        title: "Success",
        description: "Note added successfully!",
      });
    } catch (error) {
      console.error('Error adding note:', error);
      toast({
        title: "Error",
        description: "Failed to add note. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="space-y-4">
          <Input
            placeholder="Note title (optional)"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />

          <Textarea
            placeholder="Write your note here..."
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={6}
            className="resize-none"
          />

          <div>
            <p className="text-sm font-medium mb-2">Tags</p>
            <TagInput
              tags={tags}
              onTagsChange={setTags}
              suggestions={getSuggestedTags()}
            />
          </div>

          <Button 
            onClick={handleSubmit} 
            disabled={!content.trim() || isSubmitting}
            className="w-full"
          >
            {isSubmitting ? 'Adding Note...' : 'Add Note'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};

export default TextNoteTab;
