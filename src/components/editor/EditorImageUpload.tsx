
import { useCallback } from 'react';
import { createImageUpload } from 'novel';
import { uploadImageForNovel } from '@/services/imageUpload/ImageUploadService';
import type { User, Session } from '@supabase/supabase-js';
import { toast } from 'sonner';

interface UseEditorImageUploadProps {
  user: User | null;
  session: Session | null;
  itemId?: string;
  onUploadComplete?: () => void;
}

export const useEditorImageUpload = ({ user, session, itemId, onUploadComplete }: UseEditorImageUploadProps) => {
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
      
      console.log('EditorImageUpload: Novel upload successful, URL returned:', {
        imageUrl,
        urlValid: imageUrl && imageUrl.length > 0,
        containsSupabase: imageUrl.includes('supabase')
      });
      
      // ENHANCED: Trigger upload complete callback with proper timing
      // This delay ensures Novel has time to replace the placeholder with the final URL
      if (onUploadComplete) {
        setTimeout(() => {
          console.log('EditorImageUpload: Triggering explicit save callback after upload completion');
          onUploadComplete();
        }, 600); // Adjusted timing to match EditItemContentEditor delay
      }
      
      return imageUrl;
    } catch (error) {
      console.error('EditorImageUpload: Novel upload failed', error);
      throw error;
    }
  }, [user, session, itemId, onUploadComplete]);

  // Create the upload function using Novel's createImageUpload pattern
  const createUploadFn = useCallback(() => {
    if (!handleImageUpload) return undefined;

    console.log('EditorImageUpload: Creating Novel UploadFn with explicit save trigger', {
      hasUser: !!user,
      itemId,
      hasUploadCompleteCallback: !!onUploadComplete
    });

    return createImageUpload({
      onUpload: handleImageUpload,
      validateFn: (file) => {
        console.log('EditorImageUpload: Novel validation called', {
          fileName: file.name,
          fileType: file.type,
          fileSize: file.size
        });
        
        if (!file.type.includes("image/")) {
          toast.error("File type not supported. Please upload an image file.");
          return false;
        }
        if (file.size / 1024 / 1024 > 20) {
          toast.error("File size too big (max 20MB).");
          return false;
        }
        
        console.log('EditorImageUpload: Novel validation passed');
        return true;
      },
    });
  }, [handleImageUpload, user, itemId, onUploadComplete]);

  return {
    handleImageUpload,
    createUploadFn
  };
};
