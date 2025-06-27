
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
        
        // ENHANCED: More aggressive content extraction with validation
        const extractAndSaveContent = async (attempt: number = 1) => {
          console.log(`EditorUploadHandler: Content extraction attempt ${attempt}`);
          
          // Wait for editor state to update
          await new Promise(resolve => setTimeout(resolve, attempt * 100));
          
          try {
            const json = view.state.doc.toJSON ? view.state.doc.toJSON() : { type: 'doc', content: [] };
            const jsonString = JSON.stringify(json);
            
            // Validate that the image is actually in the content
            const hasImageInContent = jsonString.includes('"type":"image"') && jsonString.includes(url);
            
            console.log(`EditorUploadHandler: Attempt ${attempt} - Content extracted:`, {
              contentLength: jsonString.length,
              hasImageInContent,
              imageUrl: url,
              editorKey
            });
            
            if (hasImageInContent && onContentChange) {
              console.log('EditorUploadHandler: Image found in content, triggering save');
              onContentChange(jsonString);
              return true; // Success
            }
            
            // If image not found and we haven't tried too many times, try again
            if (attempt < 8 && !hasImageInContent) {
              console.log(`EditorUploadHandler: Image not found in content, retrying (attempt ${attempt + 1})`);
              return await extractAndSaveContent(attempt + 1);
            }
            
            // Final attempt - save anyway if we have onContentChange
            if (onContentChange && attempt >= 8) {
              console.log('EditorUploadHandler: Final attempt - saving content regardless');
              onContentChange(jsonString);
              return true;
            }
            
            return false;
          } catch (error) {
            console.error(`EditorUploadHandler: Error in content extraction attempt ${attempt}:`, error);
            if (attempt < 5) {
              return await extractAndSaveContent(attempt + 1);
            }
            return false;
          }
        };

        // Start the content extraction process
        extractAndSaveContent();
      }
    } catch (error) {
      console.error('EditorUploadHandler: Upload failed', error);
    }
  }, [handleImageUpload, editorKey, onContentChange]);
};
