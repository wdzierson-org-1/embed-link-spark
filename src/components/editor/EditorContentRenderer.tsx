
import React from 'react';
import {
  EditorRoot,
  EditorContent,
  type JSONContent,
  type EditorInstance,
  handleCommandNavigation,
  type UploadFn,
} from 'novel';
import { createEditorExtensions } from './EditorExtensions';
import EditorCommandMenu from './EditorCommandMenu';
import EditorBubbleMenu from './EditorBubbleMenu';

interface EditorContentRendererProps {
  initialContent: JSONContent;
  editorKey: string;
  isMaximized: boolean;
  uploadFn?: UploadFn;
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

  console.log('EditorContentRenderer: Configuring with Novel upload system:', {
    editorKey,
    hasUploadFn: !!uploadFn,
    usingNovelUploadSystem: true,
    extensionsCount: extensions.length
  });

  return (
    <div className={isMaximized ? "h-full flex flex-col" : "border rounded-md h-[300px] flex flex-col"}>
      <EditorRoot key={editorKey}>
        <EditorContent
          initialContent={initialContent}
          extensions={extensions}
          className={isMaximized ? "flex-1 w-full max-w-none overflow-y-auto" : "flex-1 w-full max-w-none overflow-y-auto"}
          editorProps={{
            handleDOMEvents: {
              keydown: (_view, event) => handleCommandNavigation(event),
            },
            attributes: {
              class: isMaximized 
                ? 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-4 prose-h1:text-4xl prose-h1:font-bold prose-h2:text-3xl prose-h2:font-bold prose-h3:text-2xl prose-h3:font-bold prose-h4:text-xl prose-h4:font-bold prose-h5:text-lg prose-h5:font-bold prose-h6:text-base prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 prose-ul:leading-normal prose-ol:leading-normal prose-li:leading-normal prose-li:mb-1 prose-p:leading-normal prose-p:mb-2'
                : 'prose prose-sm dark:prose-invert prose-headings:font-bold font-default focus:outline-none max-w-full p-3 h-full overflow-y-auto prose-h1:text-2xl prose-h1:font-bold prose-h2:text-xl prose-h2:font-bold prose-h3:text-lg prose-h3:font-bold prose-h4:text-base prose-h4:font-bold prose-h5:text-sm prose-h5:font-bold prose-h6:text-sm prose-h6:font-bold prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 prose-ul:leading-snug prose-ol:leading-snug prose-li:leading-snug prose-li:mb-0.5 prose-p:leading-snug prose-p:mb-1'
            }
          }}
          onUpdate={({ editor }: { editor: EditorInstance }) => {
            const json = editor.getJSON();
            const jsonString = JSON.stringify(json);
            
            console.log('EditorContentRenderer: Novel onUpdate fired - analyzing content:', {
              editorKey,
              contentLength: jsonString.length,
              hasImages: jsonString.includes('"type":"image"'),
              imageCount: (jsonString.match(/"type":"image"/g) || []).length,
              placeholderImages: (jsonString.match(/"src":"data:image/g) || []).length,
              finalUrlImages: (jsonString.match(/"src":"http/g) || []).length,
              updateTrigger: 'Novel UploadImagesPlugin system'
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
