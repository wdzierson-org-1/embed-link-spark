
import { useState, useEffect, useCallback, useRef } from 'react';

interface DraftData {
  title: string;
  description: string;
  content: string;
  timestamp: number;
}

interface UseLocalStorageDraftProps {
  itemId: string | null;
  isOpen: boolean;
}

export const useLocalStorageDraft = ({ itemId, isOpen }: UseLocalStorageDraftProps) => {
  const [hasDraft, setHasDraft] = useState(false);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const currentDataRef = useRef<Omit<DraftData, 'timestamp'>>({
    title: '',
    description: '',
    content: ''
  });

  const getDraftKey = useCallback((id: string) => `editDraft-${id}`, []);

  // Check for existing draft when sheet opens
  useEffect(() => {
    if (itemId && isOpen) {
      const draftKey = getDraftKey(itemId);
      const savedDraft = localStorage.getItem(draftKey);
      
      if (savedDraft) {
        try {
          const draft: DraftData = JSON.parse(savedDraft);
          // Check if draft is less than 24 hours old
          const isRecentDraft = Date.now() - draft.timestamp < 24 * 60 * 60 * 1000;
          setHasDraft(isRecentDraft);
          
          if (!isRecentDraft) {
            localStorage.removeItem(draftKey);
          }
        } catch (error) {
          console.error('Error parsing draft:', error);
          localStorage.removeItem(draftKey);
        }
      }
    }
  }, [itemId, isOpen, getDraftKey]);

  // Start timed saves when sheet is open
  useEffect(() => {
    if (itemId && isOpen) {
      intervalRef.current = setInterval(() => {
        const draftKey = getDraftKey(itemId);
        const currentData = currentDataRef.current;
        
        // Only save if there's actual content
        if (currentData.title || currentData.description || currentData.content) {
          const draftData: DraftData = {
            ...currentData,
            timestamp: Date.now()
          };
          
          localStorage.setItem(draftKey, JSON.stringify(draftData));
        }
      }, 500); // Save every 500ms
    }

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [itemId, isOpen, getDraftKey]);

  // Update current data reference
  const updateCurrentData = useCallback((title: string, description: string, content: string) => {
    currentDataRef.current = { title, description, content };
  }, []);

  // Get saved draft
  const getSavedDraft = useCallback((): DraftData | null => {
    if (!itemId) return null;
    
    const draftKey = getDraftKey(itemId);
    const savedDraft = localStorage.getItem(draftKey);
    
    if (savedDraft) {
      try {
        return JSON.parse(savedDraft);
      } catch (error) {
        console.error('Error parsing draft:', error);
        localStorage.removeItem(draftKey);
      }
    }
    
    return null;
  }, [itemId, getDraftKey]);

  // Clear draft from localStorage
  const clearDraft = useCallback(() => {
    if (!itemId) return;
    
    const draftKey = getDraftKey(itemId);
    localStorage.removeItem(draftKey);
    setHasDraft(false);
  }, [itemId, getDraftKey]);

  // Clean up old drafts (optional utility)
  const cleanupOldDrafts = useCallback(() => {
    const keys = Object.keys(localStorage);
    const draftKeys = keys.filter(key => key.startsWith('editDraft-'));
    
    draftKeys.forEach(key => {
      try {
        const draft = JSON.parse(localStorage.getItem(key) || '');
        const isOld = Date.now() - draft.timestamp > 24 * 60 * 60 * 1000;
        
        if (isOld) {
          localStorage.removeItem(key);
        }
      } catch (error) {
        // Remove invalid draft entries
        localStorage.removeItem(key);
      }
    });
  }, []);

  return {
    hasDraft,
    updateCurrentData,
    getSavedDraft,
    clearDraft,
    cleanupOldDrafts
  };
};
