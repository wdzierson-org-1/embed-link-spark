
import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { debounce } from 'lodash';

interface EditItemUpdates {
  title?: string;
  description?: string;
  content?: string;
  supplemental_note?: string;
}

interface EditableItemSnapshot {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  supplemental_note?: string;
}

interface UseEditItemSaveProps {
  onSave: (id: string, updates: EditItemUpdates, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  saveToLocalStorage: (itemId: string, data: { title: string; description: string; content: string; supplemental_note?: string }) => void;
  titleRef: React.MutableRefObject<string>;
  descriptionRef: React.MutableRefObject<string>;
  contentRef: React.MutableRefObject<string>;
  supplementalNoteRef: React.MutableRefObject<string>;
  itemRef: React.MutableRefObject<EditableItemSnapshot | null>;
}

// Instant-feel autosave: every change lands in localStorage synchronously (the
// safety copy), the server PATCH trails behind a short debounce, and closing
// the sheet never waits on the network — the draft survives until the final
// save confirms. Embedding regeneration is decoupled from all of this (see
// itemOperations), so a "save" is only the PATCH itself.
export const useEditItemSave = ({
  onSave,
  saveToLocalStorage,
  titleRef,
  descriptionRef,
  contentRef,
  supplementalNoteRef,
  itemRef,
}: UseEditItemSaveProps) => {
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [lastSaved, setLastSaved] = useState<Date | null>(null);

  // The debounced function is created once; it reads the latest onSave through
  // a ref so identity churn upstream can't silently reset the debounce timer.
  const onSaveRef = useRef(onSave);
  useEffect(() => {
    onSaveRef.current = onSave;
  }, [onSave]);

  const saveToLocalStorageImmediate = useCallback((itemId: string) => {
    if (!itemId) return;

    saveToLocalStorage(itemId, {
      title: titleRef.current,
      description: descriptionRef.current,
      content: contentRef.current,
      supplemental_note: supplementalNoteRef.current,
    });
  }, [saveToLocalStorage, titleRef, descriptionRef, contentRef, supplementalNoteRef]);

  const debouncedServerSave = useMemo(
    () => debounce(async (itemId: string, updates: EditItemUpdates) => {
      if (!itemId) return;

      setSaveStatus('saving');

      try {
        await onSaveRef.current(itemId, updates, { showSuccessToast: false, refreshItems: false });
        setSaveStatus('saved');
        setLastSaved(new Date());
      } catch (error) {
        console.error('Autosave failed:', error);
        setSaveStatus('idle');
      }
    }, 400),
    []
  );

  useEffect(() => () => debouncedServerSave.cancel(), [debouncedServerSave]);

  const debouncedSave = useCallback((itemId: string, updates: EditItemUpdates) => {
    if (!itemId) return;

    saveToLocalStorageImmediate(itemId);
    debouncedServerSave(itemId, updates);
  }, [saveToLocalStorageImmediate, debouncedServerSave]);

  // Final save on close: send only the fields that actually changed from the
  // opened item — and skip the request entirely when nothing did, so an
  // open-and-close doesn't PATCH or churn the search index.
  const flushAndFinalSave = useCallback(async (itemId: string) => {
    if (!itemId) return;

    debouncedServerSave.cancel();

    const snapshot = itemRef.current;
    const updates: EditItemUpdates = {};

    if (titleRef.current !== (snapshot?.title || '')) updates.title = titleRef.current;
    if (descriptionRef.current !== (snapshot?.description || '')) updates.description = descriptionRef.current;
    if (contentRef.current !== (snapshot?.content || '')) updates.content = contentRef.current;
    if (supplementalNoteRef.current !== (snapshot?.supplemental_note || '')) {
      updates.supplemental_note = supplementalNoteRef.current;
    }

    if (Object.keys(updates).length === 0) return;

    try {
      await onSaveRef.current(itemId, updates, { showSuccessToast: false, refreshItems: false });
    } catch (error) {
      console.error('Final save failed:', error);
      throw error;
    }
  }, [debouncedServerSave, itemRef, titleRef, descriptionRef, contentRef, supplementalNoteRef]);

  const clearSaveState = useCallback(() => {
    setSaveStatus('idle');
    setLastSaved(null);
    debouncedServerSave.cancel();
  }, [debouncedServerSave]);

  return {
    saveStatus,
    lastSaved,
    debouncedSave,
    flushAndFinalSave,
    clearSaveState,
  };
};
