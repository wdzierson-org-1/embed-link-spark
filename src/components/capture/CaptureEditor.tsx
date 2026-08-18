import React, { forwardRef, useImperativeHandle, useMemo, useRef } from 'react';
import {
  EditorRoot,
  EditorContent,
  handleCommandNavigation,
  type EditorInstance,
  type JSONContent,
} from 'novel';
import { createEditorExtensions } from '@/components/editor/EditorExtensions';
import EditorCommandMenu from '@/components/editor/EditorCommandMenu';
import EditorBubbleMenu from '@/components/editor/EditorBubbleMenu';
import { docToPlainText } from '@/utils/captureDoc';

export interface CaptureEditorHandle {
  getJSON: () => JSONContent | null;
  /** Reset to an empty doc (emits a change) */
  clear: () => void;
  /** Restore a doc, e.g. when a submit fails (emits a change) */
  setJSON: (doc: JSONContent) => void;
  /** Append text at the end of the doc (used by the paste-anywhere shortcut) */
  insertText: (text: string) => void;
  focus: () => void;
  isEmpty: () => boolean;
}

interface CaptureEditorProps {
  onDocChange: (payload: { plainText: string; isEmpty: boolean }) => void;
  /** Enter on a simple one-line note (or an empty note with chips) submits */
  onSubmit: () => void;
  onFocusChange?: (focused: boolean) => void;
  /** Pasted image files are routed out to the chip pipeline, not inlined */
  onImageFilesPasted?: (files: File[]) => void;
  placeholder?: string;
}

const EMPTY_DOC: JSONContent = {
  type: 'doc',
  content: [{ type: 'paragraph', content: [] }],
};

/**
 * Enter should only submit while the note still looks like the old quick
 * textarea: a single plain paragraph with no explicit line breaks. The moment
 * the doc holds lists, headings, code, or multiple paragraphs, Enter belongs
 * to the editor.
 */
const docAllowsEnterSubmit = (doc: {
  childCount: number;
  firstChild: { type: { name: string }; descendants: (fn: (node: { type: { name: string } }) => boolean | void) => void } | null;
}): boolean => {
  if (doc.childCount === 0) return true;
  if (doc.childCount > 1) return false;
  const first = doc.firstChild;
  if (!first || first.type.name !== 'paragraph') return false;

  let simple = true;
  first.descendants((child) => {
    if (child.type.name === 'hardBreak') simple = false;
    return simple;
  });
  return simple;
};

const slashMenuIsOpen = () => Boolean(document.querySelector('#slash-command'));

/**
 * The main-dashboard capture editor: the same Novel editor (slash commands,
 * bubble menu, task lists, inline image upload) the edit panel's notes tab
 * uses, wrapped with capture-specific behavior — Enter-to-submit for simple
 * notes, Escape-to-clear, and pasted images handed off to the chip pipeline.
 */
