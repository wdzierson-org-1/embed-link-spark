import React, { useState, useEffect, useRef } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import EditItemTitleSection from '@/components/EditItemTitleSection';
import EditItemDescriptionSection from '@/components/EditItemDescriptionSection';
import EditItemImageSection from '@/components/EditItemImageSection';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import MediaRemovalItem from '@/components/MediaRemovalItem';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';

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
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const { toast } = useToast();
  const { user } = useAuth();

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

  const getFileUrl = (item: ContentItem) => {
    if (item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleRemoveMedia = async () => {
    if (!item?.file_path) return;

    try {
      // Remove file from storage
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

      // Update the item to remove file reference
      await onSave(item.id, {
        file_path: null,
        mime_type: null,
        type: 'text' // Convert to text type
      });

      toast({
        title: "Success",
        description: "Media file removed successfully",
      });

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

  const handleTagsUpdated = () => {
    // This will be called when tags are updated
    // The ItemTagsManager handles the actual updates
  };

  const handleImageUpdate = async (newImage: string) => {
    if (!item) return;
    await onSave(item.id, { file_path: newImage });
  };

  const fileUrl = getFileUrl(item);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Edit Item</DialogTitle>
        </DialogHeader>

        {item && (
          <div className="space-y-6">
            <EditItemTitleSection
              title={title}
              onTitleChange={setTitle}
            />

            <EditItemDescriptionSection
              description={description}
              onDescriptionChange={setDescription}
            />

            {/* Media Section */}
            {item.file_path && (item.type === 'audio' || item.type === 'video') && (
              <div className="space-y-4">
                <h3 className="text-lg font-semibold">Media</h3>
                
                {/* Media removal item */}
                <MediaRemovalItem
                  fileName={item.title || 'Media file'}
                  fileType={item.type as 'audio' | 'video'}
                  onRemove={handleRemoveMedia}
                />

                {/* Audio player */}
                {item.type === 'audio' && fileUrl && (
                  <MediaPlayer
                    src={fileUrl}
                    fileName={item.title || 'Audio file'}
                    showRemove={false}
                  />
                )}

                {/* Video preview */}
                {item.type === 'video' && fileUrl && (
                  <div className="space-y-2">
                    <Button
                      variant="outline"
                      onClick={() => setIsVideoLightboxOpen(true)}
                      className="w-full"
                    >
                      Preview Video
                    </Button>
                    <VideoLightbox
                      src={fileUrl}
                      fileName={item.title || 'Video file'}
                      isOpen={isVideoLightboxOpen}
                      onClose={() => setIsVideoLightboxOpen(false)}
                    />
                  </div>
                )}
              </div>
            )}

            {item.type === 'image' && (
              <EditItemImageSection
                item={item}
                onImageUpdate={handleImageUpdate}
              />
            )}

            {(item.type === 'text' || item.type === 'link') && (
              <EditItemContentEditor
                content={content}
                onContentChange={setContent}
                getSuggestedTags={async () => []}
              />
            )}

            <div className="flex justify-end gap-2 pt-4 border-t">
              <Button
                variant="outline"
                onClick={() => onOpenChange(false)}
              >
                Cancel
              </Button>
              <Button
                onClick={handleSave}
                disabled={isSaving}
              >
                {isSaving ? 'Saving...' : 'Save Changes'}
              </Button>
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
};

export default EditItemDialog;
