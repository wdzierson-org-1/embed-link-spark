
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export interface ImageUploadOptions {
  file: File;
  userId: string;
  itemId?: string; // If provided, this is an update to existing item
  onProgress?: (progress: number) => void;
}

export interface ImageUploadResult {
  publicUrl: string;
  filePath: string;
}

export const uploadImage = async (options: ImageUploadOptions): Promise<ImageUploadResult> => {
  const { file, userId, itemId, onProgress } = options;
  
  console.log('ImageUploadService: Starting upload', { 
    fileName: file.name, 
    fileSize: file.size, 
    userId,
    itemId,
    isUpdate: !!itemId
  });

  // Enhanced authentication validation
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError || !session || !session.user) {
    console.error('ImageUploadService: Authentication check failed', sessionError);
    throw new Error('Authentication required for file upload');
  }

  // Verify user ID matches session
  if (session.user.id !== userId) {
    console.error('ImageUploadService: User ID mismatch', { 
      sessionUserId: session.user.id, 
      providedUserId: userId 
    });
    throw new Error('User ID mismatch');
  }

  // Validate file type
  if (!file.type.includes("image/")) {
    toast.error("File type not supported.");
    throw new Error("File type not supported");
  }
  
  if (file.size / 1024 / 1024 > 20) {
    toast.error("File size too big (max 20MB).");
    throw new Error("File size too big (max 20MB)");
  }

  const fileExt = file.name.split('.').pop();
  const fileName = `${Date.now()}.${fileExt}`;
  const filePath = `${userId}/${fileName}`;

  console.log('ImageUploadService: Uploading to path', { 
    filePath, 
    sessionUser: session.user.id,
    hasSession: !!session
  });

  // Upload to storage with retry mechanism
  const maxRetries = 3;
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`ImageUploadService: Upload attempt ${attempt}/${maxRetries}`);
      
      const { error: uploadError } = await supabase.storage
        .from('stash-media')
        .upload(filePath, file);

      if (uploadError) {
        console.error(`ImageUploadService: Upload error (attempt ${attempt}):`, uploadError);
        lastError = uploadError;
        
        // If it's an RLS error, don't retry
        if (uploadError.message?.includes('RLS') || uploadError.message?.includes('policy')) {
          console.error('ImageUploadService: RLS policy violation detected');
          throw uploadError;
        }
        
        if (attempt < maxRetries) {
          const delay = Math.pow(2, attempt) * 1000; // Exponential backoff
          console.log(`ImageUploadService: Retrying in ${delay}ms...`);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }
        throw uploadError;
      }

      console.log('ImageUploadService: Upload successful');
      break;
      
    } catch (error) {
      console.error(`ImageUploadService: Upload attempt ${attempt} failed:`, error);
      lastError = error as Error;
      
      // Don't retry for authentication or permission errors
      if (error instanceof Error && 
          (error.message?.includes('RLS') || 
           error.message?.includes('policy') || 
           error.message?.includes('Session expired'))) {
        break;
      }
      
      if (attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  if (lastError) {
    const errorMessage = lastError.message?.includes('RLS') || lastError.message?.includes('policy') 
      ? 'Permission denied. Please refresh the page and try again.'
      : 'Failed to upload image. Please try again.';
    
    toast.error(errorMessage);
    throw lastError;
  }

  // Get public URL
  const { data } = supabase.storage.from('stash-media').getPublicUrl(filePath);
  console.log('ImageUploadService: Generated public URL', { url: data.publicUrl });

  // If this is an update to an existing item, update the database record
  if (itemId) {
    console.log('ImageUploadService: Updating existing item', { itemId, filePath });
    
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
        console.error('ImageUploadService: Database update failed', updateError);
        
        // Try to clean up the uploaded file
        try {
          await supabase.storage.from('stash-media').remove([filePath]);
          console.log('ImageUploadService: Cleaned up uploaded file after DB error');
        } catch (cleanupError) {
          console.error('ImageUploadService: Failed to cleanup uploaded file', cleanupError);
        }
        
        throw updateError;
      }
      
      console.log('ImageUploadService: Database updated successfully');
    } catch (error) {
      console.error('ImageUploadService: Failed to update database', error);
      throw error;
    }
  }

  toast.success('Image uploaded successfully!');
  
  return {
    publicUrl: data.publicUrl,
    filePath
  };
};
