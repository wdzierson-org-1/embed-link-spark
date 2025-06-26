
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Play } from 'lucide-react';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import MediaRemovalItem from '@/components/MediaRemovalItem';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemMediaSectionProps {
  item: ContentItem | null;
  onMediaChange?: () => void;
}

const EditItemMediaSection = ({ item, onMediaChange }: EditItemMediaSectionProps) => {
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);
  const { toast } = useToast();

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

      // Notify parent about media change for auto-save
      if (onMediaChange) {
        onMediaChange();
      }

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

  if (!item?.file_path || (item.type !== 'audio' && item.type !== 'video')) {
    return null;
  }

  const fileUrl = getFileUrl(item);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <label className="text-sm font-medium text-muted-foreground">Media</label>
      </div>

      {/* Media removal item */}
      <MediaRemovalItem
        fileName={item.title || 'Media file'}
        fileType={item.type as 'audio' | 'video'}
        onRemove={handleRemoveMedia}
      />

      {item.type === 'audio' && fileUrl && (
        <MediaPlayer
          src={fileUrl}
          fileName={item.title || 'Audio file'}
          showRemove={false}
        />
      )}

      {item.type === 'video' && fileUrl && (
        <div className="space-y-2">
          <Button
            variant="outline"
            onClick={() => setIsVideoLightboxOpen(true)}
            className="w-full justify-center gap-2"
          >
            <Play className="h-4 w-4" />
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
  );
};

export default EditItemMediaSection;
