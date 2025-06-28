
import React, { useMemo, useEffect, useCallback, useRef } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useEditorImageUpload } from './editor/EditorImageUpload';
import EditorContainer from './editor/EditorContainer';
import { useIsMobile } from '@/hooks/use-mobile';
import type { EditorInstance } from 'novel';

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
  const isMobile = useIsMobile();
  const editorRef = useRef<EditorInstance | null>(null);
  const [mobileRefreshKey, setMobileRefreshKey] = React.useState(0);

  // Create stable editor key
  const effectiveEditorKey = useMemo(() => {
    const baseKey = editorInstanceKey || `editor-${itemId || 'new'}-stable`;
    // Add mobile refresh key to force re-initialization when needed
    const finalKey = isMobile ? `${baseKey}-mobile-${mobileRefreshKey}` : baseKey;
    console.log('EditItemContentEditor: Generated editor key:', { 
      baseKey, 
      finalKey, 
      itemId, 
      isMobile,
      mobileRefreshKey 
    });
    return finalKey;
  }, [editorInstanceKey, itemId, isMobile, mobileRefreshKey]);

  // Mobile editor initialization fix - force refresh after mount
  useEffect(() => {
    if (isMobile && itemId && content !== undefined) {
      console.log('EditItemContentEditor: Mobile initialization for item', {
        itemId,
        contentLength: content?.length || 0,
        hasContent: !!content,
        currentRefreshKey: mobileRefreshKey
      });

      // Small delay to ensure proper mobile initialization
      const refreshTimer = setTimeout(() => {
        console.log('EditItemContentEditor: Triggering mobile editor refresh');
        setMobileRefreshKey(prev => prev + 1);
      }, 150);

      return () => clearTimeout(refreshTimer);
    }
  }, [itemId, isMobile]); // Only trigger when item changes or mobile state changes

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
        newContentPreview: newContent ? newContent.slice(0, 100) + '...' : 'No content',
        isMobile
      });
      
      // Call the parent's onContentChange
      onContentChange(newContent);
      
      console.log('EditItemContentEditor: Parent onContentChange called successfully');
    };
  }, [onContentChange, itemId, effectiveEditorKey, content, isMobile]);

  // ENHANCED: Post-upload callback to explicitly trigger save with current editor content
  const handleUploadComplete = useCallback(() => {
    console.log('EditItemContentEditor: Image upload completed, triggering explicit save');
    
    // Wait a bit longer to ensure Novel has fully processed the image URL replacement
    setTimeout(() => {
      if (editorRef.current) {
        const json = editorRef.current.getJSON();
        const jsonString = JSON.stringify(json);
        
        console.log('EditItemContentEditor: Explicitly triggering save with current editor content:', {
          itemId,
          contentLength: jsonString.length,
          hasImages: jsonString.includes('"type":"image"'),
          imageCount: (jsonString.match(/"type":"image"/g) || []).length,
          hasFinalUrls: jsonString.includes('"src":"http'),
          saveReason: 'Post-upload explicit save'
        });
        
        // Explicitly call onContentChange to trigger the save mechanism
        handleContentChange(jsonString);
      } else {
        console.warn('EditItemContentEditor: Editor ref not available for post-upload save');
      }
    }, 750); // Increased delay to ensure Novel completes URL replacement
  }, [itemId, handleContentChange]);

  // Image upload functionality with enhanced post-upload callback
  const { createUploadFn } = useEditorImageUpload({ 
    user, 
    session, 
    itemId,
    onUploadComplete: handleUploadComplete
  });

  // Create the upload function using Novel's pattern - this returns UploadFn type
  const uploadFn = useMemo(() => {
    const fn = createUploadFn();
    console.log('EditItemContentEditor: Created upload function with explicit save callback:', {
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
      editorKey: effectiveEditorKey,
      isMobile,
      mobileRefreshKey
    });
  }, [content, itemId, effectiveEditorKey, isMobile, mobileRefreshKey]);

  console.log('EditItemContentEditor: Rendering with mobile initialization fix:', {
    itemId,
    contentLength: content?.length || 0,
    hasContent: !!content,
    editorKey: effectiveEditorKey,
    isMaximized,
    hasUploadFn: !!uploadFn,
    hasExplicitSaveCallback: true,
    contentPreview: content ? content.slice(0, 100) + '...' : 'No content',
    isMobile,
    mobileRefreshKey
  });

  return (
    <EditorContainer
      content={content}
      onContentChange={handleContentChange}
      handleImageUpload={uploadFn}
      editorKey={effectiveEditorKey}
      isMaximized={isMaximized}
      onEditorReady={(editor) => {
        editorRef.current = editor;
        console.log('EditItemContentEditor: Editor instance stored in ref for explicit saves', {
          isMobile,
          itemId
        });
      }}
    />
  );
};

export default EditItemContentEditor;
