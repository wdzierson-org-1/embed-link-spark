
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import MediaPlayer from '@/components/MediaPlayer';
import VideoLightbox from '@/components/VideoLightbox';
import MediaRemovalItem from '@/components/MediaRemovalItem';

interface ContentItem {
  id: string;
  title?: string;
  description?: string;
  content?: string;
  file_path?: string;
  type?: string;
  tags?: string[];
}

interface EditItemDialogMediaProps {
  item: ContentItem;
  fileUrl: string | null;
  onRemoveMedia: () => Promise<void>;
}

const EditItemDialogMedia = ({ item, fileUrl, onRemoveMedia }: EditItemDialogMediaProps) => {
  const [isVideoLightboxOpen, setIsVideoLightboxOpen] = useState(false);

  if (!item.file_path || (item.type !== 'audio' && item.type !== 'video')) {
    return null;
  }

  return (
    <div className="space-y-4">
      <h3 className="text-lg font-semibold">Media</h3>
      
      {/* Media removal item */}
      <MediaRemovalItem
        fileName={item.title || 'Media file'}
        fileType={item.type as 'audio' | 'video'}
        onRemove={onRemoveMedia}
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
  );
};

export default EditItemDialogMedia;
