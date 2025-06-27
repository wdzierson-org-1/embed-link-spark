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
