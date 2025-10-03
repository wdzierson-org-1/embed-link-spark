
import { supabase } from '@/integrations/supabase/client';
import { MAX_VIDEO_SIZE_MB, MAX_AUDIO_SIZE_MB, MAX_FILE_SIZE_MB } from '@/services/imageUpload/MediaUploadTypes';

export const uploadFile = async (file: File, userId: string): Promise<string> => {
  console.log('FileUploader: Starting upload', { 
    fileName: file.name, 
    fileSize: file.size, 
    userId 
  });

  // Validate file size as backup
  const fileSizeMB = file.size / 1024 / 1024;
  let maxSize = MAX_FILE_SIZE_MB;
  let fileTypeLabel = 'file';
  
  if (file.type.startsWith('video/')) {
    maxSize = MAX_VIDEO_SIZE_MB;
    fileTypeLabel = 'video';
  } else if (file.type.startsWith('audio/')) {
    maxSize = MAX_AUDIO_SIZE_MB;
    fileTypeLabel = 'audio';
  }
  
  if (fileSizeMB > maxSize) {
    const errorMsg = fileTypeLabel === 'video' 
      ? `File "${file.name}" is ${fileSizeMB.toFixed(1)}MB. Stash only accepts videos less than ${maxSize}MB. Perhaps you can compress the video further?`
      : `File "${file.name}" is ${fileSizeMB.toFixed(1)}MB. Maximum ${fileTypeLabel} size is ${maxSize}MB.`;
    const error = new Error(errorMsg);
    console.error('FileUploader: File too large', { fileSizeMB, maxSize, fileType: file.type });
    throw error;
  }

  // Enhanced authentication validation
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  if (sessionError || !session || !session.user) {
    console.error('FileUploader: Authentication check failed', sessionError);
    throw new Error('Authentication required for file upload');
  }

  // Verify user ID matches session
  if (session.user.id !== userId) {
    console.error('FileUploader: User ID mismatch', { 
      sessionUserId: session.user.id, 
      providedUserId: userId 
    });
    throw new Error('User ID mismatch');
  }

  const fileExt = file.name.split('.').pop();
  const fileName = `${Date.now()}.${fileExt}`;
  const filePath = `${userId}/${fileName}`;

  console.log('FileUploader: Uploading to path', { 
    filePath, 
    sessionUser: session.user.id,
    hasSession: !!session
  });

  const { error: uploadError } = await supabase.storage
    .from('stash-media')
    .upload(filePath, file);

  if (uploadError) {
    console.error('FileUploader: Upload error', uploadError);
    throw uploadError;
  }

  console.log('FileUploader: File uploaded successfully');
  return filePath;
};
