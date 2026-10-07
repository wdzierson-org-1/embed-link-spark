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
          Add a sticky note
        </Label>
      </div>
      
      {isChecked && (
        <div className="space-y-2">
          <Input
            id="supplemental-note"
            value={supplementalNote}
            onChange={(e) => onSupplementalNoteChange(e.target.value)}
            placeholder="Add a quick note…"
            className="italic"
          />
          <p className="text-[13px] text-muted-foreground">
            It shows as a note pinned to the card on your public feed.
          </p>
        </div>
      )}
    </div>
  );
};

export default EditItemSupplementalNoteSection;