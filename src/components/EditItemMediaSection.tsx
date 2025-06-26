
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Play } from 'lucide-react';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import { supabase } from '@/integrations/supabase/client';

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
}

const EditItemMediaSection = ({ item }: EditItemMediaSectionProps) => {
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);

  const getFileUrl = (item: ContentItem) => {
    if (item?.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  if (!item?.file_path || (item.type !== 'audio' && item.type !== 'video')) {
    return null;
  }

  const fileUrl = getFileUrl(item);

  return (
    <div className="space-y-4">
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
