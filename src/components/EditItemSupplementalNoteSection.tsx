import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Save } from 'lucide-react';

interface EditItemSupplementalNoteSectionProps {
  supplementalNote: string;
  onSupplementalNoteChange: (note: string) => void;
  onSave: (note: string) => Promise<void>;
}

const EditItemSupplementalNoteSection = ({
  supplementalNote,
  onSupplementalNoteChange,
  onSave
}: EditItemSupplementalNoteSectionProps) => {
  const [isSaving, setIsSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [originalNote] = useState(supplementalNote);

  const handleChange = (value: string) => {
    onSupplementalNoteChange(value);
    setHasChanges(value !== originalNote);
  };

  const handleSave = async () => {
    if (!hasChanges) return;
    
    setIsSaving(true);
    try {
      await onSave(supplementalNote);
      setHasChanges(false);
    } catch (error) {
      console.error('Error saving supplemental note:', error);
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <Label htmlFor="supplemental-note" className="text-sm font-medium">
          Supplemental Note (Yellow Sticky)
        </Label>
        {hasChanges && (
          <Button
            onClick={handleSave}
            disabled={isSaving}
            size="sm"
            className="h-6 px-2"
          >
            <Save className="h-3 w-3 mr-1" />
            {isSaving ? 'Saving...' : 'Save'}
          </Button>
        )}
      </div>
      <Textarea
        id="supplemental-note"
        value={supplementalNote}
        onChange={(e) => handleChange(e.target.value)}
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