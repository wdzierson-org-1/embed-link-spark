
import React from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Tabs } from '@/components/ui/tabs';
import { TooltipProvider } from '@/components/ui/tooltip';
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
  } = useEditItemSheet({ open, item, onSave });

  // For image items, show inline without tabs
  if (item?.type === 'image') {
    return (
      <TooltipProvider>
        <Sheet open={open} onOpenChange={onOpenChange}>
          <SheetContent className="w-full h-full sm:w-[800px] sm:max-w-[800px] sm:h-auto p-0 flex flex-col">
            <SheetHeader className="px-6 py-4 border-b flex-shrink-0">
              <SheetTitle>Edit Item</SheetTitle>
            </SheetHeader>

            <div className="flex-1 overflow-y-auto pt-6">
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
                isInsideTabs={false}
                showInlineImage={true}
                imageUrl={imageUrl}
              />
            </div>

            <EditItemAutoSaveIndicator saveStatus={saveStatus} lastSaved={lastSaved} />
          </SheetContent>
        </Sheet>
      </TooltipProvider>
    );
  }

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-full h-full sm:w-[800px] sm:max-w-[800px] sm:h-auto p-0 flex flex-col">
          <SheetHeader className="px-6 py-4 border-b flex-shrink-0">
            <SheetTitle>Edit Item</SheetTitle>
          </SheetHeader>

          <div className="flex-1 overflow-y-auto">
            {hasImage ? (
              <Tabs value={activeTab} onValueChange={setActiveTab} className="h-full">
                <div className="px-6 py-4">
                  <EditItemTabNavigation hasImage={hasImage} />
                </div>

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
                  isInsideTabs={true}
                />

                <EditItemImageTab
                  item={item}
                  hasImage={hasImage}
                  imageUrl={imageUrl}
                  onImageStateChange={handleImageStateChange}
                />
              </Tabs>
            ) : (
              // Render details directly without tabs when no image
              <div className="pt-6">
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
                  isInsideTabs={false}
                />
              </div>
            )}
          </div>

          <EditItemAutoSaveIndicator saveStatus={saveStatus} lastSaved={lastSaved} />
        </SheetContent>
      </Sheet>
    </TooltipProvider>
  );
};

export default EditItemSheet;
