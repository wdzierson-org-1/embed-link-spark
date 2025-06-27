
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
        
        // CRITICAL: Multiple attempts to trigger content change after image insertion
        const triggerContentChange = () => {
          if (onContentChange) {
            console.log('EditorUploadHandler: Attempting to extract content after image insertion');
            const json = view.state.doc.toJSON ? view.state.doc.toJSON() : { type: 'doc', content: [] };
            const jsonString = JSON.stringify(json);
            
            console.log('EditorUploadHandler: Content extracted after image upload:', {
              contentLength: jsonString.length,
              hasImageInContent: jsonString.includes('"type":"image"'),
              editorKey
            });
            
            onContentChange(jsonString);
            console.log('EditorUploadHandler: Content change triggered successfully after image upload');
          }
        };

        // Immediate attempt
        triggerContentChange();
        
        // Backup attempts with increasing delays to ensure editor state is fully updated
        setTimeout(triggerContentChange, 50);
        setTimeout(triggerContentChange, 150);
        setTimeout(triggerContentChange, 300);
        
        console.log('EditorUploadHandler: Set up multiple content change triggers for image upload');
      }
    } catch (error) {
      console.error('EditorUploadHandler: Upload failed', error);
      // Error handling is done in the upload function itself
    }
  }, [handleImageUpload, editorKey, onContentChange]);
};
