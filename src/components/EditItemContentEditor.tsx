
import React, { useMemo, useEffect, useCallback, useRef } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useEditorImageUpload } from './editor/EditorImageUpload';
import EditorContainer from './editor/EditorContainer';
import { useDebouncedCallback } from 'use-debounce';
import type { EditorInstance } from 'novel';

interface EditItemContentEditorProps {
  initialContent: string;
  onContentChange: (content: string) => void;
  itemId?: string;
  editorInstanceKey?: string;
  isMaximized?: boolean;
}

const EditItemContentEditor = ({ 
  initialContent, 
  onContentChange, 
  itemId, 
  editorInstanceKey, 
  isMaximized = false 
}: EditItemContentEditorProps) => {
  const { user, session } = useAuth();
  const editorRef = useRef<EditorInstance | null>(null);
  const hasInitialized = useRef(false);

  // Create truly stable editor key - only changes when itemId changes
  const stableEditorKey = useMemo(() => {
    const key = `editor-${itemId || 'new'}-stable`;
    console.log('EditItemContentEditor: Created stable editor key:', { key, itemId });
    return key;
  }, [itemId]);

  // Debounced save function following Novel's pattern
  const debouncedSave = useDebouncedCallback((content: string) => {
    console.log('EditItemContentEditor: Debounced save triggered:', {
      itemId,
      contentLength: content?.length || 0,
      hasImages: content ? content.includes('"type":"image"') : false
    });
    
    // Immediate localStorage save (like Novel does)
    if (itemId) {
      try {
        localStorage.setItem(`draft-${itemId}`, content);
        console.log('EditItemContentEditor: Saved to localStorage');
      } catch (error) {
        console.error('EditItemContentEditor: localStorage save failed:', error);
      }
    }
    
    // Call parent's onContentChange for server save
    onContentChange(content);
  }, 500);

  // Handle editor updates - following Novel's pattern exactly
  const handleEditorUpdate = useCallback((editor: EditorInstance) => {
    // Skip the first update after initialization (like Novel does)
    if (!hasInitialized.current) {
      hasInitialized.current = true;
      console.log('EditItemContentEditor: Skipping initial update after editor initialization');
      return;
    }

    const json = editor.getJSON();
    const jsonString = JSON.stringify(json);
    
    console.log('EditItemContentEditor: Editor content updated:', {
      itemId,
      contentLength: jsonString.length,
      hasImages: jsonString.includes('"type":"image"'),
      timestamp: new Date().toISOString()
    });
    
    // Trigger debounced save
    debouncedSave(jsonString);
  }, [itemId, debouncedSave]);

  // Reset initialization flag when editor key changes (new item)
  useEffect(() => {
    hasInitialized.current = false;
    console.log('EditItemContentEditor: Reset initialization flag for new item:', { itemId });
  }, [stableEditorKey]);

  // Enhanced onContentChange - NOT used for regular updates, only for explicit saves
  const handleExplicitContentChange = useMemo(() => {
    return (newContent: string) => {
      console.log('EditItemContentEditor: Explicit content change (not from typing):', {
        itemId,
        newContentLength: newContent?.length || 0,
        reason: 'External update'
      });
      
      // This is for external updates, not typing
      onContentChange(newContent);
    };
  }, [onContentChange, itemId]);

  // Post-upload callback for image uploads
  const handleUploadComplete = useCallback(() => {
    console.log('EditItemContentEditor: Image upload completed, forcing save');
    
    setTimeout(() => {
      if (editorRef.current) {
        const json = editorRef.current.getJSON();
        const jsonString = JSON.stringify(json);
        
        console.log('EditItemContentEditor: Forcing save after image upload:', {
          itemId,
          contentLength: jsonString.length,
          hasImages: jsonString.includes('"type":"image"')
        });
        
        // Cancel pending debounced save and do immediate save
        debouncedSave.cancel();
        onContentChange(jsonString);
      }
    }, 750);
  }, [itemId, onContentChange, debouncedSave]);

  // Image upload functionality
  const { handleImageUpload } = useEditorImageUpload({ 
    user, 
    session, 
    itemId,
    onUploadComplete: handleUploadComplete
  });

  console.log('EditItemContentEditor: Rendering with uncontrolled pattern:', {
    itemId,
    initialContentLength: initialContent?.length || 0,
    stableEditorKey,
    isMaximized,
    hasUploadFn: !!handleImageUpload
  });

  return (
    <EditorContainer
      content={initialContent}
      onContentChange={handleExplicitContentChange}
      onUpdate={handleEditorUpdate}
      handleImageUpload={handleImageUpload}
      editorKey={stableEditorKey}
      isMaximized={isMaximized}
      onEditorReady={(editor) => {
        editorRef.current = editor;
        console.log('EditItemContentEditor: Editor instance ready');
      }}
    />
  );
};

export default EditItemContentEditor;
