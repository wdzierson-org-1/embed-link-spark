
import React, { useState } from 'react';
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
import { useNow } from '@/hooks/useNow';
import { isReadingDocument } from '@/utils/itemAssembly';
import ItemWindowBar from '@/components/edit/ItemWindowBar';
import ShareControl from '@/components/edit/ShareControl';
import { StageFullProvider } from '@/components/edit/StageFull';
import { embedFor } from '@/utils/embeds';
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
  share_token?: string | null;
  summary?: string;
  url?: string;
  created_at?: string;
  attributes?: ItemAttributes;
}

interface EditItemSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string; supplemental_note?: string; is_public?: boolean; file_path?: string | null; attributes?: ItemAttributes; url?: string; summary?: string | null; share_token?: string | null; shared_at?: string | null }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
  onDelete?: (id: string) => void;
}

const EditItemSheet = ({ open, onOpenChange, item, onSave, onDelete }: EditItemSheetProps) => {
  const isMobile = useIsMobile();
  const now = useNow();

  const isProcessing = item ? isReadingDocument(item, now.getTime()) : false;

  // Prevent opening while a PDF is still being read (one whose extraction failed opens)
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

  // A link's address, edited in its strip. The quality loop reassesses the item on its own
  // (the items trigger queues a job whenever url changes).
  const handleUrlSave = async (url: string) => {
    if (!item) return;
    await onSave(item.id, { url }, { showSuccessToast: false, refreshItems: true });
  };

  // The summary, edited in place (DESIGN-v2 §12.8). Empty clears it; saving re-indexes the item.
  const handleSummarySave = async (summary: string) => {
    if (!item) return;
    await onSave(item.id, { summary: summary.trim() ? summary : null }, { showSuccessToast: false, refreshItems: true });
  };

  const handleConfirmDelete = () => {
    if (!item || !onDelete) return;
    onOpenChange(false);
    onDelete(item.id);
  };

  const [stageFull, setStageFull] = useState(false);

  // The window bar (DESIGN-v2: Stash's own furniture is a window): what this save is and
  // where it came from, in the machine voice. The share cell, then the sheet's close, sit at
  // its right end.
  const windowBar = item && (
    <ItemWindowBar item={item}>
      <ShareControl
        shareToken={item.share_token}
        onChange={(updates) => onSave(item.id, updates, { showSuccessToast: false, refreshItems: true })}
      />
    </ItemWindowBar>
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
    onUrlSave: item?.type === 'link' ? handleUrlSave : undefined,
    onSummarySave: handleSummarySave,
    isMobile,
  };

  // A stage made full size takes the sheet to the browser's width (StageFull)
  const sheetClass = `flex h-full w-full flex-col p-0 sm:h-auto ${stageFull ? 'sm:w-screen sm:max-w-none' : 'sm:w-[800px] sm:max-w-[800px]'}`;

  // For image items and links with a picture or a player of their own, show inline without tabs
  if (item?.type === 'image' || (item?.type === 'link' && (hasImage || Boolean(embedFor(item.url))))) {
    return (
      <TooltipProvider>
        <Sheet open={open} onOpenChange={onOpenChange}>
          <SheetContent className={sheetClass}>
            <SheetTitle className="sr-only">Edit item</SheetTitle>
            {windowBar}
            <div className="flex-1 overflow-y-auto pt-8">
              <StageFullProvider onChange={setStageFull}>
                <EditItemDetailsTab
                  {...detailsTabProps}
                  isInsideTabs={false}
                  showInlineImage={true}
                  imageUrl={imageUrl}
                />
              </StageFullProvider>
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
        <SheetContent className={sheetClass}>
          <SheetTitle className="sr-only">Edit item</SheetTitle>
          {windowBar}
          <div className="flex-1 overflow-y-auto">
            {hasImage ? (
              <Tabs value={activeTab} onValueChange={setActiveTab} className="h-full">
                <div className="px-6 py-4">
                  <EditItemTabNavigation hasImage={hasImage} />
                </div>

                <StageFullProvider onChange={setStageFull}>
                  <EditItemDetailsTab {...detailsTabProps} isInsideTabs={true} />
                </StageFullProvider>

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
