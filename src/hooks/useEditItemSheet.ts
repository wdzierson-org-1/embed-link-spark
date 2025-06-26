
import { useState, useEffect, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { generateTitle } from '@/utils/titleGenerator';
import { useLocalStorageDraft } from './useLocalStorageDraft';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface UseEditItemSheetProps {
  open: boolean;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
}

export const useEditItemSheet = ({ open, item, onSave }: UseEditItemSheetProps) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [content, setContent] = useState('');
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [isContentLoading, setIsContentLoading] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  const [editorInstanceKey, setEditorInstanceKey] = useState<string>('');
  const [activeTab, setActiveTab] = useState('details');
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [showDraftRestore, setShowDraftRestore] = useState(false);
  
  const itemRef = useRef(item);
  const initialLoadRef = useRef(false);

  // Use the local storage draft hook
  const {
    hasDraft,
    updateCurrentData,
    getSavedDraft,
    clearDraft,
    cleanupOldDrafts
  } = useLocalStorageDraft({ itemId: item?.id || null, isOpen: open });

  // Update refs when item changes
  useEffect(() => { itemRef.current = item; }, [item]);

  // Clean up old drafts periodically
  useEffect(() => {
    cleanupOldDrafts();
  }, [cleanupOldDrafts]);

  // Update current data in localStorage whenever state changes
  useEffect(() => {
    if (open && item && !isContentLoading) {
      updateCurrentData(title, description, content);
    }
  }, [title, description, content, open, item, isContentLoading, updateCurrentData]);

  // Simple change handlers without auto-save
  const handleTitleChange = useCallback((newTitle: string) => {
    setTitle(newTitle);
  }, []);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    setDescription(newDescription);
  }, []);

  const handleContentChange = useCallback((newContent: string) => {
    setContent(newContent);
  }, []);

  const checkForImage = useCallback(() => {
    if (!item) return;
    
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    } else if (item.type === 'link' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    } else {
      setHasImage(false);
      setImageUrl('');
    }
  }, [item]);

  // Handle draft restoration
  const handleRestoreDraft = useCallback(() => {
    const savedDraft = getSavedDraft();
    if (savedDraft) {
      setTitle(savedDraft.title);
      setDescription(savedDraft.description);
      setContent(savedDraft.content);
    }
    setShowDraftRestore(false);
  }, [getSavedDraft]);

  const handleDiscardDraft = useCallback(() => {
    clearDraft();
    setShowDraftRestore(false);
  }, [clearDraft]);

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      initialLoadRef.current = true;
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorInstanceKey(newKey);
      
      // Set initial values
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      
      // Check for draft after setting initial values
      setTimeout(() => {
        if (hasDraft) {
          setShowDraftRestore(true);
        }
        setIsContentLoading(false);
        initialLoadRef.current = false;
      }, 100);
      
      checkForImage();
    }
  }, [item?.id, open, hasDraft, checkForImage]);

  // Save to server when sheet closes
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      // Save current state to server before closing
      const performFinalSave = async () => {
        setSaveStatus('saving');
        
        try {
          const updates: any = {
            title: title.trim() || undefined,
            description: description.trim() || undefined,
            content: content.trim() || undefined,
          };

          await onSave(itemRef.current!.id, updates, { showSuccessToast: false, refreshItems: true });
          clearDraft(); // Clear localStorage after successful save
          setSaveStatus('saved');
        } catch (error) {
          console.error('Final save failed:', error);
          setSaveStatus('idle');
        }
      };

      // Only save if there are actual changes
      if (title || description || content) {
        performFinalSave();
      } else {
        clearDraft();
      }
    }

    // Clear editor state when sheet closes
    if (!open) {
      setTitle('');
      setDescription('');
      setContent('');
      setHasImage(false);
      setImageUrl('');
      setIsContentLoading(false);
      setEditorKey('');
      setEditorInstanceKey('');
      setActiveTab('details');
      setSaveStatus('idle');
      setShowDraftRestore(false);
    }
  }, [open, title, description, content, onSave, clearDraft]);

  const handleTagsChange = () => {
    // Tags changes are handled separately and don't need local storage
  };

  const handleMediaChange = () => {
    // Media changes are handled separately and don't need local storage
  };

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    
    let finalTitle = newTitle;
    if (!finalTitle && content) {
      try {
        finalTitle = await generateTitle(content, item.type || 'text');
      } catch (error) {
        console.error('Error generating title:', error);
        finalTitle = 'Untitled Note';
      }
    }
    
    setTitle(finalTitle);
    await onSave(item.id, { title: finalTitle });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    await onSave(item.id, { description: newDescription });
  };

  const handleImageStateChange = (newHasImage: boolean, newImageUrl: string) => {
    setHasImage(newHasImage);
    setImageUrl(newImageUrl);
    if (item) {
      setTimeout(() => checkForImage(), 500);
    }
    handleMediaChange();
  };

  return {
    // State
    title,
    description,
    content,
    hasImage,
    imageUrl,
    isContentLoading,
    editorKey,
    activeTab,
    saveStatus,
    showDraftRestore,
    setActiveTab,
    
    // Handlers
    handleTitleChange,
    handleDescriptionChange,
    handleContentChange,
    handleTitleSave,
    handleDescriptionSave,
    handleTagsChange,
    handleMediaChange,
    handleImageStateChange,
    handleRestoreDraft,
    handleDiscardDraft,
  };
};
