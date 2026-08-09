import React from 'react';
import { Type } from 'lucide-react';
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
      <label htmlFor="edit-item-title" className="flex items-center gap-1.5 text-[13px] font-medium text-muted-foreground">
        <Type className="h-3.5 w-3.5" />
        Title
      </label>
      <Input
        id="edit-item-title"
        value={title}
        onChange={(e) => onTitleChange(e.target.value)}
        onKeyDown={handleKeyDown}
        onBlur={handleBlur}
        className="h-auto rounded-xl border-black/10 bg-gray-50/60 py-2 text-xl font-semibold focus-visible:ring-violet-300"
        placeholder="Untitled"
      />
    </div>
  );
};

export default EditItemTitleSection;