const CaptureEditor = forwardRef<CaptureEditorHandle, CaptureEditorProps>(
  ({ onDocChange, onSubmit, onFocusChange, onImageFilesPasted, placeholder }, ref) => {
    const editorRef = useRef<EditorInstance | null>(null);

    // Refs keep the ProseMirror prop callbacks stable while always seeing the
    // latest handlers from the panel
    const onSubmitRef = useRef(onSubmit);
    onSubmitRef.current = onSubmit;
    const onDocChangeRef = useRef(onDocChange);
    onDocChangeRef.current = onDocChange;
    const onImageFilesPastedRef = useRef(onImageFilesPasted);
    onImageFilesPastedRef.current = onImageFilesPasted;

    const extensions = useMemo(
      () =>
        createEditorExtensions(undefined, {
          placeholder:
            placeholder ?? "Paste a link, drop a file, or type a note — press '/' for commands",
        }),
      // The placeholder is baked into the extension set at mount
      // eslint-disable-next-line react-hooks/exhaustive-deps
      []
    );

    const emitDocChange = (editor: EditorInstance) => {
      onDocChangeRef.current({
        plainText: docToPlainText(editor.getJSON()),
        isEmpty: editor.isEmpty,
      });
    };

    useImperativeHandle(ref, () => ({
      getJSON: () => editorRef.current?.getJSON() ?? null,
      clear: () => {
        editorRef.current?.commands.clearContent(true);
      },
      setJSON: (doc: JSONContent) => {
        editorRef.current?.commands.setContent(doc, true);
      },
      insertText: (text: string) => {
        const editor = editorRef.current;
        if (!editor) return;
        const separator = editor.isEmpty ? '' : ' ';
        editor.chain().focus('end').insertContent(`${separator}${text}`).run();
      },
      focus: () => {
        editorRef.current?.commands.focus('end');
      },
      isEmpty: () => editorRef.current?.isEmpty ?? true,
    }));

    return (
      <div
        data-testid="capture-editor"
        className="cursor-text"
        onMouseDown={(e) => {
          // Clicking the empty area below a short note still focuses the editor
          const target = e.target as HTMLElement;
          if (target.closest('.ProseMirror')) return;
          const editable = (e.currentTarget as HTMLElement).querySelector<HTMLElement>('.ProseMirror');
          if (editable) {
            e.preventDefault();
            editorRef.current?.commands.focus('end');
          }
        }}
      >
        <EditorRoot>
          <EditorContent
            initialContent={EMPTY_DOC}
            extensions={extensions}
            className="w-full max-w-none max-h-[45vh] overflow-y-auto"
            onCreate={({ editor }: { editor: EditorInstance }) => {
              editorRef.current = editor;
            }}
            editorProps={{
              handleDOMEvents: {
                keydown: (view, event) => {
                  // Slash-menu navigation wins while the menu is open
                  if (handleCommandNavigation(event)) return true;

                  if (event.key === 'Enter' && !event.shiftKey && docAllowsEnterSubmit(view.state.doc)) {
                    event.preventDefault();
                    onSubmitRef.current();
                    return true;
                  }

                  if (event.key === 'Escape') {
                    if (slashMenuIsOpen()) return false; // the menu closes itself
                    const editor = editorRef.current;
                    if (editor && !editor.isEmpty) {
                      editor.commands.clearContent(true);
                    } else {
                      (view.dom as HTMLElement).blur();
                    }
                    return true;
                  }

                  return false;
                },
              },
              handlePaste: (_view, event) => {
                const items = Array.from(event.clipboardData?.items ?? []);
                const imageFiles = items
                  .filter((item) => item.type.startsWith('image/'))
                  .map((item) => item.getAsFile())
                  .filter((file): file is File => file !== null);

                if (imageFiles.length > 0) {
                  event.preventDefault();
                  onImageFilesPastedRef.current?.(imageFiles);
                  return true;
                }
                return false;
              },
              handleDrop: (_view, event) => {
                // File drops belong to the surrounding dropzone (chips), which
                // receives the same event as it bubbles up
                return Boolean(event.dataTransfer?.files?.length);
              },
              attributes: {
                class:
                  'prose dark:prose-invert font-default focus:outline-none max-w-full min-h-[100px] px-1 py-1 text-base ' +
                  'prose-headings:font-bold prose-h1:text-2xl prose-h2:text-xl prose-h3:text-lg prose-h4:text-base ' +
                  'prose-a:text-blue-600 prose-a:underline prose-a:cursor-pointer hover:prose-a:text-blue-800 ' +
                  'prose-p:leading-snug prose-p:my-1 prose-ul:leading-snug prose-ul:my-1 prose-ol:leading-snug prose-ol:my-1 prose-li:leading-snug prose-li:my-0.5 ' +
                  'prose-blockquote:my-2 prose-pre:my-2',
              },
            }}
            onUpdate={({ editor }: { editor: EditorInstance }) => {
              editorRef.current = editor;
              emitDocChange(editor);
            }}
            onFocus={() => onFocusChange?.(true)}
            onBlur={() => onFocusChange?.(false)}
          >
            <EditorCommandMenu />
            <EditorBubbleMenu />
          </EditorContent>
        </EditorRoot>
      </div>
    );
  }
);

CaptureEditor.displayName = 'CaptureEditor';

export default CaptureEditor;
