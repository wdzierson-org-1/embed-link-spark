import React, { useState, useEffect } from 'react';
import { Dialog, DialogContent } from '@/components/ui/dialog';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import EditItemDialogHeader from '@/components/EditItemDialogHeader';
import EditItemDialogContent from '@/components/EditItemDialogContent';
import EditItemDialogFooter from '@/components/EditItemDialogFooter';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

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
  const [isSaving, setIsSaving] = useState(false);
  const { toast } = useToast();
  const { user } = useAuth();

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

  const getFileUrl = (item: ContentItem) => {
    if (item?.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleRemoveMedia = async () => {
    if (!item?.file_path) return;

    try {
      const { error: storageError } = await supabase.storage
        .from('stash-media')
        .remove([item.file_path]);

      if (storageError) {
        console.error('Error removing file from storage:', storageError);
        toast({
          title: "Error",
          description: "Failed to remove media file",
          variant: "destructive",
        });
        return;
      }

      const { error: updateError } = await supabase
        .from('items')
        .update({
          file_path: null,
          mime_type: null,
          type: 'text'
        })
        .eq('id', item.id);

      if (updateError) {
        console.error('Error updating item:', updateError);
        toast({
          title: "Error",
          description: "Failed to update item",
          variant: "destructive",
        });
        return;
      }

      toast({
        title: "Success",
        description: "Media file removed successfully",
      });

      onOpenChange(false);

    } catch (error) {
      console.error('Error removing media:', error);
      toast({
        title: "Error",
        description: "Failed to remove media file",
        variant: "destructive",
      });
    }
  };

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

  const handleImageUpdate = async (hasImage: boolean, imageUrl: string) => {
    onOpenChange(false);
  };

  const fileUrl = getFileUrl(item);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <EditItemDialogHeader />

        {item && (
          <>
            <EditItemDialogContent
              item={item}
              title={title}
              description={description}
              content={content}
              editorInstanceKey={editorInstanceKey}
              fileUrl={fileUrl}
              onTitleChange={setTitle}
              onDescriptionChange={setDescription}
              onContentChange={setContent}
              onTitleSave={handleTitleSave}
              onDescriptionSave={handleDescriptionSave}
              onImageUpdate={handleImageUpdate}
              onRemoveMedia={handleRemoveMedia}
            />

            <EditItemDialogFooter
              onCancel={() => onOpenChange(false)}
              onSave={handleSave}
              isSaving={isSaving}
            />
          </>
        )}
      </DialogContent>
    </Dialog>
  );
};

export default EditItemDialog;
