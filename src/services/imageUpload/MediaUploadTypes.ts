
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

export const SUPPORTED_IMAGE_TYPES = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/svg+xml',
  'image/bmp',
  'image/tiff'
];

// File size limits for different media types
export const MAX_FILE_SIZE_MB = 20;
export const MAX_VIDEO_SIZE_MB = 50; // Supabase free tier limit
export const MAX_AUDIO_SIZE_MB = 50;
