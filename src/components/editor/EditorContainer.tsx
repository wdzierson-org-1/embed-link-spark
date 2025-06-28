
import React from 'react';
import type { EditorInstance } from 'novel';
import { useEditorContentManager } from './EditorContentManager';
import EditorContentRenderer from './EditorContentRenderer';
import type { EditorContainerProps } from './EditorContainerProps';

const EditorContainer = ({ 
  content, 
  onContentChange, 
  handleImageUpload, 
  editorKey, 
  isMaximized = false 
}: EditorContainerProps) => {
  const { lastContentRef, initializationRef, getInitialContent } = useEditorContentManager({
    content,
    editorKey
  });

  const handleEditorUpdate = (editor: EditorInstance) => {
    // Skip the first update during initialization to prevent immediate overwrite
    if (initializationRef.current) {
      console.log('EditorContainer: Skipping initialization update to prevent overwrite', {
        editorKey,
        reason: 'initializationRef.current === true'
      });
      initializationRef.current = false;
      return;
    }

    console.log('EditorContainer: onUpdate triggered by Novel editor', {
      editorKey,
      timestamp: new Date().toISOString()
    });
    
    // Get JSON content from editor
    const json = editor.getJSON();
    const jsonString = JSON.stringify(json);
    
    // Enhanced content comparison with detailed logging
    const hasImageInContent = jsonString.includes('"type":"image"');
    const contentChanged = jsonString !== lastContentRef.current;
    
    console.log('EditorContainer: Content analysis from Novel onUpdate:', {
      editorKey,
      currentLength: jsonString.length,
      lastLength: lastContentRef.current.length,
      hasChanged: contentChanged,
      hasImageInContent,
      contentChangeReason: contentChanged ? 'Content differs from last saved' : 'Content identical to last saved',
      imageCount: (jsonString.match(/"type":"image"/g) || []).length,
      newContentPreview: jsonString.slice(0, 150) + '...',
      lastContentPreview: lastContentRef.current.slice(0, 150) + '...'
    });
    
    // Save when content changes - Novel's onUpdate handles all changes including images
    if (contentChanged) {
      console.log('EditorContainer: Content changed detected by Novel onUpdate, triggering save', {
        editorKey,
        newContentLength: jsonString.length,
        hasImageInContent,
        imageCount: (jsonString.match(/"type":"image"/g) || []).length,
        changeType: hasImageInContent ? 'Content with images' : 'Text content',
        willTriggerSave: true
      });
      
      // Update ref IMMEDIATELY before calling onContentChange to prevent double saves
      lastContentRef.current = jsonString;
      
      // This is triggered by Novel's onUpdate system which handles all content changes
      onContentChange(jsonString);
      
      console.log('EditorContainer: Save triggered via Novel onUpdate system', {
        editorKey,
        savedContentLength: jsonString.length,
        hasImages: hasImageInContent,
        imageCount: (jsonString.match(/"type":"image"/g) || []).length
      });
    } else {
      console.log('EditorContainer: No content change detected by Novel onUpdate - skipping save', {
        editorKey,
        reason: 'jsonString === lastContentRef.current'
      });
    }
  };

  // Enhanced focus/blur handlers for additional save safety
  const handleEditorFocus = (editor: EditorInstance) => {
    console.log('EditorContainer: Editor focused', { editorKey });
  };

  const handleEditorBlur = (editor: EditorInstance) => {
    console.log('EditorContainer: Editor blurred - performing safety save check', { editorKey });
    
    // Safety check on blur to catch any missed saves
    const json = editor.getJSON();
    const jsonString = JSON.stringify(json);
    
    if (jsonString !== lastContentRef.current) {
      console.log('EditorContainer: Unsaved changes detected on blur - triggering save', {
        editorKey,
        contentLength: jsonString.length,
        hasImages: jsonString.includes('"type":"image"'),
        imageCount: (jsonString.match(/"type":"image"/g) || []).length
      });
      
      lastContentRef.current = jsonString;
      onContentChange(jsonString);
    }
  };

  const initialJsonContent = getInitialContent();

  console.log('EditorContainer: Rendering editor with Novel system:', { 
    editorKey,
    hasInitialContent: !!initialJsonContent,
    contentLength: content?.length || 0,
    hasUploadHandler: !!handleImageUpload,
    usingNovelImageSystem: true
  });

  if (!initialJsonContent) {
    return (
      <div>
        <div className={`flex items-center justify-center text-muted-foreground ${isMaximized ? 'h-96' : 'border rounded-md p-4 min-h-[300px]'}`}>
          Loading editor...
        </div>
      </div>
    );
  }

  return (
    <EditorContentRenderer
      initialContent={initialJsonContent}
      editorKey={editorKey}
      isMaximized={isMaximized}
      handleImageUpload={handleImageUpload}
      uploadFn={undefined} // Not used with Novel's system
      onUpdate={handleEditorUpdate}
      onFocus={handleEditorFocus}
      onBlur={handleEditorBlur}
    />
  );
};

export default EditorContainer;
