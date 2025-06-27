
import { useEffect } from 'react';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface UseEditItemCloseProps {
  open: boolean;
  itemRef: React.MutableRefObject<ContentItem | null>;
  initialLoadRef: React.MutableRefObject<boolean>;
  titleRef: React.MutableRefObject<string>;
  descriptionRef: React.MutableRefObject<string>;
  contentRef: React.MutableRefObject<string>;
  flushAndFinalSave: (itemId: string) => Promise<void>;
  clearDraft: (itemId: string) => void;
  clearSaveState: () => void;
}

export const useEditItemClose = ({
  open,
  itemRef,
  initialLoadRef,
  titleRef,
  descriptionRef,
  contentRef,
  flushAndFinalSave,
  clearDraft,
  clearSaveState,
}: UseEditItemCloseProps) => {
  
  useEffect(() => {
    if (!open && itemRef.current && !initialLoadRef.current) {
      const performFinalSave = async () => {
        try {
          console.log('Sheet closing - performing final save');
          
          await flushAndFinalSave(itemRef.current!.id);
          
          if (itemRef.current?.id) {
            clearDraft(itemRef.current.id);
          }
          
          console.log('Final save completed');
        } catch (error) {
          console.error('Final save failed:', error);
        }
      };

      // ALWAYS perform final save when sheet closes - even if no text content
      // This ensures that images uploaded without text are saved
      console.log('useEditItemClose: Sheet closed, triggering final save regardless of content', {
        itemId: itemRef.current?.id,
        hasTitle: !!titleRef.current,
        hasDescription: !!descriptionRef.current,
        hasContent: !!contentRef.current,
        contentLength: contentRef.current?.length || 0
      });
      
      if (itemRef.current?.id) {
        performFinalSave();
      }
    }

    if (!open) {
      clearSaveState();
    }
  }, [open, flushAndFinalSave, clearDraft, clearSaveState, titleRef, descriptionRef, contentRef, itemRef, initialLoadRef]);
};
