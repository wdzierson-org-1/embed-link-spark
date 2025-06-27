
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
};
