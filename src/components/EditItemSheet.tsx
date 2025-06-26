
import React from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Tabs } from '@/components/ui/tabs';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Button } from '@/components/ui/button';
import { AlertCircle } from 'lucide-react';
import EditItemTabNavigation from '@/components/EditItemTabNavigation';
import EditItemDetailsTab from '@/components/EditItemDetailsTab';
import EditItemImageTab from '@/components/EditItemImageTab';
import EditItemAutoSaveIndicator from '@/components/EditItemAutoSaveIndicator';
import { useEditItemSheet } from '@/hooks/useEditItemSheet';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: ContentItem | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }, options?: { showSuccessToast?: boolean; refreshItems?: boolean }) => Promise<void>;
}

const EditItemSheet = ({ open, onOpenChange, item, onSave }: EditItemSheetProps) => {
  const {
    title,
    description,
    content,
    hasImage,
    imageUrl,
    isContentLoading,
    editorKey,
    activeTab,
    saveStatus,
    showDraftRestore,
    setActiveTab,
    handleTitleChange,
    handleDescriptionChange,
    handleContentChange,
    handleTitleSave,
    handleDescriptionSave,
    handleTagsChange,
    handleMediaChange,
    handleImageStateChange,
    handleRestoreDraft,
    handleDiscardDraft,
  } = useEditItemSheet({ open, item, onSave });

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-[800px] sm:max-w-[800px] p-0 flex flex-col">
          <SheetHeader className="px-6 py-4 border-b flex-shrink-0">
            <SheetTitle>Edit Item</SheetTitle>
          </SheetHeader>

          {/* Draft Restoration Banner */}
          {showDraftRestore && (
            <div className="px-6 py-3 bg-amber-50 border-b border-amber-200 flex items-center justify-between">
              <div className="flex items-center gap-2 text-amber-800">
                <AlertCircle className="h-4 w-4" />
                <span className="text-sm font-medium">Unsaved changes found</span>
              </div>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={handleDiscardDraft}
                  className="text-xs"
                >
                  Discard
                </Button>
                <Button
                  size="sm"
                  onClick={handleRestoreDraft}
                  className="text-xs"
                >
                  Restore
                </Button>
              </div>
            </div>
          )}

          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col min-h-0">
            <EditItemTabNavigation hasImage={hasImage} />

            <EditItemDetailsTab
              item={item}
              title={title}
              description={description}
              content={content}
              isContentLoading={isContentLoading}
              editorKey={editorKey}
              onTitleChange={handleTitleChange}
              onDescriptionChange={handleDescriptionChange}
              onContentChange={handleContentChange}
              onTitleSave={handleTitleSave}
              onDescriptionSave={handleDescriptionSave}
              onTagsChange={handleTagsChange}
              onMediaChange={handleMediaChange}
            />

            <EditItemImageTab
              item={item}
              hasImage={hasImage}
              imageUrl={imageUrl}
              onImageStateChange={handleImageStateChange}
            />
          </Tabs>

          <EditItemAutoSaveIndicator saveStatus={saveStatus} />
        </SheetContent>
      </Sheet>
    </TooltipProvider>
  );
};

export default EditItemSheet;
