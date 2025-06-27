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

  // Handle content changes - SIMPLIFIED to mirror TextNoteTab
  const handleTitleChange = useCallback((newTitle: string) => {
    console.log('handleTitleChange:', { newTitle: newTitle?.slice(0, 50) });
    
    titleRef.current = newTitle;
    setTitle(newTitle);
    
    if (item?.id) {
      const updates = { 
        title: newTitle || undefined,
        description: descriptionRef.current || undefined,
        content: contentRef.current || undefined
      };
      
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setTitle]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    console.log('handleDescriptionChange:', { newDescription: newDescription?.slice(0, 50) });
    
    descriptionRef.current = newDescription;
    setDescription(newDescription);
    
    if (item?.id) {
      const updates = { 
        title: titleRef.current || undefined,
        description: newDescription || undefined,
        content: contentRef.current || undefined
      };
      
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setDescription]);

  // SIMPLIFIED content change handler - mirror TextNoteTab approach
  const handleContentChange = useCallback((newContent: string) => {
    console.log('handleContentChange - SIMPLIFIED:', { 
      contentLength: newContent?.length,
      itemId: item?.id,
      hasNewContent: !!newContent
    });
    
    // Direct content update like TextNoteTab - no complex validation
    contentRef.current = newContent;
    setContent(newContent);
    
    console.log('Content updated in state and ref');
    
    if (item?.id && newContent) {
      const updates = { 
        title: titleRef.current || undefined,
        description: descriptionRef.current || undefined,
        content: newContent // Direct JSON content like TextNoteTab
      };
      
      console.log('Calling debouncedSave with content:', {
        itemId: item.id,
        hasContent: !!updates.content,
        contentLength: updates.content?.length
      });
      
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setContent]);

  // Final save when sheet closes - SIMPLIFIED
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      const performFinalSave = async () => {
        try {
          console.log('Sheet closing - performing final save');
          
          await flushAndFinalSave(
            itemRef.current!.id,
            titleRef,
            descriptionRef,
            contentRef
          );
          
          if (itemRef.current?.id) {
            clearDraft(itemRef.current.id);
          }
          
          console.log('Final save completed');
        } catch (error) {
          console.error('Final save failed:', error);
        }
      };

      // Perform final save if we have any content
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
