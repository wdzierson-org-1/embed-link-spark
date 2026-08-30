import React from 'react';
import { Input } from '@/components/ui/input';

interface EditItemTitleSectionProps {
  title: string;
  onTitleChange: (title: string) => void;
  onSave: (title: string) => Promise<void>;
}

/**
 * Panel title (DESIGN.md): weight 500, 28px, -0.02em, inline-editable — no
 * input chrome at rest, violet wash on hover, wash + 2px violet-300 ring on
 * focus. Same autosave contract as before (blur saves, Enter blurs).
 */
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
    <Input
      id="edit-item-title"
      aria-label="Title"
      value={title}
      onChange={(e) => onTitleChange(e.target.value)}
      onKeyDown={handleKeyDown}
      onBlur={handleBlur}
      className="-mx-2 h-auto w-[calc(100%+16px)] rounded-lg border-0 bg-transparent px-2 py-0.5 font-montreal text-[28px] font-medium leading-[1.2] tracking-[-0.02em] text-[#22262f] shadow-none transition-colors hover:bg-[rgba(109,91,208,0.05)] focus-visible:bg-[rgba(109,91,208,0.06)] focus-visible:ring-2 focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0 md:text-[28px]"
      placeholder="Untitled"
    />
  );
};

export default EditItemTitleSection;
