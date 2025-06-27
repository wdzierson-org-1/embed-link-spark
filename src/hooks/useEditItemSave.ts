
import { useState, useCallback } from 'react';
import { debounce } from 'lodash';

interface UseEditItemSaveProps {
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  saveToLocalStorage: (itemId: string, data: { title: string; description: string; content: string }) => void;
}

export const useEditItemSave = ({ onSave, saveToLocalStorage }: UseEditItemSaveProps) => {
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [lastSaved, setLastSaved] = useState<Date | null>(null);

  // Immediate localStorage save function
  const saveToLocalStorageImmediate = useCallback((
    itemId: string,
    titleRef: React.MutableRefObject<string>,
    descriptionRef: React.MutableRefObject<string>,
    contentRef: React.MutableRefObject<string>
  ) => {
    if (!itemId) return;
    
    console.log('Saving to localStorage immediately:', {
      itemId,
      title: titleRef.current?.slice(0, 50),
      description: descriptionRef.current?.slice(0, 50),
      content: contentRef.current?.slice(0, 50)
    });
    
    saveToLocalStorage(itemId, {
      title: titleRef.current,
      description: descriptionRef.current,
      content: contentRef.current
    });
  }, [saveToLocalStorage]);

  // Debounced server save function - reduced to 1 second
  const debouncedServerSave = useCallback(
    debounce(async (
      itemId: string, 
      updates: { title?: string; description?: string; content?: string }
    ) => {
      if (!itemId) return;
      
      console.log('Starting debounced server save:', { itemId, updates });
      setSaveStatus('saving');
      
      try {
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
        
        setSaveStatus('saved');
        setLastSaved(new Date());
        console.log('Debounced server save completed successfully');
      } catch (error) {
        console.error('Debounced server save failed:', error);
        setSaveStatus('idle');
      }
    }, 1000), // Reduced from 2 seconds to 1 second
    [onSave]
  );

  // Combined save function that handles both immediate localStorage and debounced server save
  const debouncedSave = useCallback((
    itemId: string, 
    updates: { title?: string; description?: string; content?: string },
    titleRef: React.MutableRefObject<string>,
    descriptionRef: React.MutableRefObject<string>,
    contentRef: React.MutableRefObject<string>
  ) => {
    if (!itemId) return;
    
    console.log('debouncedSave called with:', { itemId, updates });
    
    // Immediate localStorage save
    saveToLocalStorageImmediate(itemId, titleRef, descriptionRef, contentRef);
    
    // Debounced server save
    debouncedServerSave(itemId, updates);
  }, [saveToLocalStorageImmediate, debouncedServerSave]);

  // Force flush any pending saves and perform final save
  const flushAndFinalSave = useCallback(async (
    itemId: string,
    titleRef: React.MutableRefObject<string>,
    descriptionRef: React.MutableRefObject<string>,
    contentRef: React.MutableRefObject<string>
  ) => {
    if (!itemId) return;
    
    console.log('Flushing pending saves and performing final save:', { itemId });
    
    // Cancel pending debounced save
    debouncedServerSave.cancel();
    
    // Perform immediate final save with current ref values
    const updates = {
      title: titleRef.current?.trim() || undefined,
      description: descriptionRef.current?.trim() || undefined,
      content: contentRef.current?.trim() || undefined,
    };
    
    console.log('Final save updates:', updates);
    
    try {
      await onSave(itemId, updates, { showSuccessToast: false, refreshItems: true });
      console.log('Final save completed successfully');
    } catch (error) {
      console.error('Final save failed:', error);
      throw error;
    }
  }, [debouncedServerSave, onSave]);

  // Clear save state when sheet closes
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
