
import React, { useMemo, useRef } from 'react';
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

  const extensions = createEditorExtensions(handleImageUpload);

  const getInitialContent = () => {
    const contentToUse = content || '';
    console.log('EditorContainer: Converting initial content:', { 
      contentLength: contentToUse.length,
      editorKey
    });
    
    const jsonContent = convertToJsonContent(contentToUse);
    lastContentRef.current = contentToUse;
    return jsonContent;
  };

  const initialJsonContent = getInitialContent();

  console.log('EditorContainer: Rendering editor:', { 
    editorKey,
    hasInitialContent: !!initialJsonContent
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
            // ENHANCED DEBUGGING - trace the complete flow
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
              contentPreview: jsonString.slice(0, 100) + '...'
            });
            
            // ALWAYS call onContentChange when content changes - simplified like TextNoteTab
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
