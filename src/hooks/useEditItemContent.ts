
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
    
    // Update ref immediately
    titleRef.current = newTitle;
    // Update state for UI display
    setTitle(newTitle);
    
    if (item?.id) {
      const updates = { 
        title: newTitle || undefined,
        description: descriptionRef.current || undefined,
        content: contentRef.current || undefined
      };
      
      debouncedSave(item.id, updates);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setTitle]);

  const handleDescriptionChange = useCallback((newDescription: string) => {
    console.log('handleDescriptionChange:', { newDescription: newDescription?.slice(0, 50) });
    
    // Update ref immediately
    descriptionRef.current = newDescription;
    // Update state for UI display
    setDescription(newDescription);
    
    if (item?.id) {
      const updates = { 
        title: titleRef.current || undefined,
        description: newDescription || undefined,
        content: contentRef.current || undefined
      };
      
      debouncedSave(item.id, updates);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef, setDescription]);

  // CRITICAL: This is now called FROM the editor's debounced save, not on every keystroke
  const handleContentChange = useCallback((newContent: string) => {
    console.log('useEditItemContent: handleContentChange (server save):', { 
      contentLength: newContent?.length || 0,
      itemId: item?.id,
      reason: 'Debounced save from editor'
    });
    
    // Update ref immediately
    contentRef.current = newContent;
    // DO NOT update state here - this prevents re-renders that cause focus loss
    
    // Save to server
    if (item?.id) {
      const updates = { 
        title: titleRef.current || undefined,
        description: descriptionRef.current || undefined,
        content: newContent || undefined
      };
      
      console.log('useEditItemContent: Calling debouncedSave for server');
      debouncedSave(item.id, updates);
    }
  }, [item?.id, debouncedSave, titleRef, descriptionRef, contentRef]);

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
