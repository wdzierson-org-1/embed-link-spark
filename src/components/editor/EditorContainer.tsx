
import React, { useMemo, useRef, useEffect } from 'react';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
} from 'novel';
import { createEditorExtensions } from './EditorExtensions';
import { convertToJsonContent } from './EditorUtils';
import EditorCommandMenu from './EditorCommandMenu';
import EditorBubbleMenu from './EditorBubbleMenu';

interface EditorContainerProps {
  content: string;
  onContentChange: (content: string) => void;
  handleImageUpload?: (file: File) => Promise<string>;
  editorKey: string;
  isMaximized?: boolean;
}

const EditorContainer = ({ 
  content, 
  onContentChange, 
  handleImageUpload, 
  editorKey, 
  isMaximized = false 
}: EditorContainerProps) => {
  const lastContentRef = useRef<string>('');
  const initializationRef = useRef<boolean>(false);

  const extensions = createEditorExtensions(handleImageUpload);

  // ENHANCED: Track content prop changes
  useEffect(() => {
    console.log('EditorContainer: Content prop changed:', {
      editorKey,
      newContentLength: content?.length || 0,
      lastContentLength: lastContentRef.current?.length || 0,
      contentChanged: content !== lastContentRef.current,
      contentPreview: content ? content.slice(0, 100) + '...' : 'No content'
    });
    
    // Update the ref when content prop changes (from database load)
    if (content !== lastContentRef.current) {
      console.log('EditorContainer: Updating lastContentRef due to prop change');
      lastContentRef.current = content || '';
    }
  }, [content, editorKey]);

  const getInitialContent = () => {
    const contentToUse = content || '';
    console.log('EditorContainer: Converting initial content:', { 
      contentLength: contentToUse.length,
      editorKey,
      contentPreview: contentToUse.slice(0, 100) + '...'
    });
    
    const jsonContent = convertToJsonContent(contentToUse);
    
    // CRITICAL: Ensure lastContentRef matches the initial content
    lastContentRef.current = contentToUse;
    initializationRef.current = true;
    
    console.log('EditorContainer: Initial content conversion complete:', {
      editorKey,
      hasJsonContent: !!jsonContent,
      lastContentRefLength: lastContentRef.current.length
    });
    
    return jsonContent;
  };

  const initialJsonContent = getInitialContent();

  console.log('EditorContainer: Rendering editor:', { 
    editorKey,
    hasInitialContent: !!initialJsonContent,
    contentLength: content?.length || 0
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
    <div className={isMaximized ? "h-full flex flex-col" : "border rounded-md"}>
      <EditorRoot key={editorKey}>
        <EditorContent
          initialContent={initialJsonContent}
          extensions={extensions}
          className={isMaximized ? "flex-1 w-full max-w-none overflow-y-auto" : "min-h-[300px] w-full max-w-none"}
          editorProps={{
            handleDOMEvents: {
              keydown: (_view, event) => handleCommandNavigation(event),
            },
            attributes: {
              class: 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-4 prose-h1:text-4xl prose-h1:font-bold prose-h2:text-3xl prose-h2:font-bold prose-h3:text-2xl prose-h3:font-bold prose-h4:text-xl prose-h4:font-bold prose-h5:text-lg prose-h5:font-bold prose-h6:text-base prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 prose-ul:leading-normal prose-ol:leading-normal prose-li:leading-normal prose-li:mb-1 prose-p:leading-normal prose-p:mb-2'
            }
          }}
          onUpdate={({ editor }: { editor: EditorInstance }) => {
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
          }}
        >
          <EditorCommandMenu />
          <EditorBubbleMenu />
        </EditorContent>
      </EditorRoot>
    </div>
  );
};

export default EditorContainer;
