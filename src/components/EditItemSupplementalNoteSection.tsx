import React from 'react';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';

interface EditItemSupplementalNoteSectionProps {
  supplementalNote: string;
  onSupplementalNoteChange: (note: string) => void;
}

const EditItemSupplementalNoteSection = ({
  supplementalNote,
  onSupplementalNoteChange
}: EditItemSupplementalNoteSectionProps) => {
  return (
    <div className="space-y-2">
      <Label htmlFor="supplemental-note" className="text-sm font-medium">
        Supplemental Note (Yellow Sticky)
      </Label>
      <Textarea
        id="supplemental-note"
        value={supplementalNote}
        onChange={(e) => onSupplementalNoteChange(e.target.value)}
        placeholder="Add a supplemental note that will appear as a yellow sticky on the card..."
        className="min-h-[100px] resize-none"
      />
      <p className="text-xs text-muted-foreground">
        This note will appear as a yellow sticky note overlay on the card.
      </p>
    </div>
  );
};

export default EditItemSupplementalNoteSection;