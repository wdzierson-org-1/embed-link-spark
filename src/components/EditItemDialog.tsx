
import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import ItemTagsManager from '@/components/ItemTagsManager';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';

interface EditItemDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: {
    id: string;
    title?: string;
    description?: string;
    content?: string;
    file_path?: string;
    type?: string;
    tags?: string[];
  } | null;
  onSave: (id: string, updates: { title?: string; description?: string; content?: string }) => Promise<void>;
}

const EditItemDialog = ({ open, onOpenChange, item, onSave }: EditItemDialogProps) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [content, setContent] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [resetTrigger, setResetTrigger] = useState(0);
  const { toast } = useToast();

  useEffect(() => {
    if (item) {
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      setTags(item.tags || []);
      
      // Check if item has an image
      if (item.file_path && item.type === 'image') {
        setHasImage(true);
        const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
        setImageUrl(data.publicUrl);
      } else {
        setHasImage(false);
        setImageUrl('');
      }
    }
  }, [item]);

  // Reset editor when dialog closes
  useEffect(() => {
    if (!open) {
      // Increment reset trigger to force editor recreation on next open
      setResetTrigger(prev => prev + 1);
    }
  }, [open]);

  const handleSave = async () => {
    if (!item) return;
    
    setIsLoading(true);
    try {
      await onSave(item.id, {
        title: title.trim() || undefined,
        description: description.trim() || undefined,
        content: content.trim() || undefined,
      });
      onOpenChange(false);
    } catch (error) {
      console.error('Error saving item:', error);
      toast({
        title: "Error",
        description: "Failed to save changes",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleTitleSave = async (newTitle: string) => {
    if (!item) return;
    await onSave(item.id, { title: newTitle || undefined });
  };

  const handleDescriptionSave = async (newDescription: string) => {
    if (!item) return;
    await onSave(item.id, { description: newDescription || undefined });
  };

  const handleImageStateChange = (newHasImage: boolean, newImageUrl: string) => {
    setHasImage(newHasImage);
    setImageUrl(newImageUrl);
  };

  const handleTagsUpdated = () => {
    // This will be called when tags are updated
    // The ItemTagsManager handles the actual updates
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent 
        side="right" 
        className="w-full sm:max-w-2xl p-0 flex flex-col"
      >
        <ScrollArea className="flex-1">
          <div className="p-6 space-y-6">
            {/* Title Section - moved to top */}
            <div className="border-b pb-4">
              <EditItemTitleSection
                title={title}
                onTitleChange={setTitle}
                onSave={handleTitleSave}
              />
              
              {/* Add Image Link */}
              <div className="mt-2">
                <EditItemImageSection
                  itemId={item?.id || ''}
                  hasImage={hasImage}
                  imageUrl={imageUrl}
                  onImageStateChange={handleImageStateChange}
                  asLink={true}
                />
              </div>
            </div>

            {/* Content Section */}
            <EditItemContentEditor
              content={content}
              onContentChange={setContent}
              itemId={item?.id}
              resetTrigger={resetTrigger}
            />

            {/* AI Description Section */}
            <EditItemDescriptionSection
              itemId={item?.id || ''}
              description={description}
              content={content}
              title={title}
              onDescriptionChange={setDescription}
              onSave={handleDescriptionSave}
            />

            {/* Tags Section */}
            <div>
              <Label className="text-base font-medium mb-3 block">Tags</Label>
              <ItemTagsManager
                itemId={item?.id || ''}
                currentTags={tags}
                onTagsUpdated={handleTagsUpdated}
                itemContent={{
                  title: title,
                  content: content,
                  description: description
                }}
              />
            </div>
          </div>
        </ScrollArea>

        {/* Save Button */}
        <div className="flex-shrink-0 p-6 pt-4 border-t bg-background">
          <Button onClick={handleSave} disabled={isLoading} className="w-full">
            {isLoading ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
};

export default EditItemDialog;
