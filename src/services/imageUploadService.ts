
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

  // Validate file type and size first
  if (!file.type.includes("image/")) {
    toast.error("File type not supported.");
    throw new Error("File type not supported");
  }
  
  if (file.size / 1024 / 1024 > 20) {
    toast.error("File size too big (max 20MB).");
    throw new Error("File size too big (max 20MB)");
  }

  // Generate file path immediately
  const fileExt = file.name.split('.').pop();
  const fileName = `${Date.now()}.${fileExt}`;
  const filePath = `${userId}/${fileName}`;

  console.log('ImageUploadService: Generated file path', { filePath });

  // Enhanced authentication validation with session refresh
  console.log('ImageUploadService: Refreshing session before upload');
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  
  if (sessionError) {
    console.error('ImageUploadService: Session refresh failed', sessionError);
    throw new Error('Failed to refresh authentication session');
  }

  if (!session || !session.user) {
    console.error('ImageUploadService: No valid session found after refresh');
    throw new Error('Authentication required for file upload');
  }

  // Log detailed authentication information
  console.log('ImageUploadService: Authentication details', {
    sessionUserId: session.user.id,
    providedUserId: userId,
    sessionValid: !!session,
    userMatches: session.user.id === userId,
    sessionExpiry: session.expires_at,
    currentTime: new Date().toISOString()
  });

  // Verify user ID matches session
  if (session.user.id !== userId) {
    console.error('ImageUploadService: User ID mismatch', { 
      sessionUserId: session.user.id, 
      providedUserId: userId 
    });
    throw new Error('User ID mismatch');
  }

  // Upload to storage with enhanced error handling and retry
  const maxRetries = 3;
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`ImageUploadService: Upload attempt ${attempt}/${maxRetries}`, {
        filePath,
        fileSize: file.size,
        sessionUser: session.user.id
      });

      // Re-validate session before each upload attempt
      if (attempt > 1) {
        console.log('ImageUploadService: Re-validating session for retry');
        const { data: { session: retrySession }, error: retrySessionError } = await supabase.auth.getSession();
        
        if (retrySessionError || !retrySession) {
          console.error('ImageUploadService: Session validation failed on retry', retrySessionError);
          throw new Error('Session expired during retry');
        }
      }
      
      const { error: uploadError } = await supabase.storage
        .from('stash-media')
        .upload(filePath, file);

      if (uploadError) {
        console.error(`ImageUploadService: Upload error (attempt ${attempt}):`, {
          error: uploadError,
          errorMessage: uploadError.message,
          statusCode: uploadError.statusCode,
          errorCode: uploadError.error
        });
        
        lastError = uploadError;
        
        // Handle specific error types
        if (uploadError.message?.includes('RLS') || 
            uploadError.message?.includes('policy') ||
            uploadError.statusCode === '403') {
          console.error('ImageUploadService: RLS/Authorization error detected');
          
          // If this is an RLS error and we haven't exhausted retries, try refreshing auth
          if (attempt < maxRetries) {
            console.log('ImageUploadService: Attempting session refresh for RLS error');
            const { error: refreshError } = await supabase.auth.refreshSession();
            if (refreshError) {
              console.error('ImageUploadService: Session refresh failed', refreshError);
            } else {
              console.log('ImageUploadService: Session refreshed successfully');
              const delay = Math.pow(2, attempt) * 1000;
              console.log(`ImageUploadService: Retrying in ${delay}ms after RLS error...`);
              await new Promise(resolve => setTimeout(resolve, delay));
              continue;
            }
          }
          throw uploadError;
        }
        
        // For other errors, use exponential backoff
        if (attempt < maxRetries) {
          const delay = Math.pow(2, attempt) * 1000;
          console.log(`ImageUploadService: Retrying in ${delay}ms...`);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }
        throw uploadError;
      }

      console.log('ImageUploadService: Upload successful', { filePath });
      break;
      
    } catch (error) {
      console.error(`ImageUploadService: Upload attempt ${attempt} failed:`, {
        error,
        errorMessage: error instanceof Error ? error.message : 'Unknown error',
        errorType: typeof error
      });
      
      lastError = error as Error;
      
      // Don't retry for authentication or permission errors unless it's the first attempt
      if (error instanceof Error && 
          (error.message?.includes('Session expired') || 
           error.message?.includes('User ID mismatch')) &&
          attempt === 1) {
        // Allow one retry for session issues
        if (attempt < maxRetries) {
          const delay = 1000; // Shorter delay for auth issues
          console.log(`ImageUploadService: Retrying auth error in ${delay}ms...`);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }
      }
      
      if (attempt < maxRetries && 
          !(error instanceof Error && 
            (error.message?.includes('RLS') || 
             error.message?.includes('policy')))) {
        const delay = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }

  if (lastError) {
    const errorMessage = lastError.message?.includes('RLS') || 
                        lastError.message?.includes('policy') || 
                        lastError.message?.includes('Unauthorized')
      ? 'Permission denied. Please refresh the page and try again.'
      : `Failed to upload image: ${lastError.message}. Please try again.`;
    
    console.error('ImageUploadService: All upload attempts failed', {
      finalError: lastError,
      errorMessage
    });
    
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
      // Re-validate session before database update
      const { data: { session: dbSession }, error: dbSessionError } = await supabase.auth.getSession();
      if (dbSessionError || !dbSession) {
        console.error('ImageUploadService: Session validation failed before DB update', dbSessionError);
        throw new Error('Session expired before database update');
      }

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
        console.error('ImageUploadService: Database update failed', {
          error: updateError,
          itemId,
          userId,
          filePath
        });
        
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
