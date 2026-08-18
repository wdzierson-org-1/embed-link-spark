import React, { useEffect, useRef, useState } from 'react';
import { Input } from '@/components/ui/input';
import { MapPin, X } from 'lucide-react';
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

  if (isEditing) {
    return (
      <div className="flex items-center gap-2">
        <MapPin className="h-3.5 w-3.5 flex-none text-muted-foreground" />
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
          className="h-8 rounded-lg border-black/10 bg-gray-50/60 text-sm focus-visible:ring-violet-300"
        />
      </div>
    );
  }

  if (!location) {
    return (
      <button
        onClick={startEditing}
        className="flex items-center gap-1.5 text-[13px] text-muted-foreground/70 transition-colors hover:text-violet-600"
      >
        <MapPin className="h-3.5 w-3.5" />
        Add a location
      </button>
    );
  }

  return (
    <div className="group/location flex items-center gap-1.5 text-[13px] text-muted-foreground">
      <MapPin className="h-3.5 w-3.5 flex-none text-violet-500" />
      <button
        onClick={startEditing}
        title="Edit location"
        className="truncate transition-colors hover:text-violet-600"
      >
        posted from {location.label}
      </button>
      <button
        onClick={() => void commit('')}
        title="Remove location"
        aria-label="Remove location"
        className="grid h-5 w-5 flex-none place-items-center rounded-md text-muted-foreground/50 opacity-0 transition-all hover:bg-red-50 hover:text-red-500 group-hover/location:opacity-100"
      >
        <X className="h-3 w-3" />
      </button>
    </div>
  );
};

export default EditItemLocationSection;
