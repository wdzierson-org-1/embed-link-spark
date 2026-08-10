
import React, { useState } from 'react';
import { FileText, StickyNote, AudioLines, Video, Image as ImageIcon, Link as LinkIcon, type LucideIcon } from 'lucide-react';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { getGradientPlaceholder } from '@/utils/gradientPlaceholders';

const TYPE_ICONS: Record<string, LucideIcon> = {
  document: FileText,
  text: StickyNote,
  audio: AudioLines,
  video: Video,
  image: ImageIcon,
  link: LinkIcon,
};

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
  const [imgState, setImgState] = useState<{ src: string; triedProxy: boolean } | null>(null);

  // Build initial image source
  const getInitialImageSrc = () => {
    if (item.type === 'image' && item.file_path) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    
    if (item.type === 'link' && item.file_path) {
      // If it's a Supabase storage path, use public URL
      if (!item.file_path.startsWith('http')) {
        const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
        return data.publicUrl;
      }
      // If it's an external HTTP URL, route through proxy initially to avoid CORS/hotlinking
      return `${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(item.file_path)}`;
    }
    
    return null;
  };

  const initialSrc = getInitialImageSrc();
  const hasValidImage = initialSrc && !imageErrors.has(item.id);

  // Initialize image state
  if (!imgState && initialSrc) {
    const isProxied = initialSrc.includes('/functions/v1/image-proxy');
    setImgState({ src: initialSrc, triedProxy: isProxied });
  }

  const handleImageError = () => {
    if (!imgState) {
      onImageError(item.id);
      return;
    }

    if (!imgState.triedProxy && initialSrc) {
      // Try proxy fallback
      const proxySrc = initialSrc.includes('/functions/v1/image-proxy') 
        ? initialSrc 
        : `${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(initialSrc)}`;
      setImgState({ src: proxySrc, triedProxy: true });
    } else {
      // Already tried proxy, give up
      onImageError(item.id);
    }
  };

  // Show actual image if we have one and it's valid
  if (hasValidImage && imgState && (item.type === 'image' || item.type === 'link') && item.file_path) {
    return (
      <div className="w-full h-48 overflow-hidden">
        <img
          src={imgState.src}
          alt={item.title || 'Content thumbnail'}
          className="w-full h-full object-cover"
          onError={handleImageError}
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
        />
      </div>
    );
  }

  // Always show a gradient placeholder if no image is available
  const gradientSrc = getGradientPlaceholder(item.id);
  const TypeIcon = TYPE_ICONS[item.type];

  return (
    <div className="relative w-full h-48 overflow-hidden">
      <img
        src={gradientSrc}
        alt={item.title || 'Content thumbnail'}
        className="w-full h-full object-cover"
      />
      {TypeIcon && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="grid h-14 w-14 place-items-center rounded-2xl bg-white/75 shadow-[0_2px_8px_rgba(0,0,0,0.12)] backdrop-blur-sm">
            <TypeIcon className="h-6 w-6 text-gray-700" strokeWidth={1.75} />
          </div>
        </div>
      )}
      {isPublicView && (
        <div className="absolute top-2 right-2 bg-primary text-primary-foreground text-xs font-medium px-2 py-1 rounded-md shadow-sm">
          PUBLICLY SHARED
        </div>
      )}
    </div>
  );
};

export default ContentItemImage;
