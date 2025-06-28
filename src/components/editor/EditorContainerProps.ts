
import type { EditorInstance } from 'novel';

export interface EditorContainerProps {
  content: string;
  onContentChange: (content: string) => void;
  onUpdate?: (editor: EditorInstance) => void;
  handleImageUpload: (file: File) => Promise<string>;
  editorKey: string;
  isMaximized?: boolean;
  onEditorReady?: (editor: EditorInstance) => void;
}
