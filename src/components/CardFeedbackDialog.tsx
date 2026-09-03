import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { useToast } from '@/hooks/use-toast';
import { buildCardFeedbackSnapshot, CARD_FEEDBACK_ISSUES, type CardFeedbackIssue } from '@/utils/cardFeedback';

interface CardFeedbackDialogProps {
  item: {
    id: string;
    type?: string;
    title?: string;
    description?: string;
    url?: string;
    file_path?: string;
    summary?: string;
    attributes?: { link?: { flavor?: string } };
  };
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * "Report a problem" for one card: a checkbox list of the things that can go
 * wrong with enrichment/rendering plus an optional note. Writes one
 * `card_feedback` row (see src/utils/cardFeedback.ts for the codes).
 */
const CardFeedbackDialog = ({ item, open, onOpenChange }: CardFeedbackDialogProps) => {
  const [issues, setIssues] = useState<CardFeedbackIssue[]>([]);
  const [note, setNote] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { user } = useAuth();
  const { toast } = useToast();

  const toggle = (code: CardFeedbackIssue, checked: boolean) => {
    setIssues((current) => (checked ? [...current, code] : current.filter((c) => c !== code)));
  };

  const reset = () => {
    setIssues([]);
    setNote('');
  };

  const handleOpenChange = (next: boolean) => {
    if (!next) reset();
    onOpenChange(next);
  };

  const handleSubmit = async () => {
    if (!user || issues.length === 0) return;
    setIsSubmitting(true);
    try {
      const { error } = await supabase.from('card_feedback').insert({
        user_id: user.id,
        item_id: item.id,
        issues,
        note: note.trim() || null,
        client: 'web',
        snapshot: buildCardFeedbackSnapshot(item),
      });
      if (error) throw error;
      toast({ title: 'Thanks — noted', description: 'Your report helps tune how cards are built.' });
      handleOpenChange(false);
    } catch (error) {
      console.error('Error submitting card feedback:', error);
      toast({ title: 'Could not send report', description: 'Please try again in a moment.', variant: 'destructive' });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md" onClick={(e) => e.stopPropagation()}>
        <DialogHeader>
          <DialogTitle className="font-montreal text-[20px] font-medium tracking-[-0.01em] text-[#22262f]">
            What looks wrong with this card?
          </DialogTitle>
          <DialogDescription className="text-[13.5px] text-[#646b76]">
            Tick everything that applies. Reports go straight to the team.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2.5">
          {CARD_FEEDBACK_ISSUES.map(({ code, label }) => {
            const id = `card-feedback-${item.id}-${code}`;
            return (
              <label key={code} htmlFor={id} className="flex cursor-pointer items-start gap-3 rounded-lg px-1 py-1 text-[14px] text-[#22262f] hover:bg-[rgba(109,91,208,0.05)]">
                <Checkbox
                  id={id}
                  checked={issues.includes(code)}
                  onCheckedChange={(checked) => toggle(code, checked === true)}
                  className="mt-0.5"
                />
                <span className="leading-snug">{label}</span>
              </label>
            );
          })}
        </div>

        <Textarea
          aria-label="Anything else?"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Anything else? (optional)"
          rows={3}
          className="min-h-0 resize-none rounded-lg border-0 bg-[rgba(109,91,208,0.05)] px-3 py-2 text-[14px] text-[#22262f] shadow-none focus-visible:bg-[rgba(109,91,208,0.06)] focus-visible:ring-2 focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0"
        />

        <DialogFooter className="gap-2 sm:gap-2">
          <Button type="button" variant="ghost" onClick={() => handleOpenChange(false)} disabled={isSubmitting}>
            Cancel
          </Button>
          <Button
            type="button"
            onClick={handleSubmit}
            disabled={isSubmitting || issues.length === 0 || !user}
            className="rounded-full bg-[#6d5bd0] text-white hover:bg-[#5e4dbd]"
          >
            {isSubmitting ? 'Sending…' : 'Send report'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

export default CardFeedbackDialog;
