
export interface EditorContainerProps {
  content: string;
  onContentChange: (content: string) => void;
  handleImageUpload?: (file: File) => Promise<string>;
  editorKey: string;
  isMaximized?: boolean;
}
