import { useCallback } from 'react';
import { generateTitle } from '@/utils/titleGenerator';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface UseEditItemContentProps {
  item: ContentItem | null;
  titleRef: React.MutableRefObject<string>;
  descriptionRef: React.MutableRefObject<string>;
  contentRef: React.MutableRefObject<string>;
  setTitle: (title: string) => void;
  setDescription: (description: string) => void;
  setContent: (content: string) => void;
  debouncedSave: (itemId: string, updates: { title?: string; description?: string; content?: string }) => void;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
}

export const useEditItemContent = ({
  item,
  titleRef,
  descriptionRef,
  contentRef,
  setTitle,
  setDescription,
  setContent,
  debouncedSave,
  onSave,
}: UseEditItemContentProps) => {
  
  const handleTitleChange = useCallback((newTitle: string) => {
    console.log('handleTitleChange:', { newTitle: newTitle?.slice(0, 50) });
    
    // OPTIMISTIC UPDATE: Update ref and state immediately
    titleRef.current = newTitle;
    setTitle(newTitle);
    
    if (item?.id) {
      const updates = { 
        title: newTitle || undefined,
        description: descriptionRef.current || undefined,
        content: contentRef.current || undefined
      };
      
      console.log('handleTitleChange: Triggering debounced save with UI refresh');
      debouncedSave(item.id, updates);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setTitle]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    console.log('handleDescriptionChange:', { newDescription: newDescription?.slice(0, 50) });
    
    // OPTIMISTIC UPDATE: Update ref and state immediately
    descriptionRef.current = newDescription;
    setDescription(newDescription);
    
    if (item?.id) {
      const updates = { 
        title: titleRef.current || undefined,
        description: newDescription || undefined,
        content: contentRef.current || undefined
      };
      
      console.log('handleDescriptionChange: Triggering debounced save with UI refresh');
      debouncedSave(item.id, updates);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setDescription]);

  const handleContentChange = useCallback((newContent: string) => {
    console.log('useEditItemContent: handleContentChange ENTRY', { 
      contentLength: newContent?.length || 0,
      itemId: item?.id,
      hasNewContent: !!newContent,
      hasItemId: !!item?.id,
      contentPreview: newContent ? newContent.slice(0, 100) + '...' : 'No content',
      timestamp: new Date().toISOString()
    });
    
    // CRITICAL OPTIMISTIC UPDATE: Update ref FIRST, THEN state immediately
    console.log('useEditItemContent: Applying optimistic update to refs and state');
    contentRef.current = newContent;
    setContent(newContent);
    
    console.log('useEditItemContent: Optimistic update complete', {
      contentRefLength: contentRef.current?.length || 0,
      titleRefLength: titleRef.current?.length || 0,
      descriptionRefLength: descriptionRef.current?.length || 0,
      refsMatch: contentRef.current === newContent
    });
    
    // ALWAYS save if we have an item ID - this will now trigger UI refresh
    if (item?.id) {
      const updates = { 
        title: titleRef.current || undefined,
        description: descriptionRef.current || undefined,
        content: newContent || undefined  // Use newContent directly
      };
      
      console.log('useEditItemContent: Calling debouncedSave with UI refresh enabled', {
        itemId: item.id,
        hasContent: !!updates.content,
        contentLength: updates.content?.length || 0,
        hasTitle: !!updates.title,
        hasDescription: !!updates.description,
        updatePreview: updates.content ? updates.content.slice(0, 100) + '...' : 'No content'
      });
      
      debouncedSave(item.id, updates);
      
      console.log('useEditItemContent: debouncedSave called successfully - UI will refresh after save');
    } else {
      console.log('useEditItemContent: No save - missing item ID', {
        hasItem: !!item,
        itemId: item?.id
      });
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setContent]);

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
    handleTitleChange,
    handleDescriptionChange,
    handleContentChange,
    handleTitleSave,
    handleDescriptionSave,
  };
};
