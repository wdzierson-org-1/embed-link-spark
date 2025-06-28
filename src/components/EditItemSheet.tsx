
import React from 'react';
import { Sheet, SheetContent, SheetHeader } from '@/components/ui/sheet';
import { TooltipProvider } from '@/components/ui/tooltip';
import { Input } from '@/components/ui/input';
import EditItemDetailsTab from '@/components/EditItemDetailsTab';
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
  links?: any[];
  files?: any[];
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

  const handleTitleBlur = () => {
    if (title !== item?.title) {
      handleTitleSave(title);
    }
  };

  const handleTitleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      e.currentTarget.blur();
    }
  };

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-full h-full sm:w-[800px] sm:max-w-[800px] sm:h-auto p-0 flex flex-col">
          <SheetHeader className="px-6 py-4 border-b flex-shrink-0">
            <Input
              value={title}
              onChange={(e) => handleTitleChange(e.target.value)}
              onBlur={handleTitleBlur}
              onKeyDown={handleTitleKeyDown}
              className="text-lg font-semibold border-none p-0 h-auto focus-visible:ring-0 focus-visible:ring-offset-0"
              placeholder="Untitled Note"
            />
          </SheetHeader>

          {/* Primary Image - show at top if available */}
          {hasImage && imageUrl && (
            <div className="w-full h-48 overflow-hidden flex-shrink-0">
              <img
                src={imageUrl}
                alt={title || 'Note image'}
                className="w-full h-full object-cover"
              />
            </div>
          )}

          <div className="flex-1 overflow-y-auto">
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
          </div>

          <EditItemAutoSaveIndicator saveStatus={saveStatus} lastSaved={lastSaved} />
        </SheetContent>
      </Sheet>
    </TooltipProvider>
  );
};

export default EditItemSheet;
