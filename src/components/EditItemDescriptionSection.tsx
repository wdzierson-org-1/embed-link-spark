import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Textarea } from '@/components/ui/textarea';

interface EditItemDescriptionSectionProps {
  description: string;
  onDescriptionChange: (description: string) => void;
  onSave: (description: string) => Promise<void>;
}

const DESCRIPTION_TYPE = 'text-[15px] leading-[1.5] md:text-[15px]';
const DESCRIPTION_BOX = '-mx-2 mt-2.5 w-[calc(100%+16px)] px-2 py-0.5 transition-colors hover:bg-fill';

/**
 * Panel description (DESIGN-v2 §12.8: Montreal 15/1.5 muted, editable like the title). The
 * same two states as the title (Will, 2026-10-10, on reels whose captions run to paragraphs:
 * "ellipsize these at a maximum of three lines … show the full content in an editable
 * control"): at rest a clamped three-line block; a click swaps in an auto-growing textarea
 * with every line, focused with the caret at the end. Blur saves and returns to the clamped
 * view. Enter is a new line here — a description may run to several — so there is no Enter-
 * is-done. The text stays plain (one lane every surface reads), so no slash commands.
 */
const EditItemDescriptionSection = ({ description, onDescriptionChange, onSave }: EditItemDescriptionSectionProps) => {
  const [editing, setEditing] = useState(false);
  const ref = useRef<HTMLTextAreaElement>(null);

  // Size the textarea to its wrapped content before paint, so opening it never flashes a
  // one-line box under a long description
  useLayoutEffect(() => {
    if (!editing) return;
    const el = ref.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight}px`;
  }, [editing, description]);

  useEffect(() => {
    if (!editing) return;
    const el = ref.current;
    if (!el) return;
    el.focus();
    const end = el.value.length;
    el.setSelectionRange(end, end);
  }, [editing]);

  const finish = () => {
    setEditing(false);
    void onSave(description.trim());
  };

  if (!editing) {
    return (
      <button
        type="button"
        aria-label="Edit description"
        onClick={() => setEditing(true)}
        // No display utility here: `line-clamp-3` relies on `display: -webkit-box`
        className={`${DESCRIPTION_BOX} ${DESCRIPTION_TYPE} text-left line-clamp-3 break-words text-muted-foreground focus-visible:bg-fill focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink`}
      >
        {description ? description : <span className="text-muted-foreground/70">Add a description…</span>}
      </button>
    );
  }

  return (
    <Textarea
      id="edit-item-description"
      aria-label="Description"
      ref={ref}
      rows={1}
      value={description}
      onChange={(e) => onDescriptionChange(e.target.value)}
      onBlur={finish}
      placeholder="Add a description…"
      className={`${DESCRIPTION_BOX} ${DESCRIPTION_TYPE} min-h-0 resize-none overflow-hidden rounded-none border border-ink bg-white text-ink shadow-[0_0_0_3px_rgb(var(--spot-rgb))] focus-visible:border-ink focus-visible:bg-white focus-visible:ring-0 focus-visible:ring-offset-0 v2:bg-white v2:focus-visible:ring-0`}
    />
  );
};

export default EditItemDescriptionSection;
