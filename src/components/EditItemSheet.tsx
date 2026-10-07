
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
import { domainOfUrl } from '@/utils/linkFlavor';
import { kindLabel } from '@/components/cards/ItemTypeChip';
import { St4shSymbol } from '@/components/brand/St4sh';
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
  url?: string;
  created_at?: string;
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

  // The window bar (DESIGN-v2: Stash's own furniture is a window): what this save is and
  // where it came from, in the machine voice. The sheet's close sits at its right end.
  const savedOn = (() => {
    if (!item?.created_at) return '';
    const date = new Date(item.created_at);
    return Number.isNaN(date.getTime())
      ? ''
      : date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).replace(',', '').toLowerCase();
  })();
  const source = item?.type === 'link' ? domainOfUrl(item.url) : '';
  const windowBar = item && (
    <div className="flex h-11 flex-none items-center gap-2.5 bg-ink pl-4 pr-12 text-white sm:pl-10">
      <St4shSymbol className="h-[13px] w-[12px] flex-none text-spot-on-ink" />
      <span className="flex min-w-0 items-center gap-2 truncate font-pixel text-pixel leading-none">
        <span className="bg-white px-1.5 pb-[3px] pt-1 text-ink">{kindLabel({ type: item.type ?? 'text', title: item.title, mime_type: item.mime_type, attributes: item.attributes })}</span>
        {source && <span className="truncate">{source}</span>}
        {savedOn && <span className="truncate text-white/60">saved {savedOn}</span>}
      </span>
    </div>
  );

  const footer = (
    <div className="flex flex-shrink-0 items-center justify-between border-t border-ink bg-white px-4 py-2 sm:px-10">
      {onDelete ? (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <button className="-ml-2 flex h-8 items-center gap-1.5 px-2 text-[13px] text-error transition-colors hover:bg-error hover:text-white">
              <Trash2 className="h-3.5 w-3.5" />
              Delete item
            </button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete this item?</AlertDialogTitle>
              <AlertDialogDescription>
                "{item?.title || 'Untitled'}" and everything Stash knows about it will be removed. This can't be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={handleConfirmDelete} className="bg-error hover:bg-error hover:opacity-90">
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
          <SheetContent className="flex h-full w-full flex-col p-0 sm:h-auto sm:w-[800px] sm:max-w-[800px]">
            <SheetTitle className="sr-only">Edit item</SheetTitle>
            {windowBar}
            <div className="flex-1 overflow-y-auto pt-8">
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
        <SheetContent className="flex h-full w-full flex-col p-0 sm:h-auto sm:w-[800px] sm:max-w-[800px]">
          <SheetTitle className="sr-only">Edit item</SheetTitle>
          {windowBar}
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
              <div className="pt-8">
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
