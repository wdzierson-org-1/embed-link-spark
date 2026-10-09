
import type { UploadFn } from 'novel';

export interface EditorContainerProps {
  content: string;
  onContentChange: (content: string) => void;
  handleImageUpload?: UploadFn;
  editorKey: string;
  isMaximized?: boolean;
  /** No box of its own: the notes section draws the field around it */
  inline?: boolean;
}
