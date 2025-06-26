
import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { TooltipProvider } from '@/components/ui/tooltip';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemMediaSection from '@/components/EditItemMediaSection';
import EditItemTagsSection from '@/components/EditItemTagsSection';
import { supabase } from '@/integrations/supabase/client';
import { generateTitle } from '@/utils/titleGenerator';

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
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }) => Promise<void>;
}

const EditItemSheet = ({ open, onOpenChange, item, onSave }: EditItemSheetProps) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [content, setContent] = useState('');
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [isContentLoading, setIsContentLoading] = useState(false);
  const [editorKey, setEditorKey] = useState<string>('');
  const [activeTab, setActiveTab] = useState('details');
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved'>('idle');
  const [saveTimeoutId, setSaveTimeoutId] = useState<NodeJS.Timeout | null>(null);

  // Generate a unique editor key when item changes or sheet opens
  useEffect(() => {
    if (item && open) {
      setIsContentLoading(true);
      // Create a unique key combining item ID and timestamp to force editor recreation
      const newKey = `editor-${item.id}-${Date.now()}`;
      setEditorKey(newKey);
      
      // Set content state
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      
      // Small delay to ensure state is updated before showing editor
      setTimeout(() => {
        setIsContentLoading(false);
      }, 100);
      
      checkForImage();
    }
  }, [item?.id, open]);

  // Clear editor state when sheet closes
  useEffect(() => {
    if (!open) {
      // Reset all state when sheet closes to ensure clean state
      setTitle('');
      setDescription('');
      setContent('');
      setHasImage(false);
      setImageUrl('');
      setIsContentLoading(false);
      setEditorKey('');
      setActiveTab('details');
      setSaveStatus('idle');
      if (saveTimeoutId) {
        clearTimeout(saveTimeoutId);
        setSaveTimeoutId(null);
      }
    }
  }, [open, saveTimeoutId]);

  const checkForImage = () => {
    if (!item) return;
    
    // Check for regular image files
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      setHasImage(true);
      setImageUrl(data.publicUrl);
    }
    // Check for link preview images
    else if (item.type === 'link' && item.content) {
      try {
        const contentData = JSON.parse(item.content);
        const storedImagePath = contentData.ogData?.storedImagePath;
        
        if (storedImagePath) {
          const { data } = supabase.storage.from('stash-media').getPublicUrl(storedImagePath);
          setHasImage(true);
          setImageUrl(data.publicUrl);
        }
      } catch (e) {
        // If content is not JSON, ignore
      }
    } else {
      setHasImage(false);
      setImageUrl('');
    }
  };

  // Unified auto-save function that handles all types of changes
  const triggerAutoSave = async (changeType: 'content' | 'tags' | 'media' = 'content') => {
    if (!item || isContentLoading) return;
    
    // Clear existing timeout
    if (saveTimeoutId) {
      clearTimeout(saveTimeoutId);
    }
    
    setSaveStatus('saving');
    
    const timeoutId = setTimeout(async () => {
      try {
        await onSave(item.id, {
          title: title.trim() || undefined,
          description: description.trim() || undefined,
          content: content.trim() || undefined,
        });
        setSaveStatus('saved');
        
        // Reset to idle after showing "saved" for 2 seconds
        setTimeout(() => {
          setSaveStatus('idle');
        }, 2000);
      } catch (error) {
        console.error('Auto-save failed:', error);
        setSaveStatus('idle');
      }
      setSaveTimeoutId(null);
    }, 1000); // 1 second debounce
    
    setSaveTimeoutId(timeoutId);
  };

  // Auto-save functionality with debouncing for content changes
  useEffect(() => {
    triggerAutoSave('content');
  }, [title, description, content, item?.id]);

  // Handle tags changes callback
  const handleTagsChange = () => {
    triggerAutoSave('tags');
  };

  // Handle media changes callback
  const handleMediaChange = () => {
    triggerAutoSave('media');
  };

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    
    // If title is empty, generate one from content
    let finalTitle = newTitle;
    if (!finalTitle && content) {
      try {
        finalTitle = await generateTitle(content, item.type || 'text');
      } catch (error) {
        console.error('Error generating title:', error);
        finalTitle = 'Untitled Note';
      }
    }
    
    setTitle(finalTitle);
    await onSave(item.id, { title: finalTitle });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    await onSave(item.id, { description: newDescription });
  };

  const handleImageStateChange = (newHasImage: boolean, newImageUrl: string) => {
    setHasImage(newHasImage);
    setImageUrl(newImageUrl);
    // Refetch the item to update the UI properly
    if (item) {
      setTimeout(() => checkForImage(), 500);
    }
    // Trigger auto-save for media changes
    handleMediaChange();
  };

  const getSaveStatusText = () => {
    switch (saveStatus) {
      case 'saving':
        return 'Saving...';
      case 'saved':
        return 'Saved';
      default:
        return 'Changes are saved automatically';
    }
  };

  return (
    <TooltipProvider>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-[800px] sm:max-w-[800px] p-0 flex flex-col">
          <SheetHeader className="px-6 py-4 border-b flex-shrink-0">
            <SheetTitle>Edit Item</SheetTitle>
          </SheetHeader>

          <Tabs value={activeTab} onValueChange={setActiveTab} className="flex-1 flex flex-col min-h-0">
            <div className="px-6 mt-4 flex-shrink-0">
              <TabsList className="w-fit">
                <TabsTrigger value="details">Note Details</TabsTrigger>
                {hasImage && <TabsTrigger value="image">Image</TabsTrigger>}
              </TabsList>
            </div>

            <TabsContent value="details" className="flex-1 overflow-y-auto m-0 px-6 pb-6">
              <div className="space-y-8 pt-4">
                {/* Title Section */}
                <EditItemTitleSection
                  title={title}
                  onTitleChange={setTitle}
                  onSave={handleTitleSave}
                />

                {/* Content Section */}
                <div className="space-y-2">
                  <label className="text-sm font-medium text-muted-foreground">Content</label>
                  <div className="relative">
                    {isContentLoading ? (
                      <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
                        Loading editor...
                      </div>
                    ) : (
                      <EditItemContentEditor
                        content={content}
                        onContentChange={setContent}
                        itemId={item?.id}
                        editorInstanceKey={editorKey}
                      />
                    )}
                    <div className="absolute bottom-3 right-3 text-xs text-muted-foreground bg-background/80 backdrop-blur-sm px-2 py-1 rounded">
                      Press / for formatting options
                    </div>
                  </div>
                </div>

                {/* Summary Section */}
                <EditItemDescriptionSection
                  itemId={item?.id || ''}
                  description={description}
                  content={content}
                  title={title}
                  onDescriptionChange={setDescription}
                  onSave={handleDescriptionSave}
                />

                {/* Media Section */}
                <EditItemMediaSection item={item} onMediaChange={handleMediaChange} />

                {/* Tags Section */}
                <EditItemTagsSection item={item} onTagsChange={handleTagsChange} />
              </div>
            </TabsContent>

            <TabsContent value="image" className="flex-1 overflow-y-auto m-0 px-6 pb-6">
              <div className="pt-4">
                {hasImage && (
                  <div className="relative inline-block">
                    <img
                      src={imageUrl}
                      alt="Item image"
                      className="w-full max-w-md rounded-lg border"
                    />
                    <EditItemImageSection
                      itemId={item?.id || ''}
                      hasImage={hasImage}
                      imageUrl={imageUrl}
                      onImageStateChange={handleImageStateChange}
                      asLink={true}
                    />
                  </div>
                )}
              </div>
            </TabsContent>
          </Tabs>

          {/* Auto-save indicator */}
          <div className="px-6 py-3 border-t bg-muted/30 flex-shrink-0">
            <p className={`text-xs ${saveStatus === 'saving' ? 'text-blue-600' : saveStatus === 'saved' ? 'text-green-600' : 'text-muted-foreground'}`}>
              {getSaveStatusText()}
            </p>
          </div>
        </SheetContent>
      </Sheet>
    </TooltipProvider>
  );
};

export default EditItemSheet;
