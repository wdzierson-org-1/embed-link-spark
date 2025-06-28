
import React, { useMemo } from 'react';
import { EditorRoot, EditorContent, EditorCommandEmpty, EditorCommandList, EditorCommand, EditorCommandItem, ImageResizer, type EditorInstance } from 'novel';
import { handleCommandNavigation, handleImageDrop, handleImagePaste } from 'novel';
import { useEditorContentManager } from './EditorContentManager';
import EditorBubbleMenu from './EditorBubbleMenu';
import EditorCommandMenu from './EditorCommandMenu';
import { createEditorExtensions } from './EditorExtensions';
import type { EditorContainerProps } from './EditorContainerProps';

const EditorContainer = ({
  content,
  onContentChange,
  onUpdate,
  handleImageUpload,
  editorKey,
  isMaximized = false,
  onEditorReady
}: EditorContainerProps) => {
  const { getInitialContent } = useEditorContentManager({ content, editorKey });
  
  const extensions = useMemo(() => createEditorExtensions(handleImageUpload), [handleImageUpload]);
  const initialContent = useMemo(() => getInitialContent(), [getInitialContent]);

  console.log('EditorContainer: Rendering with key:', { 
    editorKey, 
    hasInitialContent: !!initialContent,
    isMaximized,
    hasOnUpdate: !!onUpdate
  });

  return (
    <EditorRoot>
      <EditorContent
        key={editorKey}
        initialContent={initialContent}
        extensions={extensions}
        className={`relative w-full border-muted bg-background ${
          isMaximized 
            ? 'min-h-[calc(100vh-200px)] border-0' 
            : 'min-h-[300px] sm:rounded-lg sm:border sm:shadow-sm'
        }`}
        editorProps={{
          handleDOMEvents: {
            keydown: (_view, event) => handleCommandNavigation(event),
          },
          handlePaste: (view, event) => handleImagePaste(view, event, handleImageUpload),
          handleDrop: (view, event, _slice, moved) => handleImageDrop(view, event, moved, handleImageUpload),
          attributes: {
            class: "prose prose-sm dark:prose-invert prose-headings:font-title font-default focus:outline-none max-w-full px-4 py-3",
          },
        }}
        onCreate={({ editor }) => {
          console.log('EditorContainer: Editor created');
          if (onEditorReady) {
            onEditorReady(editor);
          }
        }}
        onUpdate={({ editor }) => {
          console.log('EditorContainer: Editor updated');
          if (onUpdate) {
            onUpdate(editor);
          }
          // Don't call onContentChange here - let the parent handle it via onUpdate
        }}
        slotAfter={<ImageResizer />}
      >
        <EditorCommandMenu />
        <EditorBubbleMenu />
      </EditorContent>
    </EditorRoot>
  );
};

export default EditorContainer;
