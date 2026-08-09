
import { useState, useCallback } from 'react';
import { debounce } from 'lodash';

interface UseEditItemSaveProps {
  onSave: (id: string, updates: { title?: string; description?: string; content?: string; supplemental_note?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  saveToLocalStorage: (itemId: string, data: { title: string; description: string; content: string }) => void;
  titleRef: React.MutableRefObject<string>;
  descriptionRef: React.MutableRefObject<string>;
  contentRef: React.MutableRefObject<string>;
}

// Instant-feel autosave: every change lands in localStorage synchronously (the
// safety copy), the server PATCH trails behind a short debounce, and closing
// the sheet never waits on the network — the draft survives until the final
// save confirms.
export const useEditItemSave = ({
  onSave,
  saveToLocalStorage,
  titleRef,
  descriptionRef,
  contentRef
}: UseEditItemSaveProps) => {
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [lastSaved, setLastSaved] = useState<Date | null>(null);

  const saveToLocalStorageImmediate = useCallback((itemId: string) => {
    if (!itemId) return;

    saveToLocalStorage(itemId, {
      title: titleRef.current,
      description: descriptionRef.current,
      content: contentRef.current
    });
  }, [saveToLocalStorage, titleRef, descriptionRef, contentRef]);

  const debouncedServerSave = useCallback(
    debounce(async (
      itemId: string,
      updates: { title?: string; description?: string; content?: string; supplemental_note?: string }
    ) => {
      if (!itemId) return;

      setSaveStatus('saving');

      try {
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
        setSaveStatus('saved');
        setLastSaved(new Date());
      } catch (error) {
        console.error('Autosave failed:', error);
        setSaveStatus('idle');
      }
    }, 400),
    [onSave]
  );

  const debouncedSave = useCallback((
    itemId: string,
    updates: { title?: string; description?: string; content?: string; supplemental_note?: string }
  ) => {
    if (!itemId) return;

    saveToLocalStorageImmediate(itemId);
    debouncedServerSave(itemId, updates);
  }, [saveToLocalStorageImmediate, debouncedServerSave]);

  const flushAndFinalSave = useCallback(async (itemId: string) => {
    if (!itemId) return;

    debouncedServerSave.cancel();

    const updates = {
      title: titleRef.current || undefined,
      description: descriptionRef.current || undefined,
      content: contentRef.current || undefined,
    };

    try {
      await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
    } catch (error) {
      console.error('Final save failed:', error);
      throw error;
    }
  }, [debouncedServerSave, onSave, titleRef, descriptionRef, contentRef]);

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
