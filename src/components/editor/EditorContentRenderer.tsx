
import React from 'react';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
  handleImageDrop,
  handleImagePaste,
} from 'novel';
import { createEditorExtensions } from './EditorExtensions';
import EditorCommandMenu from './EditorCommandMenu';
import EditorBubbleMenu from './EditorBubbleMenu';

interface EditorContentRendererProps {
  initialContent: JSONContent;
  editorKey: string;
  isMaximized: boolean;
  handleImageUpload?: (file: File) => Promise<string>;
  uploadFn?: (file: File, view: any, pos: number) => Promise<void>;
  onUpdate: (editor: EditorInstance) => void;
}

const EditorContentRenderer = ({
  initialContent,
  editorKey,
  isMaximized,
  handleImageUpload,
  uploadFn,
  onUpdate
}: EditorContentRendererProps) => {
  const extensions = createEditorExtensions(handleImageUpload);

  return (
    <div className={isMaximized ? "h-full flex flex-col" : "border rounded-md"}>
      <EditorRoot key={editorKey}>
        <EditorContent
          initialContent={initialContent}
          extensions={extensions}
          className={isMaximized ? "flex-1 w-full max-w-none overflow-y-auto" : "min-h-[300px] w-full max-w-none"}
          editorProps={{
            handleDOMEvents: {
              keydown: (_view, event) => handleCommandNavigation(event),
            },
            handlePaste: uploadFn ? (view, event) => {
              console.log('EditorContainer: Paste event detected');
              return handleImagePaste(view, event, uploadFn);
            } : undefined,
            handleDrop: uploadFn ? (view, event, _slice, moved) => {
              console.log('EditorContainer: Drop event detected');
              return handleImageDrop(view, event, moved, uploadFn);
            } : undefined,
            attributes: {
              class: 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-4 prose-h1:text-4xl prose-h1:font-bold prose-h2:text-3xl prose-h2:font-bold prose-h3:text-2xl prose-h3:font-bold prose-h4:text-xl prose-h4:font-bold prose-h5:text-lg prose-h5:font-bold prose-h6:text-base prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 prose-ul:leading-normal prose-ol:leading-normal prose-li:leading-normal prose-li:mb-1 prose-p:leading-normal prose-p:mb-2'
            }
          }}
          onUpdate={({ editor }: { editor: EditorInstance }) => onUpdate(editor)}
        >
          <EditorCommandMenu />
          <EditorBubbleMenu />
        </EditorContent>
      </EditorRoot>
    </div>
  );
};

export default EditorContentRenderer;
