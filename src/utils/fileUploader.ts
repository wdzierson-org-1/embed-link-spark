
import { supabase } from '@/integrations/supabase/client';

export const uploadFile = async (file: File, userId: string): Promise<string> => {
  const fileExt = file.name.split('.').pop();
  const fileName = `${Date.now()}.${fileExt}`;
  const filePath = `${userId}/${fileName}`;

  console.log('Uploading file to path:', filePath);

  const { error: uploadError } = await supabase.storage
    .from('stash-media')
    .upload(filePath, file);

  if (uploadError) {
    console.error('Upload error:', uploadError);
    throw uploadError;
  }

  console.log('File uploaded successfully');
  return filePath;
};
