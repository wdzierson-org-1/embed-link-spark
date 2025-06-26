
import { supabase } from '@/integrations/supabase/client';

export const uploadFile = async (file: File, userId: string): Promise<string> => {
  console.log('FileUploader: Starting upload', { 
    fileName: file.name, 
    fileSize: file.size, 
    userId 
  });

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
