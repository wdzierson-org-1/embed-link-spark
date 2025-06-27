
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
      contentLength: contentRef.current?.length,
      hasContent: !!contentRef.current,
      contentPreview: contentRef.current?.slice(0, 100)
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
      
      console.log('Starting debounced server save - ENHANCED LOGGING:', { 
        itemId, 
        updates: {
          title: updates.title?.slice(0, 50),
          description: updates.description?.slice(0, 50),
          contentLength: updates.content?.length,
          hasContent: !!updates.content,
          contentPreview: updates.content?.slice(0, 100)
        }
      });
      
      setSaveStatus('saving');
      
      try {
        console.log('Calling onSave with updates:', {
          itemId,
          updatesKeys: Object.keys(updates),
          contentIncluded: 'content' in updates,
          contentNotEmpty: !!updates.content
        });
        
        await onSave(itemId, updates, { showSuccessToast: false, refreshItems: false });
        
        setSaveStatus('saved');
        setLastSaved(new Date());
        console.log('Debounced server save completed successfully - content should be saved');
      } catch (error) {
        console.error('Debounced server save failed:', error);
        setSaveStatus('idle');
      }
    }, 1000),
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
    
    console.log('debouncedSave called - ENHANCED:', { 
      itemId, 
      updates: {
        title: updates.title?.slice(0, 50),
        description: updates.description?.slice(0, 50),
        contentLength: updates.content?.length,
        hasContent: !!updates.content,
        contentPreview: updates.content?.slice(0, 100)
      },
      refsContent: {
        titleRef: titleRef.current?.slice(0, 50),
        descriptionRef: descriptionRef.current?.slice(0, 50),
        contentRefLength: contentRef.current?.length,
        contentRefPreview: contentRef.current?.slice(0, 100)
      }
    });
    
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
    
    console.log('Flushing pending saves and performing final save - ENHANCED:', { 
      itemId,
      contentLength: contentRef.current?.length,
      hasContent: !!contentRef.current,
      contentPreview: contentRef.current?.slice(0, 100)
    });
    
    // Cancel pending debounced save
    debouncedServerSave.cancel();
    
    // Perform immediate final save with current ref values
    const updates = {
      title: titleRef.current || undefined,
      description: descriptionRef.current || undefined,
      content: contentRef.current || undefined,
    };
    
    console.log('Final save updates - ENHANCED:', {
      title: updates.title?.slice(0, 50),
      description: updates.description?.slice(0, 50),
      contentLength: updates.content?.length,
      hasContent: !!updates.content,
      contentPreview: updates.content?.slice(0, 100)
    });
    
    try {
      console.log('Executing final save to database...');
      await onSave(itemId, updates, { showSuccessToast: false, refreshItems: true });
      console.log('Final save completed successfully - content saved to database');
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
