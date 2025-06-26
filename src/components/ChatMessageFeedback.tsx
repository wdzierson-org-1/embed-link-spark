
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { ThumbsUp, ThumbsDown } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface ChatMessageFeedbackProps {
  question: string;
  answer: string;
  sourceItemIds: string[];
}

const ChatMessageFeedback = ({ question, answer, sourceItemIds }: ChatMessageFeedbackProps) => {
  const [rating, setRating] = useState<number | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();

  const handleFeedback = async (feedbackRating: number) => {
    setIsSubmitting(true);
    
    try {
      const { error } = await supabase
        .from('chat_feedback')
        .insert({
          question,
          answer,
          source_item_ids: sourceItemIds,
          rating: feedbackRating
        });

      if (error) throw error;

      setRating(feedbackRating);
      toast({
        title: "Thank you!",
        description: "Your feedback has been recorded."
      });
    } catch (error) {
      console.error('Error submitting feedback:', error);
      toast({
        title: "Error",
        description: "Failed to submit feedback",
        variant: "destructive"
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex items-center gap-2 mt-2">
      <Button
        variant={rating === 1 ? "default" : "ghost"}
        size="sm"
        onClick={() => handleFeedback(1)}
        disabled={isSubmitting || rating !== null}
        className="h-8 w-8 p-0"
      >
        <ThumbsUp className="h-4 w-4" />
      </Button>
      <Button
        variant={rating === -1 ? "destructive" : "ghost"}
        size="sm"
        onClick={() => handleFeedback(-1)}
        disabled={isSubmitting || rating !== null}
        className="h-8 w-8 p-0"
      >
        <ThumbsDown className="h-4 w-4" />
      </Button>
    </div>
  );
};

export default ChatMessageFeedback;
