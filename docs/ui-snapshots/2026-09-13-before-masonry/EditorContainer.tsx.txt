
import React from 'react';
import type { EditorInstance } from 'novel';
import { useEditorContentManager } from './EditorContentManager';
import EditorContentRenderer from './EditorContentRenderer';
import type { EditorContainerProps } from './EditorContainerProps';

interface EnhancedEditorContainerProps extends EditorContainerProps {
  onEditorReady?: (editor: EditorInstance) => void;
}

const EditorContainer = ({ 
  content, 
  onContentChange, 
  handleImageUpload, 
  editorKey, 
  isMaximized = false,
  onEditorReady
}: EnhancedEditorContainerProps) => {
  const { lastContentRef, initializationRef, getInitialContent } = useEditorContentManager({
    content,
    editorKey
  });

  const handleEditorUpdate = (editor: EditorInstance) => {
    // Call onEditorReady when we first get the editor instance
    if (onEditorReady && editor) {
      onEditorReady(editor);
    }

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
    const hasPlaceholderImages = jsonString.includes('"src":"data:image/');
    const hasFinalUrlImages = jsonString.includes('"src":"http');
    
    console.log('EditorContainer: Enhanced content analysis from Novel onUpdate:', {
      editorKey,
      currentLength: jsonString.length,
      lastLength: lastContentRef.current.length,
      hasChanged: contentChanged,
      hasImageInContent,
      hasPlaceholderImages,
      hasFinalUrlImages,
      contentChangeReason: contentChanged ? 'Content differs from last saved' : 'Content identical to last saved',
      imageCount: (jsonString.match(/"type":"image"/g) || []).length,
      placeholderCount: (jsonString.match(/"src":"data:image/g) || []).length,
      finalUrlCount: (jsonString.match(/"src":"http/g) || []).length,
      updatePhase: hasPlaceholderImages ? 'Placeholder phase' : hasFinalUrlImages ? 'Final URL phase' : 'Text content',
      newContentPreview: jsonString.slice(0, 150) + '...',
      lastContentPreview: lastContentRef.current.slice(0, 150) + '...'
    });
    
    // ENHANCED: Save when content changes - including both placeholder and final URL phases
    if (contentChanged) {
      console.log('EditorContainer: Content changed detected - triggering save', {
        editorKey,
        newContentLength: jsonString.length,
        hasImageInContent,
        imageCount: (jsonString.match(/"type":"image"/g) || []).length,
        changeType: hasImageInContent ? 'Content with images' : 'Text content',
        willTriggerSave: true,
        updateType: hasPlaceholderImages ? 'Placeholder phase' : hasFinalUrlImages ? 'Final URL phase' : 'Text update',
        imageUploadComplete: hasFinalUrlImages && !hasPlaceholderImages
      });
      
      // Update ref IMMEDIATELY before calling onContentChange to prevent double saves
      lastContentRef.current = jsonString;
      
      // This is triggered by Novel's onUpdate system which handles all content changes
      onContentChange(jsonString);
      
      console.log('EditorContainer: Save triggered via Novel onUpdate system', {
        editorKey,
        savedContentLength: jsonString.length,
        hasImages: hasImageInContent,
        imageCount: (jsonString.match(/"type":"image"/g) || []).length,
        savePhase: hasPlaceholderImages ? 'Placeholder saved' : hasFinalUrlImages ? 'Final URLs saved' : 'Text saved'
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
    console.log('EditorContainer: Editor blurred - performing enhanced safety save check', { editorKey });
    
    // Enhanced safety check on blur to catch any missed saves, especially for images
    const json = editor.getJSON();
    const jsonString = JSON.stringify(json);
    const hasImages = jsonString.includes('"type":"image"');
    const hasFinalUrls = jsonString.includes('"src":"http');
    
    if (jsonString !== lastContentRef.current) {
      console.log('EditorContainer: Unsaved changes detected on blur - triggering enhanced save', {
        editorKey,
        contentLength: jsonString.length,
        hasImages,
        hasFinalUrls,
        imageCount: (jsonString.match(/"type":"image"/g) || []).length,
        saveReason: 'Blur safety check'
      });
      
      lastContentRef.current = jsonString;
      onContentChange(jsonString);
    }
  };

  const initialJsonContent = getInitialContent();

  console.log('EditorContainer: Rendering editor with enhanced save system:', { 
    editorKey,
    hasInitialContent: !!initialJsonContent,
    contentLength: content?.length || 0,
    hasUploadHandler: !!handleImageUpload,
    hasEditorReadyCallback: !!onEditorReady,
    usingExplicitSaveSystem: true
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
      uploadFn={handleImageUpload}
      onUpdate={handleEditorUpdate}
      onFocus={handleEditorFocus}
      onBlur={handleEditorBlur}
    />
  );
};

export default EditorContainer;
