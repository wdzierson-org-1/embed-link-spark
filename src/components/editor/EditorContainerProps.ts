
import type { UploadFn } from 'novel';

export interface EditorContainerProps {
  content: string;
  onContentChange: (content: string) => void;
  handleImageUpload?: UploadFn;
  editorKey: string;
  isMaximized?: boolean;
}
