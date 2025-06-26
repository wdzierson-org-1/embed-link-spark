
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Textarea } from '@/components/ui/textarea';
import { useToast } from '@/hooks/use-toast';

interface TextNoteTabProps {
  onAddContent: (type: string, data: any) => Promise<void>;
  getSuggestedTags: (limit?: number) => string[];
}

const TextNoteTab = ({ onAddContent, getSuggestedTags }: TextNoteTabProps) => {
  const [content, setContent] = useState('');
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
        title: 'Untitled Note',
        content: content.trim(),
        tags: []
      });

      // Reset form
      setContent('');

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
          <Textarea
            placeholder="Write your note here..."
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={6}
            className="resize-none"
          />

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
