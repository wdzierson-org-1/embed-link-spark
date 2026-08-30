
import React from 'react';
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet';
import { Tabs } from '@/components/ui/tabs';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Trash2 } from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import EditItemTabNavigation from '@/components/EditItemTabNavigation';
import EditItemDetailsTab from '@/components/EditItemDetailsTab';
import EditItemImageTab from '@/components/EditItemImageTab';
import EditItemAutoSaveIndicator from '@/components/EditItemAutoSaveIndicator';
import { useEditItemSheet } from '@/hooks/useEditItemSheet';
import { useIsMobile } from '@/hooks/use-mobile';
import { isDocumentProcessing } from '@/utils/documentProcessing';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  mime_type?: string;
  type?: string;
  tags?: string[];
  is_public?: boolean;
  summary?: string;
  attributes?: ItemAttributes;
}

interface EditItemSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string; supplemental_note?: string; is_public?: boolean; file_path?: string | null; attributes?: ItemAttributes }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  onDelete?: (id: string) => void;
}

const EditItemSheet = ({ open, onOpenChange, item, onSave, onDelete }: EditItemSheetProps) => {
  const isMobile = useIsMobile();

  const isProcessing = item ? isDocumentProcessing(item) : false;

  // Prevent opening if processing
  React.useEffect(() => {
    if (open && isProcessing) {
      onOpenChange(false);
    }
  }, [open, isProcessing, onOpenChange]);

  const {
    title,
    description,
    content,
    supplementalNote,
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
    handleSupplementalNoteChange,
    handleTitleSave,
    handleDescriptionSave,
    handleTagsChange,
    handleMediaChange,
    handleImageStateChange,
    handlePublicToggle,
  } = useEditItemSheet({ open, item, onSave });

  const handleImageChange = async (filePath: string | null) => {
    if (!item) return;
    await onSave(item.id, { file_path: filePath }, { showSuccessToast: false, refreshItems: true });
  };

  const handleAttributesSave = async (attributes: ItemAttributes) => {
    if (!item) return;
    await onSave(item.id, { attributes }, { showSuccessToast: false, refreshItems: true });
  };

  const handleConfirmDelete = () => {
    if (!item || !onDelete) return;
    onOpenChange(false);
    onDelete(item.id);
  };

  const footer = (
    <div className="flex flex-shrink-0 items-center justify-between border-t border-black/[0.07] bg-white/65 px-6 py-2.5 sm:px-10">
      {onDelete ? (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <button className="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-[13px] text-[#c93a3a] transition-opacity hover:opacity-75">
              <Trash2 className="h-3.5 w-3.5" />
              Delete item
            </button>
          </AlertDialogTrigger>
          <AlertDialogContent className="rounded-2xl">
            <AlertDialogHeader>
              <AlertDialogTitle>Delete this item?</AlertDialogTitle>
              <AlertDialogDescription>
                "{item?.title || 'Untitled'}" and everything Stash knows about it will be removed. This can't be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={handleConfirmDelete} className="bg-red-600 hover:bg-red-700">
                Delete
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      ) : <span />}
      <EditItemAutoSaveIndicator saveStatus={saveStatus} lastSaved={lastSaved} />
    </div>
  );

  const detailsTabProps = {
    item,
    title,
    description,
    content,
    isContentLoading,
    editorKey,
    onTitleChange: handleTitleChange,
    onDescriptionChange: handleDescriptionChange,
    onContentChange: handleContentChange,
    onTitleSave: handleTitleSave,
    onDescriptionSave: handleDescriptionSave,
    onTagsChange: handleTagsChange,
    onMediaChange: handleMediaChange,
    supplementalNote,
    onSupplementalNoteChange: handleSupplementalNoteChange,
    onPublicToggle: handlePublicToggle,
    onImageChange: handleImageChange,
    onAttributesSave: handleAttributesSave,
    isMobile,
  };

  // For image items or links with images, show inline without tabs
  if (item?.type === 'image' || (item?.type === 'link' && hasImage)) {
    return (
      <TooltipProvider>
        <Sheet open={open} onOpenChange={onOpenChange}>
          <SheetContent className="w-full h-full sm:w-[800px] sm:max-w-[800px] sm:h-auto p-0 flex flex-col bg-gradient-to-b from-white to-[#f8f8fa] shadow-[0_2px_6px_rgba(20,22,30,0.05),0_24px_70px_rgba(30,33,44,0.16)]">
            <SheetTitle className="sr-only">Edit item</SheetTitle>
            <div className="flex-1 overflow-y-auto pt-12">
              <EditItemDetailsTab
                {...detailsTabProps}
                isInsideTabs={false}
                showInlineImage={true}
                imageUrl={imageUrl}
              />
            </div>
            {footer}
          </SheetContent>
        </Sheet>
      </TooltipProvider>
    );
  }

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-full h-full sm:w-[800px] sm:max-w-[800px] sm:h-auto p-0 flex flex-col bg-gradient-to-b from-white to-[#f8f8fa] shadow-[0_2px_6px_rgba(20,22,30,0.05),0_24px_70px_rgba(30,33,44,0.16)]">
          <SheetTitle className="sr-only">Edit item</SheetTitle>
          <div className="flex-1 overflow-y-auto">
            {hasImage ? (
              <Tabs value={activeTab} onValueChange={setActiveTab} className="h-full">
                <div className="px-6 py-4">
                  <EditItemTabNavigation hasImage={hasImage} />
                </div>

                <EditItemDetailsTab {...detailsTabProps} isInsideTabs={true} />

                <EditItemImageTab
                  item={item}
                  hasImage={hasImage}
                  imageUrl={imageUrl}
                  onImageStateChange={handleImageStateChange}
                />
              </Tabs>
            ) : (
              // Render details directly without tabs when no image
              <div className="pt-12">
                <EditItemDetailsTab {...detailsTabProps} isInsideTabs={false} />
              </div>
            )}
          </div>
          {footer}
        </SheetContent>
      </Sheet>
    </TooltipProvider>
  );
};

export default EditItemSheet;
