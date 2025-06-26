
import { useCallback, useEffect } from 'react';
import { generateTitle } from '@/utils/titleGenerator';
import { useEditItemState } from './useEditItemState';
import { useEditItemDraft } from './useEditItemDraft';
import { useEditItemSave } from './useEditItemSave';
import { useEditItemMedia } from './useEditItemMedia';

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
  // State management
  const {
    title,
    description,
    content,
    isContentLoading,
    editorKey,
    activeTab,
    setActiveTab,
    titleRef,
    descriptionRef,
    contentRef,
    itemRef,
    initialLoadRef,
    setTitle,
    setDescription,
    setContent,
  } = useEditItemState({ open, item });

  // Draft management
  const {
    saveToLocalStorage,
    clearDraft,
  } = useEditItemDraft({ itemId: item?.id || null, open });

  // Save management
  const {
    saveStatus,
    lastSaved,
    debouncedSave,
    clearSaveState,
  } = useEditItemSave({ onSave, saveToLocalStorage });

  // Media management
  const {
    hasImage,
    imageUrl,
    handleImageStateChange,
  } = useEditItemMedia({ item });

  // Handle content changes with debounced save
  const handleTitleChange = useCallback((newTitle: string) => {
    titleRef.current = newTitle;
    setTitle(newTitle);
    
    if (item?.id) {
      debouncedSave(item.id, { 
        title: newTitle.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: contentRef.current.trim() || undefined
      }, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setTitle]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    descriptionRef.current = newDescription;
    setDescription(newDescription);
    
    if (item?.id) {
      debouncedSave(item.id, { 
        title: titleRef.current.trim() || undefined,
        description: newDescription.trim() || undefined,
        content: contentRef.current.trim() || undefined
      }, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setDescription]);

  const handleContentChange = useCallback((newContent: string) => {
    contentRef.current = newContent;
    
    if (item?.id) {
      debouncedSave(item.id, { 
        title: titleRef.current.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: newContent.trim() || undefined
      }, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef]);

  // Save to server when sheet closes (final save)
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      const performFinalSave = async () => {
        try {
          const updates: any = {
            title: titleRef.current.trim() || undefined,
            description: descriptionRef.current.trim() || undefined,
            content: contentRef.current.trim() || undefined,
          };

          await onSave(itemRef.current!.id, updates, { showSuccessToast: false, refreshItems: true });
          
          // Clear localStorage after successful save
          if (itemRef.current?.id) {
            clearDraft(itemRef.current.id);
          }
        } catch (error) {
          console.error('Final save failed:', error);
        }
      };

      // Only save if there are actual changes
      if (titleRef.current || descriptionRef.current || contentRef.current) {
        performFinalSave();
      } else if (itemRef.current?.id) {
        clearDraft(itemRef.current.id);
      }
    }

    // Clear save state when sheet closes
    if (!open) {
      clearSaveState();
    }
  }, [open, onSave, clearDraft, clearSaveState, titleRef, descriptionRef, contentRef, itemRef, initialLoadRef]);

  // Handlers that don't need auto-save
  const handleTagsChange = () => {
    // Tags changes are handled separately and don't need auto-save
  };

  const handleMediaChange = () => {
    // Media changes are handled separately and don't need auto-save
  };

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    
    let finalTitle = newTitle;
    if (!finalTitle && contentRef.current) {
      try {
        finalTitle = await generateTitle(contentRef.current, item.type || 'text');
      } catch (error) {
        console.error('Error generating title:', error);
        finalTitle = 'Untitled Note';
      }
    }
    
    setTitle(finalTitle);
    titleRef.current = finalTitle;
    await onSave(item.id, { title: finalTitle });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    descriptionRef.current = newDescription;
    await onSave(item.id, { description: newDescription });
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
    lastSaved,
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
  };
};
