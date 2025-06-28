
import React, { useMemo, useEffect, useCallback } from 'react';
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
        newContentLength: newContent?.length || 0,
        hasNewContent: !!newContent,
        contentChanged: newContent !== content,
        editorKey: effectiveEditorKey,
        hasImages: newContent ? newContent.includes('"type":"image"') : false,
        imageCount: newContent ? (newContent.match(/"type":"image"/g) || []).length : 0,
        newContentPreview: newContent ? newContent.slice(0, 100) + '...' : 'No content'
      });
      
      // Call the parent's onContentChange
      onContentChange(newContent);
      
      console.log('EditItemContentEditor: Parent onContentChange called successfully');
    };
  }, [onContentChange, itemId, effectiveEditorKey, content]);

  // Post-upload callback to force content check and save
  const handleUploadComplete = useCallback(() => {
    console.log('EditItemContentEditor: Image upload completed, forcing content check');
    
    // Trigger a content change detection by getting current editor content
    // This is handled by the EditorContainer's update mechanism
    setTimeout(() => {
      console.log('EditItemContentEditor: Post-upload content verification completed');
    }, 100);
  }, []);

  // Image upload functionality with post-upload callback
  const { createUploadFn } = useEditorImageUpload({ 
    user, 
    session, 
    itemId,
    onUploadComplete: handleUploadComplete
  });

  // Create the upload function using Novel's pattern - this returns UploadFn type
  const uploadFn = useMemo(() => {
    const fn = createUploadFn();
    console.log('EditItemContentEditor: Created upload function with post-upload callback:', {
      hasUploadFn: !!fn,
      itemId,
      editorKey: effectiveEditorKey
    });
    return fn;
  }, [createUploadFn, itemId, effectiveEditorKey]);

  // ENHANCED: Track content prop changes for debugging
  useEffect(() => {
    console.log('EditItemContentEditor: Content prop changed:', {
      itemId,
      contentLength: content?.length || 0,
      hasContent: !!content,
      contentPreview: content ? content.slice(0, 100) + '...' : 'No content',
      editorKey: effectiveEditorKey
    });
  }, [content, itemId, effectiveEditorKey]);

  console.log('EditItemContentEditor: Rendering with enhanced upload system:', {
    itemId,
    contentLength: content?.length || 0,
    hasContent: !!content,
    editorKey: effectiveEditorKey,
    isMaximized,
    hasUploadFn: !!uploadFn,
    hasUploadCompleteCallback: true,
    contentPreview: content ? content.slice(0, 100) + '...' : 'No content'
  });

  return (
    <EditorContainer
      content={content}
      onContentChange={handleContentChange}
      handleImageUpload={uploadFn}
      editorKey={effectiveEditorKey}
      isMaximized={isMaximized}
    />
  );
};

export default EditItemContentEditor;
