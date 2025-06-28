
import { toast } from 'sonner';
import type { ImageUploadOptions, ImageUploadResult } from './ImageUploadTypes';
import { validateImageFile, generateFilePath } from './ImageUploadValidation';
import { validateAuthentication } from './ImageUploadAuth';
import { uploadFileToStorage, getPublicUrl, updateItemInDatabase } from './ImageUploadStorage';

export const uploadImage = async (options: ImageUploadOptions): Promise<ImageUploadResult> => {
  const { file, userId, itemId, onProgress } = options;
  
  console.log('ImageUploadService: Starting upload for Novel editor', { 
    fileName: file.name, 
    fileSize: file.size, 
    fileType: file.type,
    userId,
    itemId,
    isUpdate: !!itemId
  });

  // Validate the file
  validateImageFile(file);

  // Generate file path immediately
  const filePath = generateFilePath(file, userId);

  // Validate authentication
  await validateAuthentication(userId);

  // Upload to storage with enhanced error handling and retry
  await uploadFileToStorage(file, filePath, userId);

  // Get public URL - this is what Novel needs immediately
  const publicUrl = getPublicUrl(filePath);
  
  console.log('ImageUploadService: Upload completed, returning URL for Novel', {
    filePath,
    publicUrl,
    urlLength: publicUrl.length
  });

  // Verify the URL is properly constructed
  if (!publicUrl || !publicUrl.includes('supabase')) {
    console.error('ImageUploadService: Invalid URL generated', { publicUrl });
    throw new Error('Failed to generate valid image URL');
  }

  // If this is an update to an existing item, update the database record
  if (itemId) {
    await updateItemInDatabase(itemId, userId, file, filePath);
  }

  toast.success('Image uploaded successfully!');
  
  return {
    publicUrl,
    filePath
  };
};

// Novel-specific upload function that returns just the URL
export const uploadImageForNovel = async (file: File, userId: string, itemId?: string): Promise<string> => {
  console.log('ImageUploadService: Novel upload wrapper called', {
    fileName: file.name,
    userId,
    itemId
  });
  
  const result = await uploadImage({
    file,
    userId,
    itemId
  });
  
  console.log('ImageUploadService: Returning URL to Novel:', result.publicUrl);
  return result.publicUrl;
};

// Export types for convenience
export type { ImageUploadOptions, ImageUploadResult } from './ImageUploadTypes';
