/**
 * Small formatting helpers for the detail panel's facts (Details drawer,
 * player strip). Pure functions, no item-shape assumptions beyond scalars.
 */

/** Human file size — whole bytes below 1 KB, one decimal above */
export const formatBytes = (bytes?: number | null): string => {
  if (!bytes || bytes <= 0 || !Number.isFinite(bytes)) return '';
  if (bytes < 1024) return `${Math.round(bytes)} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
};

/** Seconds → m:ss (or h:mm:ss past the hour) */
export const formatClock = (seconds?: number | null): string => {
  if (seconds == null || !Number.isFinite(seconds) || seconds < 0) return '';
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
};

/** Last path segment of a storage path (empty for external URLs) */
export const fileBasename = (filePath?: string | null): string => {
  if (!filePath || filePath.startsWith('http')) return '';
  return filePath.split('/').pop() ?? '';
};

const MIME_EXT: Record<string, string> = {
  'audio/mpeg': 'MP3',
  'audio/mp3': 'MP3',
  'audio/mp4': 'M4A',
  'audio/x-m4a': 'M4A',
  'audio/m4a': 'M4A',
  'audio/aac': 'AAC',
  'audio/wav': 'WAV',
  'audio/webm': 'WEBM',
  'audio/ogg': 'OGG',
  'video/mp4': 'MP4',
  'video/quicktime': 'MOV',
  'video/webm': 'WEBM',
  'application/pdf': 'PDF',
  'application/msword': 'DOC',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'DOCX',
  'text/plain': 'TXT',
  'image/jpeg': 'JPG',
  'image/png': 'PNG',
  'image/heic': 'HEIC',
  'image/webp': 'WEBP',
  'image/gif': 'GIF',
};

/** Short format label ("M4A", "PDF") from a filename or mime type */
export const fileExtensionLabel = (fileName?: string | null, mimeType?: string | null): string => {
  if (mimeType && MIME_EXT[mimeType.toLowerCase()]) return MIME_EXT[mimeType.toLowerCase()];
  if (fileName && fileName.includes('.')) {
    const ext = fileName.split('.').pop() ?? '';
    if (ext.length >= 2 && ext.length <= 5) return ext.toUpperCase();
  }
  const subtype = mimeType?.split('/')[1];
  return subtype ? subtype.toUpperCase() : '';
};
