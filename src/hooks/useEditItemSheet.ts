
import { useEditItemState } from './useEditItemState';
import { useEditItemDraft } from './useEditItemDraft';
import { useEditItemSave } from './useEditItemSave';
import { useEditItemMedia } from './useEditItemMedia';
import { useEditItemContent } from './useEditItemContent';
import { useEditItemHandlers } from './useEditItemHandlers';
import { useEditItemClose } from './useEditItemClose';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
  supplemental_note?: string;
}

interface UseEditItemSheetProps {
  open: boolean;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string; supplemental_note?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
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

  // Save management - now passing refs
  const {
    saveStatus,
    lastSaved,
    debouncedSave,
    flushAndFinalSave,
    clearSaveState,
  } = useEditItemSave({ 
    onSave, 
    saveToLocalStorage,
    titleRef,
    descriptionRef,
    contentRef
  });

  // Media management
  const {
    hasImage,
    imageUrl,
    handleImageStateChange,
  } = useEditItemMedia({ item });

  // Content handlers
  const {
    handleTitleChange,
    handleDescriptionChange,
    handleContentChange,
    handleTitleSave,
    handleDescriptionSave,
  } = useEditItemContent({
    item,
    titleRef,
    descriptionRef,
    contentRef,
    setTitle,
    setDescription,
    setContent,
    debouncedSave,
    onSave,
  });

  // Other handlers
  const {
    handleTagsChange,
    handleMediaChange,
  } = useEditItemHandlers();

  // Sheet close logic
  useEditItemClose({
    open,
    itemRef,
    initialLoadRef,
    titleRef,
    descriptionRef,
    contentRef,
    flushAndFinalSave,
    clearDraft,
    clearSaveState,
  });

  const handleSupplementalNoteSave = async (note: string) => {
    if (!item?.id) return;
    await onSave(item.id, { supplemental_note: note });
  };

  return {
    title,
    description,
    content,
    supplementalNote: item?.supplemental_note || '',
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
    onSupplementalNoteChange: () => {},
    handleSupplementalNoteSave,
    handleTagsChange,
    handleMediaChange,
    handleImageStateChange,
  };
};
