
import { toast } from 'sonner';
import { SUPPORTED_IMAGE_TYPES, MAX_FILE_SIZE_MB } from './MediaUploadTypes';

export const validateImageFile = (file: File): void => {
  console.log('ImageUploadValidation: Validating file', { 
    fileName: file.name, 
    fileSize: file.size, 
    fileType: file.type
  });

  // Enhanced file type validation
  if (!SUPPORTED_IMAGE_TYPES.includes(file.type.toLowerCase())) {
    const errorMsg = `File type "${file.type}" not supported. Supported types: ${SUPPORTED_IMAGE_TYPES.join(', ')}`;
    console.error('ImageUploadValidation: Invalid file type', { fileType: file.type, supportedTypes: SUPPORTED_IMAGE_TYPES });
    toast.error(errorMsg);
    throw new Error(errorMsg);
  }
  
  if (file.size / 1024 / 1024 > MAX_FILE_SIZE_MB) {
    const errorMsg = `File size too big (max ${MAX_FILE_SIZE_MB}MB).`;
    console.error('ImageUploadValidation: File too large', { fileSize: file.size, maxSize: MAX_FILE_SIZE_MB * 1024 * 1024 });
    toast.error(errorMsg);
    throw new Error(errorMsg);
  }

  console.log('ImageUploadValidation: File validation passed');
};

export const generateFilePath = (file: File, userId: string): string => {
  const fileExt = file.name.split('.').pop()?.toLowerCase() || 'jpg';
  const fileName = `${Date.now()}-${Math.random().toString(36).substring(7)}.${fileExt}`;
  const filePath = `${userId}/${fileName}`;

  console.log('ImageUploadValidation: Generated file path', { filePath });
  return filePath;
};
