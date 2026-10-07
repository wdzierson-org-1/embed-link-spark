
import React, { useState } from 'react';

import { ThumbsUp, ThumbsDown } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useAuth } from '@/hooks/useAuth';

interface ChatMessageFeedbackProps {
  question: string;
  answer: string;
  sourceItemIds: string[];
}

const ChatMessageFeedback = ({ question, answer, sourceItemIds }: ChatMessageFeedbackProps) => {
  const [rating, setRating] = useState<number | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();
  const { user } = useAuth();

  const handleFeedback = async (feedbackRating: number) => {
    if (!user) return;
    
    setIsSubmitting(true);
    
    try {
      const { error } = await supabase
        .from('chat_feedback')
        .insert({
          user_id: user.id,
          question,
          answer,
          source_item_ids: sourceItemIds,
          rating: feedbackRating
        });

      if (error) throw error;

      setRating(feedbackRating);
      toast({
        title: "Feedback saved",
        description: "Thanks for rating this answer."
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

  // Square glyph buttons beside the answer's other controls; the chosen one stays inked
  const button = (value: number) =>
    `grid h-7 w-7 place-items-center transition-colors disabled:cursor-default ${
      rating === value ? 'bg-ink text-white' : 'text-muted-foreground hover:bg-fill hover:text-ink disabled:hover:bg-transparent'
    }`;

  return (
    <div className="flex items-center gap-0.5">
      <button
        type="button"
        aria-label="Good answer"
        aria-pressed={rating === 1}
        onClick={() => handleFeedback(1)}
        disabled={isSubmitting || rating !== null}
        className={button(1)}
      >
        <ThumbsUp className="h-3.5 w-3.5" />
      </button>
      <button
        type="button"
        aria-label="Bad answer"
        aria-pressed={rating === -1}
        onClick={() => handleFeedback(-1)}
        disabled={isSubmitting || rating !== null}
        className={button(-1)}
      >
        <ThumbsDown className="h-3.5 w-3.5" />
      </button>
    </div>
  );
};

export default ChatMessageFeedback;
