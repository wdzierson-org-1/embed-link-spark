
import React, { useMemo } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useEditorImageUpload } from './editor/EditorImageUpload';
import EditorContainer from './editor/EditorContainer';

interface EditItemContentEditorProps {
  content: string;
  onContentChange: (content: string) => void;
  itemId?: string;
  editorInstanceKey?: string;
  isMaximized?: boolean;
}

const EditItemContentEditor = ({ 
  content, 
  onContentChange, 
  itemId, 
  editorInstanceKey, 
  isMaximized = false 
}: EditItemContentEditorProps) => {
  const { user, session } = useAuth();

  // Image upload functionality
  const { handleImageUpload } = useEditorImageUpload({ user, session, itemId });

  // Create stable editor key
  const effectiveEditorKey = useMemo(() => {
    const key = editorInstanceKey || `editor-${itemId || 'new'}-stable`;
    console.log('EditItemContentEditor: Generated stable editor key:', { key, itemId });
    return key;
  }, [editorInstanceKey, itemId]);

  // Enhanced onContentChange with debugging
  const handleContentChange = useMemo(() => {
    return (newContent: string) => {
      console.log('EditItemContentEditor: handleContentChange called:', {
        itemId,
        contentLength: newContent?.length,
        hasContent: !!newContent,
        editorKey: effectiveEditorKey
      });
      
      // Call the parent's onContentChange
      onContentChange(newContent);
      
      console.log('EditItemContentEditor: Parent onContentChange called successfully');
    };
  }, [onContentChange, itemId, effectiveEditorKey]);

  console.log('EditItemContentEditor: Rendering with props:', {
    itemId,
    contentLength: content?.length,
    hasContent: !!content,
    editorKey: effectiveEditorKey,
    isMaximized
  });

  return (
    <EditorContainer
      content={content}
      onContentChange={handleContentChange}
      handleImageUpload={handleImageUpload}
      editorKey={effectiveEditorKey}
      isMaximized={isMaximized}
    />
  );
};

export default EditItemContentEditor;
