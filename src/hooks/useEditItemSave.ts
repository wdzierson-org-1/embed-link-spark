
import { useState, useCallback } from 'react';
import { debounce } from 'lodash';

interface UseEditItemSaveProps {
  onSave: (id: string, updates: { title?: string; description?: string; content?: string; supplemental_note?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
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
    
    console.log('useEditItemSave: Saving to localStorage:', {
      itemId,
      hasContent: !!contentRef.current,
      contentLength: contentRef.current?.length,
      hasImageInContent: contentRef.current?.includes('"type":"image"'),
      hasTitle: !!titleRef.current,
      hasDescription: !!descriptionRef.current
    });
    
    saveToLocalStorage(itemId, {
      title: titleRef.current,
      description: descriptionRef.current,
      content: contentRef.current
    });
  }, [saveToLocalStorage, titleRef, descriptionRef, contentRef]);

  // ENHANCED: Debounced server save with better image detection logging
  const debouncedServerSave = useCallback(
    debounce(async (
      itemId: string, 
      updates: { title?: string; description?: string; content?: string; supplemental_note?: string }
    ) => {
      if (!itemId) return;
      
      console.log('useEditItemSave: Starting debounced server save:', { 
        itemId, 
        hasContent: !!updates.content,
        contentLength: updates.content?.length,
        hasImageInContent: updates.content?.includes('"type":"image"'),
        hasTitle: !!updates.title,
        hasDescription: !!updates.description,
        timestamp: new Date().toISOString()
      });
      
      setSaveStatus('saving');
      
      try {
        console.log('useEditItemSave: Calling onSave with refreshItems enabled:', {
          itemId,
          updates: {
            hasTitle: !!updates.title,
            hasDescription: !!updates.description,
            hasContent: !!updates.content,
            contentLength: updates.content?.length,
            hasImageInContent: updates.content?.includes('"type":"image"')
          }
        });
        
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: true });
        
        setSaveStatus('saved');
        setLastSaved(new Date());
        console.log('useEditItemSave: Server save completed successfully with UI refresh', {
          itemId,
          timestamp: new Date().toISOString()
        });
      } catch (error) {
        console.error('useEditItemSave: Server save failed:', error);
        setSaveStatus('idle');
      }
    }, 1000),
    [onSave]
  );

  // ENHANCED: Combined save function with improved logging
  const debouncedSave = useCallback((
    itemId: string, 
    updates: { title?: string; description?: string; content?: string; supplemental_note?: string }
  ) => {
    if (!itemId) {
      console.log('useEditItemSave: No save - missing itemId');
      return;
    }
    
    console.log('useEditItemSave: debouncedSave called:', { 
      itemId, 
      hasContent: !!updates.content,
      contentLength: updates.content?.length,
      hasImageInContent: updates.content?.includes('"type":"image"'),
      hasTitle: !!updates.title,
      hasDescription: !!updates.description,
      timestamp: new Date().toISOString()
    });
    
    // Immediate localStorage save
    saveToLocalStorageImmediate(itemId);
    
    // Debounced server save with UI refresh enabled
    console.log('useEditItemSave: Triggering debounced server save with UI refresh');
    debouncedServerSave(itemId, updates);
  }, [saveToLocalStorageImmediate, debouncedServerSave]);

  // ENHANCED: Final save with improved logging
  const flushAndFinalSave = useCallback(async (itemId: string) => {
    if (!itemId) return;
    
    console.log('useEditItemSave: Performing final save:', { 
      itemId,
      hasContent: !!contentRef.current,
      contentLength: contentRef.current?.length,
      hasImageInContent: contentRef.current?.includes('"type":"image"')
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
      console.log('useEditItemSave: Final save completed successfully');
    } catch (error) {
      console.error('useEditItemSave: Final save failed:', error);
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
