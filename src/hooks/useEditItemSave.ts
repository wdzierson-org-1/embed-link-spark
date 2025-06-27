
import { useState, useCallback } from 'react';
import { debounce } from 'lodash';

interface UseEditItemSaveProps {
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  saveToLocalStorage: (itemId: string, data: { title: string; description: string; content: string }) => void;
  titleRef: React.MutableRefObject<string>;
  descriptionRef: React.MutableRefObject<string>;
  contentRef: React.MutableRefObject<string>;
}

export const useEditItemSave = ({ 
  onSave, 
  saveToLocalStorage, 
  titleRef, 
  descriptionRef, 
  contentRef 
}: UseEditItemSaveProps) => {
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [lastSaved, setLastSaved] = useState<Date | null>(null);

  // Immediate localStorage save function
  const saveToLocalStorageImmediate = useCallback((itemId: string) => {
    if (!itemId) return;
    
    console.log('Saving to localStorage:', {
      itemId,
      hasContent: !!contentRef.current,
      contentLength: contentRef.current?.length
    });
    
    saveToLocalStorage(itemId, {
      title: titleRef.current,
      description: descriptionRef.current,
      content: contentRef.current
    });
  }, [saveToLocalStorage, titleRef, descriptionRef, contentRef]);

  // SIMPLIFIED debounced server save - mirror TextNoteTab approach
  const debouncedServerSave = useCallback(
    debounce(async (
      itemId: string, 
      updates: { title?: string; description?: string; content?: string }
    ) => {
      if (!itemId) return;
      
      console.log('Starting server save:', { 
        itemId, 
        hasContent: !!updates.content,
        contentLength: updates.content?.length
      });
      
      setSaveStatus('saving');
      
      try {
        // Direct save like TextNoteTab - no complex validation
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
        
        setSaveStatus('saved');
        setLastSaved(new Date());
        console.log('Server save completed successfully');
      } catch (error) {
        console.error('Server save failed:', error);
        setSaveStatus('idle');
      }
    }, 1000),
    [onSave]
  );

  // SIMPLIFIED combined save function
  const debouncedSave = useCallback((
    itemId: string, 
    updates: { title?: string; description?: string; content?: string }
  ) => {
    if (!itemId) return;
    
    console.log('debouncedSave called:', { 
      itemId, 
      hasContent: !!updates.content,
      contentLength: updates.content?.length
    });
    
    // Immediate localStorage save
    saveToLocalStorageImmediate(itemId);
    
    // Debounced server save
    debouncedServerSave(itemId, updates);
  }, [saveToLocalStorageImmediate, debouncedServerSave]);

  // SIMPLIFIED final save
  const flushAndFinalSave = useCallback(async (itemId: string) => {
    if (!itemId) return;
    
    console.log('Performing final save:', { 
      itemId,
      hasContent: !!contentRef.current,
      contentLength: contentRef.current?.length
    });
    
    // Cancel pending debounced save
    debouncedServerSave.cancel();
    
    // Perform immediate final save with current ref values
    const updates = {
      title: titleRef.current || undefined,
      description: descriptionRef.current || undefined,
      content: contentRef.current || undefined,
    };
    
    try {
      await onSave(itemId, updates, { showSuccessToast: false, refreshItems: true });
      console.log('Final save completed successfully');
    } catch (error) {
      console.error('Final save failed:', error);
      throw error;
    }
  }, [debouncedServerSave, onSave, titleRef, descriptionRef, contentRef]);

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
