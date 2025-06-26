
import { useState, useEffect, useCallback } from 'react';

interface UseEditItemDraftProps {
  itemId: string | null;
  open: boolean;
}

export const useEditItemDraft = ({ itemId, open }: UseEditItemDraftProps) => {
  const [showDraftRestore, setShowDraftRestore] = useState(false);

  // Local storage draft management
  const getDraftKey = useCallback((id: string) => `editDraft-${id}`, []);

  const saveToLocalStorage = useCallback((itemId: string, data: { title: string; description: string; content: string }) => {
    const draftKey = getDraftKey(itemId);
    const draftData = {
      ...data,
      timestamp: Date.now()
    };
    localStorage.setItem(draftKey, JSON.stringify(draftData));
  }, [getDraftKey]);

  const clearDraft = useCallback((itemId: string) => {
    const draftKey = getDraftKey(itemId);
    localStorage.removeItem(draftKey);
  }, [getDraftKey]);

  // Check for existing draft when sheet opens
  useEffect(() => {
    if (itemId && open) {
      const draftKey = getDraftKey(itemId);
      const savedDraft = localStorage.getItem(draftKey);
      
      if (savedDraft) {
        try {
          const draft = JSON.parse(savedDraft);
          // Check if draft is less than 24 hours old
          const isRecentDraft = Date.now() - draft.timestamp < 24 * 60 * 60 * 1000;
          
          if (isRecentDraft) {
            setShowDraftRestore(true);
          } else {
            localStorage.removeItem(draftKey);
          }
        } catch (error) {
          console.error('Error parsing draft:', error);
          localStorage.removeItem(draftKey);
        }
      }
    }
  }, [itemId, open, getDraftKey]);

  const handleRestoreDraft = useCallback((
    setTitle: (title: string) => void,
    setDescription: (description: string) => void,
    setContent: (content: string) => void,
    titleRef: React.MutableRefObject<string>,
    descriptionRef: React.MutableRefObject<string>,
    contentRef: React.MutableRefObject<string>
  ) => {
    if (!itemId) return;
    
    const draftKey = getDraftKey(itemId);
    const savedDraft = localStorage.getItem(draftKey);
    
    if (savedDraft) {
      try {
        const draft = JSON.parse(savedDraft);
        
        // Update both state and refs
        setTitle(draft.title);
        setDescription(draft.description);
        setContent(draft.content);
        
        titleRef.current = draft.title;
        descriptionRef.current = draft.description;
        contentRef.current = draft.content;
      } catch (error) {
        console.error('Error restoring draft:', error);
      }
    }
    setShowDraftRestore(false);
  }, [itemId, getDraftKey]);

  const handleDiscardDraft = useCallback(() => {
    if (itemId) {
      clearDraft(itemId);
    }
    setShowDraftRestore(false);
  }, [itemId, clearDraft]);

  // Clear draft restore state when sheet closes
  useEffect(() => {
    if (!open) {
      setShowDraftRestore(false);
    }
  }, [open]);

  return {
    showDraftRestore,
    saveToLocalStorage,
    clearDraft,
    handleRestoreDraft,
    handleDiscardDraft,
  };
};
