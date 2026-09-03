import React, { useLayoutEffect, useRef } from 'react';
import { Textarea } from '@/components/ui/textarea';

interface EditItemTitleSectionProps {
  title: string;
  onTitleChange: (title: string) => void;
  onSave: (title: string) => Promise<void>;
}

/**
 * Panel title (DESIGN.md): weight 500, 28px, -0.02em, inline-editable — no
 * input chrome at rest, violet wash on hover, wash + 2px violet-300 ring on
 * focus. Rendered as an auto-growing single-value textarea so long titles wrap
 * and show in full instead of clipping at the panel edge (a title is still one
 * line of text: Enter blurs/saves, pasted newlines are flattened). Same
 * autosave contract as before (blur saves).
 */
const EditItemTitleSection = ({ title, onTitleChange, onSave }: EditItemTitleSectionProps) => {
  const ref = useRef<HTMLTextAreaElement>(null);

  // Grow/shrink with the wrapped content (mirrors the description field)
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight}px`;
  }, [title]);

  const handleBlur = () => {
    void onSave(title.trim());
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      e.currentTarget.blur();
    }
  };

  return (
    <Textarea
      id="edit-item-title"
      aria-label="Title"
      ref={ref}
      rows={1}
      value={title}
      onChange={(e) => onTitleChange(e.target.value.replace(/[\r\n]+/g, ' '))}
      onKeyDown={handleKeyDown}
      onBlur={handleBlur}
      className="-mx-2 min-h-0 w-[calc(100%+16px)] resize-none overflow-hidden rounded-lg border-0 bg-transparent px-2 py-0.5 font-montreal text-[28px] font-medium leading-[1.2] tracking-[-0.02em] text-[#22262f] shadow-none transition-colors hover:bg-[rgba(109,91,208,0.05)] focus-visible:bg-[rgba(109,91,208,0.06)] focus-visible:ring-2 focus-visible:ring-[#b6a8ef] focus-visible:ring-offset-0 md:text-[28px]"
      placeholder="Untitled"
    />
  );
};

export default EditItemTitleSection;
