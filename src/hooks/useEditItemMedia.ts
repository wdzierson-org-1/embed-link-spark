
import { useState, useCallback, useEffect } from 'react';
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

interface UseEditItemMediaProps {
  item: ContentItem | null;
}

export const useEditItemMedia = ({ item }: UseEditItemMediaProps) => {
  const [hasImage, setHasImage] = useState(false);
  const [imageUrl, setImageUrl] = useState('');

  const checkForImage = useCallback(() => {
    if (!item) return;

    if ((item.type === 'image' || item.type === 'link') && item.file_path) {
      // file_path is either a storage path or (for rescued link previews) a
      // raw external URL — use external URLs directly
      if (item.file_path.startsWith('http')) {
        setHasImage(true);
        setImageUrl(item.file_path);
      } else {
        const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
        setHasImage(true);
        setImageUrl(data.publicUrl);
      }
    } else {
      setHasImage(false);
      setImageUrl('');
    }
  }, [item]);

  useEffect(() => {
    checkForImage();
  }, [checkForImage]);

  const handleImageStateChange = useCallback((newHasImage: boolean, newImageUrl: string) => {
    setHasImage(newHasImage);
    setImageUrl(newImageUrl);
    if (item) {
      setTimeout(() => checkForImage(), 500);
    }
  }, [item, checkForImage]);

  // Clear media state when item changes or is null
  useEffect(() => {
    if (!item) {
      setHasImage(false);
      setImageUrl('');
    }
  }, [item]);

  return {
    hasImage,
    imageUrl,
    handleImageStateChange,
  };
};
