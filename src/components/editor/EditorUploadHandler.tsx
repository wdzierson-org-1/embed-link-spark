
import { useCallback } from 'react';

interface EditorUploadHandlerProps {
  handleImageUpload?: (file: File) => Promise<string>;
  editorKey: string;
  onContentChange?: (content: string) => void;
}

export const useEditorUploadHandler = ({ handleImageUpload, editorKey, onContentChange }: EditorUploadHandlerProps) => {
  return useCallback(async (file: File, view: any, pos: number) => {
    console.log('EditorUploadHandler: Upload function called', {
      fileName: file.name,
      fileType: file.type,
      fileSize: file.size,
      editorKey,
      hasOnContentChange: !!onContentChange
    });

    if (!handleImageUpload) {
      console.error('EditorUploadHandler: No upload handler provided');
      return;
    }

    try {
      const url = await handleImageUpload(file);
      console.log('EditorUploadHandler: Upload successful, inserting image', { url });
      
      // Insert the image at the specified position
      const { schema } = view.state;
      const node = schema.nodes.image?.create({ src: url });
      if (node) {
        const transaction = view.state.tr.replaceWith(pos, pos, node);
        view.dispatch(transaction);
        
        console.log('EditorUploadHandler: Image inserted into editor - onUpdate should trigger save');
        
        // The editor's onUpdate event will handle saving the content
        // We don't need to manually extract and save content here
        // The native editor update mechanism will trigger our handleEditorUpdate function
      }
    } catch (error) {
      console.error('EditorUploadHandler: Upload failed', error);
    }
  }, [handleImageUpload, editorKey, onContentChange]);
};
