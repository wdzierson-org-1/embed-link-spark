
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

// Helper function to validate JSON content from Novel editor
const isValidNovelContent = (content: string): boolean => {
  if (!content) return false;
  
  try {
    const parsed = JSON.parse(content);
    // Check if it's a valid Novel/TipTap JSON structure
    return parsed && typeof parsed === 'object' && parsed.type;
  } catch {
    return false;
  }
};

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
        title: newTitle || undefined,
        description: descriptionRef.current || undefined,
        content: contentRef.current || undefined
      };
      
      console.log('Calling debouncedSave from handleTitleChange:', {
        title: updates.title?.slice(0, 50),
        description: updates.description?.slice(0, 50),
        hasContent: !!updates.content,
        contentLength: updates.content?.length
      });
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
        title: titleRef.current || undefined,
        description: newDescription || undefined,
        content: contentRef.current || undefined
      };
      
      console.log('Calling debouncedSave from handleDescriptionChange:', {
        title: updates.title?.slice(0, 50),
        description: updates.description?.slice(0, 50),
        hasContent: !!updates.content,
        contentLength: updates.content?.length
      });
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setDescription]);

  const handleContentChange = useCallback((newContent: string) => {
    console.log('handleContentChange called - FIXED VERSION:', { 
      newContent: newContent?.slice(0, 100),
      contentLength: newContent?.length,
      itemId: item?.id,
      isValidJSON: isValidNovelContent(newContent),
      contentRef: contentRef.current?.slice(0, 50)
    });
    
    // Accept any non-empty content - removed overly restrictive validation
    if (!newContent) {
      console.log('handleContentChange: Empty content received, skipping update');
      return;
    }

    console.log('handleContentChange: Content validation passed, proceeding with update');
    
    // Check if content actually changed to prevent unnecessary updates
    if (newContent === contentRef.current) {
      console.log('handleContentChange: Content unchanged, skipping update');
      return;
    }
    
    // Update both state and ref synchronously - CRITICAL FIX
    contentRef.current = newContent;
    setContent(newContent);
    
    console.log('handleContentChange: Content updated in refs and state:', {
      refContent: contentRef.current?.slice(0, 100),
      stateContentLength: newContent.length
    });
    
    if (item?.id) {
      const updates = { 
        title: titleRef.current || undefined,
        description: descriptionRef.current || undefined,
        content: newContent // Keep the full JSON content
      };
      
      console.log('handleContentChange: Calling debouncedSave with updates:', {
        itemId: item.id,
        hasTitle: !!updates.title,
        hasDescription: !!updates.description,
        hasContent: !!updates.content,
        contentLength: updates.content?.length,
        contentPreview: updates.content?.slice(0, 100)
      });
      
      debouncedSave(item.id, updates, titleRef, descriptionRef, contentRef);
    } else {
      console.warn('handleContentChange: No item.id available for save');
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setContent]);

  // Enhanced final save when sheet closes
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      const performFinalSave = async () => {
        try {
          console.log('Sheet closing, performing final save for item:', itemRef.current?.id);
          console.log('Final save content check:', {
            title: titleRef.current?.slice(0, 50),
            description: descriptionRef.current?.slice(0, 50),
            contentLength: contentRef.current?.length,
            hasContent: !!contentRef.current,
            contentPreview: contentRef.current?.slice(0, 100)
          });
          
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

      // Perform final save if we have any content
      if (titleRef.current || descriptionRef.current || contentRef.current) {
        console.log('Triggering final save with content:', {
          hasTitle: !!titleRef.current,
          hasDescription: !!descriptionRef.current,
          hasContent: !!contentRef.current
        });
        performFinalSave();
      } else if (itemRef.current?.id) {
        console.log('No content to save, just clearing draft');
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
