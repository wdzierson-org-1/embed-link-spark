import React, { useState } from 'react';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Checkbox } from '@/components/ui/checkbox';

interface EditItemSupplementalNoteSectionProps {
  supplementalNote: string;
  onSupplementalNoteChange: (note: string) => void;
}

const EditItemSupplementalNoteSection = ({
  supplementalNote,
  onSupplementalNoteChange
}: EditItemSupplementalNoteSectionProps) => {
  const [isChecked, setIsChecked] = useState(!!supplementalNote);

  const handleCheckboxChange = (checked: boolean) => {
    setIsChecked(checked);
    if (!checked) {
      // Clear the note when unchecked
      onSupplementalNoteChange('');
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center space-x-2">
        <Checkbox
          id="add-sticky"
          checked={isChecked}
          onCheckedChange={handleCheckboxChange}
        />
        <Label
          htmlFor="add-sticky"
          className="text-sm font-medium cursor-pointer"
        >
          Add a sticky
        </Label>
      </div>
      
      {isChecked && (
        <div className="space-y-2">
          <Input
            id="supplemental-note"
            value={supplementalNote}
            onChange={(e) => onSupplementalNoteChange(e.target.value)}
            placeholder="Add a quick note..."
            className="bg-yellow-50/50 border-amber-200/40 focus:border-amber-300 focus:ring-amber-200"
          />
          <p className="text-xs text-muted-foreground">
            This note will appear as a yellow sticky note overlay on the card.
          </p>
        </div>
      )}
    </div>
  );
};

export default EditItemSupplementalNoteSection;