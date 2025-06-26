
import React from 'react';
import { supabase } from '@/integrations/supabase/client';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document';
  title?: string;
  file_path?: string;
  content?: string;
}

interface ContentItemImageProps {
  item: ContentItem;
  imageErrors: Set<string>;
  onImageError: (itemId: string) => void;
}

const ContentItemImage = ({ item, imageErrors, onImageError }: ContentItemImageProps) => {
  // Handle regular image files
  if (item.type === 'image' && item.file_path) {
    const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
    const imageUrl = data.publicUrl;
    const showImage = imageUrl && !imageErrors.has(item.id);

    if (!showImage) {
      return null;
    }

    return (
      <div className="w-full h-48 overflow-hidden">
        <img
          src={imageUrl}
          alt={item.title || 'Content thumbnail'}
          className="w-full h-full object-cover"
          onError={() => onImageError(item.id)}
        />
      </div>
    );
  }

  // Handle link preview images
  if (item.type === 'link' && item.content) {
    try {
      const contentData = JSON.parse(item.content);
      const storedImagePath = contentData.ogData?.storedImagePath;
      
      if (storedImagePath && !imageErrors.has(item.id)) {
        const { data } = supabase.storage.from('stash-media').getPublicUrl(storedImagePath);
        const imageUrl = data.publicUrl;

        return (
          <div className="w-full h-48 overflow-hidden">
            <img
              src={imageUrl}
              alt={item.title || 'Link preview'}
              className="w-full h-full object-cover"
              onError={() => onImageError(item.id)}
            />
          </div>
        );
      }
    } catch (e) {
      // If content is not JSON, ignore
    }
  }

  return null;
};

export default ContentItemImage;
