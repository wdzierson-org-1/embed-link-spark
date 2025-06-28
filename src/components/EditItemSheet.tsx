
import React from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Image, FileText } from 'lucide-react';
import { useEditItemSheet } from '@/hooks/useEditItemSheet';
import EditItemDetailsTab from '@/components/EditItemDetailsTab';
import EditItemImageTab from '@/components/EditItemImageTab';
import EditItemAutoSaveIndicator from '@/components/EditItemAutoSaveIndicator';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
  mime_type?: string;
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

  const getFileUrl = (item: ContentItem) => {
    if (item?.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const getFileSize = (item: ContentItem) => {
    // This is a placeholder - in a real app you'd store file size in the database
    return "Size unavailable";
  };

  const handleImageClick = (imageUrl: string) => {
    window.open(imageUrl, '_blank');
  };

  // Special handling for image items
  if (item?.type === 'image') {
    const fileUrl = getFileUrl(item);
    const fileName = item.title || 'Untitled Image';
    const fileSize = getFileSize(item);

    return (
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-[600px] sm:max-w-[600px] flex flex-col p-0">
          <SheetHeader className="px-6 py-4 border-b">
            <div className="flex items-center justify-between">
              <SheetTitle className="text-lg font-semibold">Image Details</SheetTitle>
              <EditItemAutoSaveIndicator 
                saveStatus={saveStatus} 
                lastSaved={lastSaved} 
              />
            </div>
          </SheetHeader>

          <div className="flex-1 p-6 space-y-6">
            {/* Image Thumbnail */}
            {fileUrl && (
              <div className="space-y-4">
                <div 
                  className="relative cursor-pointer group rounded-lg overflow-hidden border hover:shadow-md transition-shadow"
                  onClick={() => handleImageClick(fileUrl)}
                >
                  <img
                    src={fileUrl}
                    alt={fileName}
                    className="w-full h-64 object-cover group-hover:opacity-90 transition-opacity"
                  />
                  <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-10 transition-all flex items-center justify-center">
                    <div className="opacity-0 group-hover:opacity-100 transition-opacity text-white text-sm bg-black bg-opacity-50 px-3 py-1 rounded">
                      Click to view full size
                    </div>
                  </div>
                </div>
                
                {/* File Info */}
                <div className="bg-gray-50 rounded-lg p-4 space-y-2">
                  <div className="flex items-center gap-2">
                    <Image className="h-4 w-4 text-gray-500" />
                    <span className="font-medium text-sm">{fileName}</span>
                  </div>
                  <div className="text-xs text-gray-500 space-y-1">
                    <div>Type: {item.mime_type || 'Image'}</div>
                    <div>Size: {fileSize}</div>
                  </div>
                </div>
              </div>
            )}

            {/* Title and Description editing */}
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Title
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={handleTitleChange}
                  onBlur={handleTitleSave}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="Enter image title..."
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Description
                </label>
                <textarea
                  value={description}
                  onChange={handleDescriptionChange}
                  onBlur={handleDescriptionSave}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[100px] resize-vertical"
                  placeholder="Enter image description..."
                />
              </div>
            </div>
          </div>
        </SheetContent>
      </Sheet>
    );
  }

  // Regular handling for non-image items
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-[600px] sm:max-w-[600px] flex flex-col p-0">
        <SheetHeader className="px-6 py-4 border-b">
          <div className="flex items-center justify-between">
            <SheetTitle className="text-lg font-semibold">Edit Item</SheetTitle>
            <EditItemAutoSaveIndicator 
              saveStatus={saveStatus} 
              lastSaved={lastSaved} 
            />
          </div>
        </SheetHeader>

        <Tabs value={activeTab} onValueChange={setActiveTab} className="flex flex-col flex-1">
          <div className="border-b bg-gray-50">
            <TabsList className="grid w-full grid-cols-2 h-12 bg-transparent">
              <TabsTrigger 
                value="details" 
                className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm"
              >
                <FileText className="h-4 w-4" />
                Details
              </TabsTrigger>
              {hasImage && (
                <TabsTrigger 
                  value="image" 
                  className="flex items-center gap-2 data-[state=active]:bg-white data-[state=active]:shadow-sm"
                >
                  <Image className="h-4 w-4" />
                  Image
                </TabsTrigger>
              )}
            </TabsList>
          </div>

          <div className="flex-1 overflow-auto">
            <TabsContent value="details" className="m-0 h-full">
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
            </TabsContent>

            {hasImage && (
              <TabsContent value="image" className="m-0 h-full">
                <EditItemImageTab
                  item={item}
                  hasImage={hasImage}
                  imageUrl={imageUrl}
                  onImageStateChange={handleImageStateChange}
                />
              </TabsContent>
            )}
          </div>
        </Tabs>
      </SheetContent>
    </Sheet>
  );
};

export default EditItemSheet;
