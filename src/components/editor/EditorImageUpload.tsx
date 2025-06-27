
import { toast } from 'sonner';
import { supabase } from '@/integrations/supabase/client';
import { uploadImage } from '@/services/imageUploadService';

interface EditorImageUploadProps {
  user: any;
  session: any;
  itemId?: string;
}

export const useEditorImageUpload = ({ user, session, itemId }: EditorImageUploadProps) => {
  const handleImageUpload = async (file: File): Promise<string> => {
    console.log('Starting image upload', { 
      fileName: file.name, 
      fileSize: file.size, 
      hasUser: !!user,
      hasSession: !!session
    });

    if (!user || !session) {
      console.error('No user or session found');
      toast.error('Please log in to upload images');
      throw new Error('User not authenticated');
    }

    if (session.expires_at) {
      const expiryTime = new Date(session.expires_at * 1000);
      const currentTime = new Date();
      const timeUntilExpiry = expiryTime.getTime() - currentTime.getTime();
      
      if (timeUntilExpiry < 5 * 60 * 1000) {
        console.log('Session expires soon, refreshing...');
        try {
          const { error } = await supabase.auth.refreshSession();
          if (error) {
            console.error('Failed to refresh session', error);
            toast.error('Session expired. Please refresh the page and try again.');
            throw new Error('Session expired');
          }
        } catch (refreshError) {
          console.error('Session refresh failed', refreshError);
          toast.error('Session expired. Please refresh the page and try again.');
          throw refreshError;
        }
      }
    }

    try {
      const result = await uploadImage({
        file,
        userId: user.id,
        itemId: itemId
      });
      
      console.log('Upload completed successfully', {
        publicUrl: result.publicUrl,
        filePath: result.filePath
      });
      
      return result.publicUrl;
    } catch (error) {
      console.error('Upload failed', error);
      
      if (error instanceof Error) {
        if (error.message.includes('RLS') || 
            error.message.includes('policy') || 
            error.message.includes('Unauthorized') ||
            error.message.includes('row-level security')) {
          toast.error('Permission denied. Please refresh the page and try again.');
        } else if (error.message.includes('Session expired')) {
          toast.error('Session expired. Please refresh the page and try again.');
        } else if (error.message.includes('User ID mismatch')) {
          toast.error('Authentication error. Please refresh the page and try again.');
        } else {
          toast.error(`Upload failed: ${error.message}`);
        }
      } else {
        toast.error('Failed to upload image. Please try again.');
      }
      
      throw error;
    }
  };

  return { handleImageUpload };
};
