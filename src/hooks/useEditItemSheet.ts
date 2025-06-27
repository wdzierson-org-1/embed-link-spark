
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
    flushAndFinalSave,
    clearSaveState,
  } = useEditItemSave({ onSave, saveToLocalStorage });

  // Media management
  const {
    hasImage,
    imageUrl,
    handleImageStateChange,
  } = useEditItemMedia({ item });

  // Handle content changes with improved synchronization
  const handleTitleChange = useCallback((newTitle: string) => {
    console.log('handleTitleChange called:', { newTitle: newTitle?.slice(0, 50) });
    
    // Update both state and ref synchronously
    titleRef.current = newTitle;
    setTitle(newTitle);
    
    if (item?.id) {
      const updates = { 
        title: newTitle.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: contentRef.current.trim() || undefined
      };
      
      console.log('Calling debouncedSave from handleTitleChange:', updates);
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setTitle]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    console.log('handleDescriptionChange called:', { newDescription: newDescription?.slice(0, 50) });
    
    // Update both state and ref synchronously
    descriptionRef.current = newDescription;
    setDescription(newDescription);
    
    if (item?.id) {
      const updates = { 
        title: titleRef.current.trim() || undefined,
        description: newDescription.trim() || undefined,
        content: contentRef.current.trim() || undefined
      };
      
      console.log('Calling debouncedSave from handleDescriptionChange:', updates);
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setDescription]);

  const handleContentChange = useCallback((newContent: string) => {
    console.log('handleContentChange called:', { 
      newContent: newContent?.slice(0, 100),
      contentLength: newContent?.length 
    });
    
    // Validate content - don't save empty content if we had content before
    if (!newContent?.trim() && contentRef.current?.trim()) {
      console.warn('Ignoring empty content update when we have existing content');
      return;
    }
    
    // Update both state and ref synchronously
    contentRef.current = newContent;
    setContent(newContent);
    
    if (item?.id) {
      const updates = { 
        title: titleRef.current.trim() || undefined,
        description: descriptionRef.current.trim() || undefined,
        content: newContent.trim() || undefined
      };
      
      console.log('Calling debouncedSave from handleContentChange:', updates);
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setContent]);

  // Enhanced final save when sheet closes
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      const performFinalSave = async () => {
        try {
          console.log('Sheet closing, performing final save for item:', itemRef.current?.id);
          
          await flushAndFinalSave(
            itemRef.current!.id,
            titleRef,
            descriptionRef,
            contentRef
          );
          
          if (itemRef.current?.id) {
            clearDraft(itemRef.current.id);
          }
          
          console.log('Final save completed successfully');
        } catch (error) {
          console.error('Final save failed:', error);
        }
      };

      // Only perform final save if we have any content
      if (titleRef.current || descriptionRef.current || contentRef.current) {
        performFinalSave();
      } else if (itemRef.current?.id) {
        clearDraft(itemRef.current.id);
      }
    }

    if (!open) {
      clearSaveState();
    }
  }, [open, flushAndFinalSave, clearDraft, clearSaveState, titleRef, descriptionRef, contentRef, itemRef, initialLoadRef]);

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
    await onSave(item.id, { title: finalTitle }, { showSuccessToast: false });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    descriptionRef.current = newDescription;
    await onSave(item.id, { description: newDescription }, { showSuccessToast: false });
  };

  return {
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
