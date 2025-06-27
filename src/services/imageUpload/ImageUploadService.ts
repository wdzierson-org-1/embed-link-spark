
import { toast } from 'sonner';
import type { ImageUploadOptions, ImageUploadResult } from './ImageUploadTypes';
import { validateImageFile, generateFilePath } from './ImageUploadValidation';
import { validateAuthentication } from './ImageUploadAuth';
import { uploadFileToStorage, getPublicUrl, updateItemInDatabase } from './ImageUploadStorage';

export const uploadImage = async (options: ImageUploadOptions): Promise<ImageUploadResult> => {
  const { file, userId, itemId, onProgress } = options;
  
  console.log('ImageUploadService: Starting upload', { 
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

  // Get public URL
  const publicUrl = getPublicUrl(filePath);

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

// Export types for convenience
export type { ImageUploadOptions, ImageUploadResult } from './ImageUploadTypes';
