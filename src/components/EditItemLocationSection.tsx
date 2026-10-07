import React, { useEffect, useRef, useState } from 'react';
import { Input } from '@/components/ui/input';
import { Plus, X } from 'lucide-react';
import type { CapturedLocation, ItemAttributes } from '@/types/itemAttributes';

interface EditItemLocationSectionProps {
  itemId: string;
  attributes?: ItemAttributes;
  onSaveAttributes: (attributes: ItemAttributes) => Promise<void>;
}

/**
 * Shows and edits the item's location (attributes.location). Typing a place by
 * hand records a `manual` location with just the label — coordinates from an
 * earlier device fix are dropped because they no longer describe the typed
 * place. Clearing the field removes the location entirely.
 */
const EditItemLocationSection = ({ itemId, attributes, onSaveAttributes }: EditItemLocationSectionProps) => {
  const [location, setLocation] = useState<CapturedLocation | null>(attributes?.location ?? null);
  const [isEditing, setIsEditing] = useState(false);
  const [draft, setDraft] = useState('');
  // The sheet's item prop freezes while open; after a save this section's
  // local state is the source of truth for what's stored
  const attributesRef = useRef<ItemAttributes>(attributes ?? {});

  useEffect(() => {
    setLocation(attributes?.location ?? null);
    attributesRef.current = attributes ?? {};
    setIsEditing(false);
    // Re-sync only when a different item opens
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [itemId]);

  const startEditing = () => {
    setDraft(location?.label ?? '');
    setIsEditing(true);
  };

  const commit = async (rawValue: string) => {
    const label = rawValue.trim();
    setIsEditing(false);
    if (label === (location?.label ?? '')) return;

    const base = { ...attributesRef.current };
    let next: ItemAttributes;
    if (!label) {
      delete base.location;
      next = base;
      setLocation(null);
    } else {
      const manualLocation: CapturedLocation = {
        label,
        source: 'manual',
        captured_at: new Date().toISOString(),
      };
      next = { ...base, location: manualLocation };
      setLocation(manualLocation);
    }

    attributesRef.current = next;
    try {
      await onSaveAttributes(next);
    } catch (error) {
      console.error('Failed to save location:', error);
    }
  };

  // Rendered as the value side of the Details drawer's "Location" fact row —
  // compact, right-aligned, no chrome beyond the states themselves.
  if (isEditing) {
    return (
      <Input
        autoFocus
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={() => void commit(draft)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            void commit(draft);
          } else if (e.key === 'Escape') {
            e.preventDefault();
            setIsEditing(false);
          }
        }}
        placeholder="e.g. Brooklyn, New York"
        className="h-7 w-52 max-w-full rounded-none border-ink bg-white px-2 text-[14px] md:text-[14px] focus-visible:ring-[3px] focus-visible:ring-spot focus-visible:ring-offset-0"
      />
    );
  }

  if (!location) {
    return (
      <button
        onClick={startEditing}
        className="inline-flex items-center gap-1 text-[14px] text-ink underline-offset-[3px] hover:underline"
      >
        <Plus className="h-3 w-3" />
        Add a location
      </button>
    );
  }

  return (
    <span className="group/location inline-flex max-w-full items-center gap-1.5">
      <button
        onClick={startEditing}
        title="Edit location"
        className="truncate text-ink underline-offset-[3px] hover:underline"
      >
        {location.label}
      </button>
      <button
        onClick={() => void commit('')}
        title="Remove location"
        aria-label="Remove location"
        className="grid h-6 w-6 flex-none place-items-center text-muted-foreground opacity-0 transition-all hover:bg-error hover:text-white focus-visible:opacity-100 group-hover/location:opacity-100"
      >
        <X className="h-3 w-3" />
      </button>
    </span>
  );
};

export default EditItemLocationSection;
