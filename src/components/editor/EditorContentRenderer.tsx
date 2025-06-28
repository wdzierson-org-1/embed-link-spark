
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
  uploadFn?: (file: File, view: any, pos: number) => void;
  onUpdate: (editor: EditorInstance) => void;
  onFocus?: (editor: EditorInstance) => void;
  onBlur?: (editor: EditorInstance) => void;
}

const EditorContentRenderer = ({
  initialContent,
  editorKey,
  isMaximized,
  uploadFn,
  onUpdate,
  onFocus,
  onBlur
}: EditorContentRendererProps) => {
  const extensions = createEditorExtensions(uploadFn);

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
            // Use Novel's built-in image handling with our upload function
            handlePaste: uploadFn ? (view, event) => {
              console.log('EditorContentRenderer: Paste event detected, using Novel handler');
              return handleImagePaste(view, event, uploadFn);
            } : undefined,
            handleDrop: uploadFn ? (view, event, _slice, moved) => {
              console.log('EditorContentRenderer: Drop event detected, using Novel handler');
              return handleImageDrop(view, event, moved, uploadFn);
            } : undefined,
            attributes: {
              class: 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-4 prose-h1:text-4xl prose-h1:font-bold prose-h2:text-3xl prose-h2:font-bold prose-h3:text-2xl prose-h3:font-bold prose-h4:text-xl prose-h4:font-bold prose-h5:text-lg prose-h5:font-bold prose-h6:text-base prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 prose-ul:leading-normal prose-ol:leading-normal prose-li:leading-normal prose-li:mb-1 prose-p:leading-normal prose-p:mb-2'
            }
          }}
          onUpdate={({ editor }: { editor: EditorInstance }) => {
            console.log('EditorContentRenderer: onUpdate event fired', {
              editorKey,
              hasContent: !!editor.getJSON(),
              contentLength: JSON.stringify(editor.getJSON()).length,
              hasImages: JSON.stringify(editor.getJSON()).includes('"type":"image"'),
              imageCount: (JSON.stringify(editor.getJSON()).match(/"type":"image"/g) || []).length,
              updateReason: 'Novel editor content changed'
            });
            onUpdate(editor);
          }}
          onFocus={onFocus ? ({ editor }: { editor: EditorInstance }) => {
            console.log('EditorContentRenderer: onFocus event fired', { editorKey });
            onFocus(editor);
          } : undefined}
          onBlur={onBlur ? ({ editor }: { editor: EditorInstance }) => {
            console.log('EditorContentRenderer: onBlur event fired', { editorKey });
            onBlur(editor);
          } : undefined}
        >
          <EditorCommandMenu />
          <EditorBubbleMenu />
        </EditorContent>
      </EditorRoot>
    </div>
  );
};

export default EditorContentRenderer;
