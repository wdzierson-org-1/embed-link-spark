
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export const uploadFileToStorage = async (file: File, filePath: string, userId: string): Promise<void> => {
  const maxRetries = 3;
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`ImageUploadStorage: Upload attempt ${attempt}/${maxRetries}`, {
        filePath,
        fileSize: file.size,
        fileType: file.type,
        userId
      });

      const { error: uploadError } = await supabase.storage
        .from('stash-media')
        .upload(filePath, file, {
          cacheControl: '3600',
          upsert: false
        });

      if (uploadError) {
        console.error(`ImageUploadStorage: Upload error (attempt ${attempt}):`, {
          error: uploadError,
          errorMessage: uploadError.message,
          errorName: uploadError.name
        });
        
        lastError = uploadError;
        
        // Handle specific error types
        if (uploadError.message?.includes('RLS') || 
            uploadError.message?.includes('policy') ||
            uploadError.message?.includes('Unauthorized') ||
            uploadError.message?.includes('row-level security')) {
          console.error('ImageUploadStorage: RLS/Authorization error detected');
          
          // For RLS errors, try refreshing auth and retrying
          if (attempt < maxRetries) {
            console.log('ImageUploadStorage: Attempting session refresh for RLS error');
            const { error: refreshError } = await supabase.auth.refreshSession();
            if (refreshError) {
              console.error('ImageUploadStorage: Session refresh failed', refreshError);
            } else {
              console.log('ImageUploadStorage: Session refreshed successfully');
            }
            const delay = Math.pow(2, attempt) * 1000;
            console.log(`ImageUploadStorage: Retrying in ${delay}ms after RLS error...`);
            await new Promise(resolve => setTimeout(resolve, delay));
            continue;
          }
          throw uploadError;
        }
        
        // For other errors, use exponential backoff
        if (attempt < maxRetries) {
          const delay = Math.pow(2, attempt) * 1000;
          console.log(`ImageUploadStorage: Retrying in ${delay}ms...`);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }
        throw uploadError;
      }

      console.log('ImageUploadStorage: Upload successful', { filePath });
      break;
      
    } catch (error) {
      console.error(`ImageUploadStorage: Upload attempt ${attempt} failed:`, {
        error,
        errorMessage: error instanceof Error ? error.message : 'Unknown error',
        errorType: typeof error
      });
      
      lastError = error as Error;
      
      if (attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  if (lastError) {
    const errorMessage = lastError.message?.includes('RLS') || 
                        lastError.message?.includes('policy') || 
                        lastError.message?.includes('Unauthorized') ||
                        lastError.message?.includes('row-level security')
      ? 'Permission denied. Please refresh the page and try again.'
      : `Failed to upload image: ${lastError.message}. Please try again.`;
    
    console.error('ImageUploadStorage: All upload attempts failed', {
      finalError: lastError,
      errorMessage
    });
    
    toast.error(errorMessage);
    throw lastError;
  }
};

export const getPublicUrl = (filePath: string): string => {
  const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
  console.log('ImageUploadStorage: Generated public URL', { url: data.publicUrl });
  return data.publicUrl;
};

export const updateItemInDatabase = async (itemId: string, userId: string, file: File, filePath: string): Promise<void> => {
  console.log('ImageUploadStorage: Updating existing item', { itemId, filePath });
  
  try {
    const { error: updateError } = await supabase
      .from('items')
      .update({ 
        file_path: filePath,
        mime_type: file.type,
        file_size: file.size,
        updated_at: new Date().toISOString()
      })
      .eq('id', itemId)
      .eq('user_id', userId); // Additional safety check

    if (updateError) {
      console.error('ImageUploadStorage: Database update failed', {
        error: updateError,
        itemId,
        userId,
        filePath
      });
      
      // Try to clean up the uploaded file
      try {
        await supabase.storage.from('stash-media').remove([filePath]);
        console.log('ImageUploadStorage: Cleaned up uploaded file after DB error');
      } catch (cleanupError) {
        console.error('ImageUploadStorage: Failed to cleanup uploaded file', cleanupError);
      }
      
      throw updateError;
    }
    
    console.log('ImageUploadStorage: Database updated successfully');
  } catch (error) {
    console.error('ImageUploadStorage: Failed to update database', error);
    throw error;
  }
};
