
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
    
    titleRef.current = newTitle;
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
    
    descriptionRef.current = newDescription;
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

  const handleContentChange = useCallback((newContent: string) => {
    console.log('handleContentChange:', { 
      contentLength: newContent?.length,
      itemId: item?.id,
      hasNewContent: !!newContent
    });
    
    contentRef.current = newContent;
    setContent(newContent);
    
    if (item?.id && newContent) {
      const updates = { 
        title: titleRef.current || undefined,
        description: descriptionRef.current || undefined,
        content: newContent
      };
      
      console.log('Calling debouncedSave with content:', {
        itemId: item.id,
        hasContent: !!updates.content,
        contentLength: updates.content?.length
      });
      
      debouncedSave(item.id, updates);
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
