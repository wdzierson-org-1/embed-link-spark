import React from 'react';
import { Input } from '@/components/ui/input';

interface EditItemTitleSectionProps {
  title: string;
  onTitleChange: (title: string) => void;
  onSave: (title: string) => Promise<void>;
}

const EditItemTitleSection = ({ title, onTitleChange, onSave }: EditItemTitleSectionProps) => {
  const handleBlur = () => {
    void onSave(title.trim());
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      (e.target as HTMLInputElement).blur();
    }
  };

  return (
    <div className="space-y-1.5">
      <label htmlFor="edit-item-title" className="text-sm text-muted-foreground">
        Title
      </label>
      <Input
        id="edit-item-title"
        value={title}
        onChange={(e) => onTitleChange(e.target.value)}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="text-xl font-semibold h-auto py-2"
        placeholder="Untitled"
      />
    </div>
  );
};

export default EditItemTitleSection;
