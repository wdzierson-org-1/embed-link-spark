import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Textarea } from '@/components/ui/textarea';

interface EditItemTitleSectionProps {
  title: string;
  onTitleChange: (title: string) => void;
  onSave: (title: string) => Promise<void>;
}

const TITLE_TYPE =
  'font-montreal text-[28px] font-medium leading-[1.12] tracking-[-0.03em] text-ink md:text-[28px]';
const TITLE_BOX =
  '-mx-2 w-[calc(100%+16px)] px-2 py-0.5 transition-colors hover:bg-fill';

/**
 * Panel title (DESIGN-v2 screen title: Montreal 500, 28px, -0.03em), inline-editable: no
 * input chrome at rest, the soft fill on hover; editing, a white box with an ink edge and the
 * spot ring, like every place the person writes.
 *
 * Two states (ui-changes.md 2026-09-03; three lines since 2026-10-10): at rest the title is
 * a clamped three-line block with an ellipsis (the full text sits in the tooltip);
 * clicking it swaps in an auto-growing textarea showing every line, focused
 * with the caret at the end. Blur saves the trimmed title and returns to the
 * clamped view; Enter is "done" (a title is one line — pasted newlines are
 * flattened to spaces).
 */
const EditItemTitleSection = ({ title, onTitleChange, onSave }: EditItemTitleSectionProps) => {
  const [editing, setEditing] = useState(false);
  const ref = useRef<HTMLTextAreaElement>(null);

  // Size the textarea to its wrapped content before paint, so opening the
  // editor never flashes a one-line box under a multi-line title
  useLayoutEffect(() => {
    if (!editing) return;
    const el = ref.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${el.scrollHeight}px`;
  }, [editing, title]);

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
    void onSave(title.trim());
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      e.currentTarget.blur();
    }
  };

  if (!editing) {
    return (
      <button
        type="button"
        aria-label="Edit title"
        title={title}
        onClick={() => setEditing(true)}
        // No display utility here: `line-clamp-3` relies on `display: -webkit-box`,
        // and `block`/`flex` would override it and defeat the clamp
        className={`${TITLE_BOX} ${TITLE_TYPE} text-left line-clamp-3 break-words focus-visible:bg-fill focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ink`}
      >
        {title ? title : <span className="text-muted-foreground">Untitled</span>}
      </button>
    );
  }

  return (
    <Textarea
      id="edit-item-title"
      aria-label="Title"
      ref={ref}
      rows={1}
      value={title}
      onChange={(e) => onTitleChange(e.target.value.replace(/[\r\n]+/g, ' '))}
      onKeyDown={handleKeyDown}
      onBlur={finish}
      className={`${TITLE_BOX} ${TITLE_TYPE} min-h-0 resize-none overflow-hidden rounded-none border border-ink bg-white shadow-[0_0_0_3px_rgb(var(--spot-rgb))] focus-visible:border-ink focus-visible:bg-white focus-visible:ring-0 focus-visible:ring-offset-0 v2:focus-visible:ring-0`}
      placeholder="Untitled"
    />
  );
};

export default EditItemTitleSection;
