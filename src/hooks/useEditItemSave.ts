
import { useState, useCallback } from 'react';
import { debounce } from 'lodash';

interface UseEditItemSaveProps {
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  saveToLocalStorage: (itemId: string, data: { title: string; description: string; content: string }) => void;
}

export const useEditItemSave = ({ onSave, saveToLocalStorage }: UseEditItemSaveProps) => {
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [lastSaved, setLastSaved] = useState<Date | null>(null);

  // Debounced save function - saves to both localStorage and server
  const debouncedSave = useCallback(
    debounce(async (
      itemId: string, 
      updates: { title?: string; description?: string; content?: string },
      titleRef: React.MutableRefObject<string>,
      descriptionRef: React.MutableRefObject<string>,
      contentRef: React.MutableRefObject<string>
    ) => {
      if (!itemId) return;
      
      setSaveStatus('saving');
      
      try {
        // Save to localStorage first (immediate)
        saveToLocalStorage(itemId, {
          title: titleRef.current,
          description: descriptionRef.current,
          content: contentRef.current
        });

        // Then save to server
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
        
        setSaveStatus('saved');
        setLastSaved(new Date());
      } catch (error) {
        console.error('Debounced save failed:', error);
        setSaveStatus('idle');
      }
    }, 2000), // 2 second delay
    [onSave, saveToLocalStorage]
  );

  // Clear save state when sheet closes
  const clearSaveState = useCallback(() => {
    setSaveStatus('idle');
    setLastSaved(null);
  }, []);

  return {
    saveStatus,
    lastSaved,
    debouncedSave,
    clearSaveState,
  };
};
