
import React from 'react';
import { supabase } from '@/integrations/supabase/client';
import { getGradientPlaceholder } from '@/utils/gradientPlaceholders';

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
  isPublicView?: boolean;
}

const ContentItemImage = ({ item, imageErrors, onImageError, isPublicView }: ContentItemImageProps) => {
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
          referrerPolicy="no-referrer"
        />
      </div>
    );
  }

  // Handle link preview images - now stored in file_path
  if (item.type === 'link' && item.file_path && !imageErrors.has(item.id)) {
    // If file_path is already a full HTTP URL, use it directly (backward compatibility)
    const imageUrl = item.file_path.startsWith('http') 
      ? item.file_path 
      : supabase.storage.from('stash-media').getPublicUrl(item.file_path).data.publicUrl;

    return (
      <div className="w-full h-48 overflow-hidden">
        <img
          src={imageUrl}
          alt={item.title || 'Link preview'}
          className="w-full h-full object-cover"
          onError={() => onImageError(item.id)}
          referrerPolicy="no-referrer"
        />
      </div>
    );
  }

  // Always show a gradient placeholder if no image is available
  const gradientSrc = getGradientPlaceholder(item.id);
  
  return (
    <div className="relative w-full h-48 overflow-hidden">
      <img
        src={gradientSrc}
        alt={item.title || 'Content thumbnail'}
        className="w-full h-full object-cover"
      />
      {isPublicView && (
        <div className="absolute top-2 right-2 bg-primary text-primary-foreground text-xs font-medium px-2 py-1 rounded-md shadow-sm">
          PUBLICLY SHARED
        </div>
      )}
    </div>
  );
};

export default ContentItemImage;
