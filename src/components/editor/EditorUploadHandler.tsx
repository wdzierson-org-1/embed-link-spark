
import { useCallback } from 'react';

interface EditorUploadHandlerProps {
  handleImageUpload?: (file: File) => Promise<string>;
  editorKey: string;
  onContentChange?: (content: string) => void;
}

export const useEditorUploadHandler = ({ handleImageUpload, editorKey, onContentChange }: EditorUploadHandlerProps) => {
  return useCallback(async (file: File, view: any, pos: number) => {
    console.log('EditorContainer: Upload function called', {
      fileName: file.name,
      fileType: file.type,
      fileSize: file.size,
      editorKey
    });

    if (!handleImageUpload) {
      console.error('EditorContainer: No upload handler provided');
      return;
    }

    try {
      const url = await handleImageUpload(file);
      console.log('EditorContainer: Upload successful, inserting image', { url });
      
      // Insert the image at the specified position
      const { schema } = view.state;
      const node = schema.nodes.image?.create({ src: url });
      if (node) {
        const transaction = view.state.tr.replaceWith(pos, pos, node);
        view.dispatch(transaction);
        
        // CRITICAL: Trigger content change after image insertion
        setTimeout(() => {
          console.log('EditorContainer: Triggering content change after image upload');
          if (onContentChange) {
            const json = view.state.doc.toJSON ? view.state.doc.toJSON() : { type: 'doc', content: [] };
            const jsonString = JSON.stringify(json);
            onContentChange(jsonString);
            console.log('EditorContainer: Content change triggered after image upload');
          }
        }, 100); // Small delay to ensure DOM is updated
      }
    } catch (error) {
      console.error('EditorContainer: Upload failed', error);
      // Error handling is done in the upload function itself
    }
  }, [handleImageUpload, editorKey, onContentChange]);
};
