
import { useCallback } from 'react';
import { uploadImageForNovel } from '@/services/imageUpload/ImageUploadService';
import type { User, Session } from '@supabase/supabase-js';

interface UseEditorImageUploadProps {
  user: User | null;
  session: Session | null;
  itemId?: string;
}

export const useEditorImageUpload = ({ user, session, itemId }: UseEditorImageUploadProps) => {
  const handleImageUpload = useCallback(async (file: File): Promise<string> => {
    console.log('EditorImageUpload: Novel upload handler called', {
      fileName: file.name,
      fileSize: file.size,
      hasUser: !!user,
      hasSession: !!session,
      userId: user?.id,
      itemId
    });

    if (!user || !session) {
      console.error('EditorImageUpload: No user or session for Novel upload');
      throw new Error('User not authenticated');
    }

    try {
      // Use the Novel-specific upload function that returns just the URL
      const imageUrl = await uploadImageForNovel(file, user.id, itemId);
      
      console.log('EditorImageUpload: Novel upload successful, returning URL:', {
        imageUrl,
        urlValid: imageUrl && imageUrl.length > 0,
        containsSupabase: imageUrl.includes('supabase')
      });
      
      return imageUrl;
    } catch (error) {
      console.error('EditorImageUpload: Novel upload failed', error);
      throw error;
    }
  }, [user, session, itemId]);

  return {
    handleImageUpload
  };
};
