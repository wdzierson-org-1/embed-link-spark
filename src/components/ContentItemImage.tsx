
import React from 'react';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  title?: string;
  file_path?: string;
}

interface ContentItemImageProps {
  item: ContentItem;
  imageErrors: Set<string>;
  onImageError: (itemId: string) => void;
}

const ContentItemImage = ({ item, imageErrors, onImageError }: ContentItemImageProps) => {
  if (item.type !== 'image' || !item.file_path) {
    return null;
  }

  const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
  const imageUrl = data.publicUrl;
  const showImage = imageUrl && !imageErrors.has(item.id);

  if (!showImage) {
    return null;
  }

  return (
    <div className="mb-3">
      <img
        src={imageUrl}
        alt={item.title || 'Content thumbnail'}
        className="w-full h-32 object-cover rounded-md"
        onError={() => onImageError(item.id)}
      />
    </div>
  );
};

export default ContentItemImage;
