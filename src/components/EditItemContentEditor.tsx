
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
    console.log('Generated stable editor key:', { key });
    return key;
  }, [editorInstanceKey, itemId]);

  return (
    <EditorContainer
      content={content}
      onContentChange={onContentChange}
      handleImageUpload={handleImageUpload}
      editorKey={effectiveEditorKey}
      isMaximized={isMaximized}
    />
  );
};

export default EditItemContentEditor;
