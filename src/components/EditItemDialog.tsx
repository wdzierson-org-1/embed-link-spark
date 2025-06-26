
import React, { useState, useEffect } from 'react';
import { Sheet, SheetContent } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { ScrollArea } from '@/components/ui/scroll-area';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import ItemTagsManager from '@/components/ItemTagsManager';
import EditItemTitleSection from '@/components/EditItemTitleSection';
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
  const [tags, setTags] = useState<string[]>([]);
  const [editorInstanceKey, setEditorInstanceKey] = useState('');
  const { toast } = useToast();

  // Generate new editor instance key when dialog opens or item changes
  useEffect(() => {
    if (open && item) {
      const newInstanceKey = `${item.id}-${Date.now()}`;
      setEditorInstanceKey(newInstanceKey);
      console.log('EditItemDialog: Generated new editor instance key', { newInstanceKey, itemId: item.id });
    }
  }, [open, item?.id]);

  useEffect(() => {
    if (item) {
      console.log('EditItemDialog: Setting item data', { 
        itemId: item.id, 
        contentLength: item.content?.length || 0,
        contentPreview: item.content?.slice(0, 50) || 'No content'
      });
      
      setTitle(item.title || '');
      setDescription(item.description || '');
      setContent(item.content || '');
      setTags(item.tags || []);
    }
  }, [item]);

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
            {/* Title Section */}
            <div className="border-b pb-4">
              <EditItemTitleSection
                title={title}
                onTitleChange={setTitle}
                onSave={handleTitleSave}
              />
            </div>

            {/* Content Section */}
            <EditItemContentEditor
              content={content}
              onContentChange={setContent}
              itemId={item?.id}
              editorInstanceKey={editorInstanceKey}
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
