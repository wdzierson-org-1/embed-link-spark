
import React from 'react';
import type { EditorInstance } from 'novel';
import { useEditorContentManager } from './EditorContentManager';
import { useEditorUploadHandler } from './EditorUploadHandler';
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

  const uploadFn = useEditorUploadHandler({ handleImageUpload, editorKey });

  const handleEditorUpdate = (editor: EditorInstance) => {
    // Skip the first update during initialization to prevent immediate overwrite
    if (initializationRef.current) {
      console.log('EditorContainer: Skipping initialization update to prevent overwrite');
      initializationRef.current = false;
      return;
    }

    console.log('EditorContainer: onUpdate triggered', {
      editorKey,
      timestamp: new Date().toISOString()
    });
    
    // Get JSON content like TextNoteTab
    const json = editor.getJSON();
    const jsonString = JSON.stringify(json);
    
    console.log('EditorContainer: Content comparison:', {
      editorKey,
      currentLength: jsonString.length,
      lastLength: lastContentRef.current.length,
      hasChanged: jsonString !== lastContentRef.current,
      newContentPreview: jsonString.slice(0, 100) + '...',
      lastContentPreview: lastContentRef.current.slice(0, 100) + '...'
    });
    
    // ALWAYS call onContentChange when content changes
    if (jsonString !== lastContentRef.current) {
      console.log('EditorContainer: Content changed, calling onContentChange', {
        editorKey,
        newContentLength: jsonString.length,
        willTriggerSave: true
      });
      
      // Update ref IMMEDIATELY before calling onContentChange
      lastContentRef.current = jsonString;
      
      // Call onContentChange - this should trigger the save
      onContentChange(jsonString);
      
      console.log('EditorContainer: onContentChange called successfully', {
        editorKey,
        contentSent: jsonString.length > 0
      });
    } else {
      console.log('EditorContainer: No content change detected', {
        editorKey,
        reason: 'jsonString === lastContentRef.current'
      });
    }
  };

  const initialJsonContent = getInitialContent();

  console.log('EditorContainer: Rendering editor:', { 
    editorKey,
    hasInitialContent: !!initialJsonContent,
    contentLength: content?.length || 0,
    hasUploadHandler: !!handleImageUpload
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
      uploadFn={handleImageUpload ? uploadFn : undefined}
      onUpdate={handleEditorUpdate}
    />
  );
};

export default EditorContainer;
