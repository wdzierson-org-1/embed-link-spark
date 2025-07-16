
import { supabase } from '@/integrations/supabase/client';

export const downloadAndStoreImage = async (imageUrl: string, userId: string): Promise<string | null> => {
  if (!userId) return null;
  
  try {
    const response = await fetch(imageUrl, { mode: 'cors' });
    if (!response.ok) return null;
    
    const blob = await response.blob();
    // Extract file extension from URL, remove query params and clean up
    const urlParts = imageUrl.split('?')[0].split('/');
    const lastPart = urlParts[urlParts.length - 1];
    const fileExt = lastPart.includes('.') ? lastPart.split('.').pop() : 'jpg';
    const fileName = `preview_${Date.now()}.${fileExt}`;
    const filePath = `${userId}/previews/${fileName}`;

    const { error: uploadError } = await supabase.storage
      .from('stash-media')
      .upload(filePath, blob);

    if (uploadError) {
      console.error('Error uploading preview image:', uploadError);
      return null;
    }

    return filePath;
  } catch (error) {
    console.error('Error downloading and storing image:', error);
    return null;
  }
};
