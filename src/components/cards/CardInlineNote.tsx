import React, { useEffect, useMemo, useRef, useState } from 'react';
import { EditorRoot, EditorContent, type EditorInstance } from 'novel';
import { Check } from 'lucide-react';
import { createEditorExtensions } from '@/components/editor/EditorExtensions';
import { convertToJsonContent } from '@/components/editor/EditorUtils';
import { extractPlainTextFromNovelContent } from '@/utils/contentExtractor';
import { supabase } from '@/integrations/supabase/client';
import { scheduleEmbeddingRefresh } from '@/utils/itemOperations';

interface Props {
  item: { id: string; content?: string };
  readOnly?: boolean;
  onSaved?: () => void;
}

/** Edits the same rich document as the detail panel, without flattening marks. */
export default function CardInlineNote({ item, readOnly, onSaved }: Props) {
  const [content, setContent] = useState(item.content ?? '');
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [justSaved, setJustSaved] = useState(false);
  const previewRef = useRef<HTMLButtonElement>(null);
  const restoreFocusRef = useRef(false);
  const cancelledRef = useRef(false);
  const initialDocumentRef = useRef('');
  const editorRef = useRef<EditorInstance | null>(null);
  const savingRef = useRef(false);
  const extensions = useMemo(() => createEditorExtensions(undefined, { inline: true, placeholder: 'Add a note…' }), []);
  useEffect(() => { setContent(item.content ?? ''); }, [item.id, item.content]);
  const preview = extractPlainTextFromNovelContent(content).trim();
  useEffect(() => {
    if (!justSaved) return;
    const timer = setTimeout(() => setJustSaved(false), 1400);
    return () => clearTimeout(timer);
  }, [justSaved]);
  useEffect(() => {
    if (!editing && restoreFocusRef.current) {
      restoreFocusRef.current = false;
      previewRef.current?.focus({ preventScroll: true });
    }
  }, [editing]);

  const cancel = () => {
    cancelledRef.current = true;
    restoreFocusRef.current = true;
    setEditing(false);
  };

  const save = async (nextContent: string, restoreFocus = true) => {
    if (savingRef.current) return;
    savingRef.current = true;
    setSaving(true);
    setError('');
    try {
      const { data, error: saveError } = await supabase.from('items')
        .update({ content: nextContent }).eq('id', item.id).select().single();
      if (saveError) throw saveError;
      setContent(nextContent);
      restoreFocusRef.current = restoreFocus;
      setEditing(false);
      setJustSaved(true);
      if (data) scheduleEmbeddingRefresh(data);
      onSaved?.();
    } catch {
      setError('Couldn’t save your note. Your changes are still here. Try again.');
    } finally {
      savingRef.current = false;
      setSaving(false);
    }
  };

  if (readOnly) return preview ? <p className="line-clamp-5 whitespace-pre-wrap text-sm text-foreground/75">{preview}</p> : null;

  if (!editing) return (
    <div className="relative">
      <button
        ref={previewRef}
        type="button"
        aria-label={preview ? 'Edit note' : 'Add a note'}
        onClick={(event) => {
          event.stopPropagation();
          cancelledRef.current = false;
          setError('');
          setJustSaved(false);
          setEditing(true);
        }}
        className={`${preview
          ? 'relative block w-full rounded-r-md border-l-2 border-violet-300 py-1 pl-3 pr-2 text-left text-sm leading-snug text-foreground/75 transition-colors hover:bg-black/[0.04] focus-visible:bg-[rgba(109,91,208,0.06)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#b6a8ef]'
          : 'card-hover-control rounded-md px-2 py-1 text-xs text-muted-foreground hover:bg-black/[0.04] hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#b6a8ef]'} ${justSaved ? 'card-note-saved' : ''}`}
      >
        {preview ? <span className="line-clamp-5 whitespace-pre-wrap">{preview}</span> : 'Add a note'}
      </button>
      {justSaved && (
        <span role="status" className="card-note-saved-indicator pointer-events-none absolute -top-3 right-0 inline-flex items-center gap-1 rounded-full bg-card px-1.5 py-0.5 text-[11px] font-medium text-[#6d5bd0]">
          <Check aria-hidden="true" className="card-note-saved-check h-3 w-3" />
          Saved
        </span>
      )}
    </div>
  );

  return (
    <div className="space-y-2" onClick={(event) => event.stopPropagation()} onKeyDown={(event) => event.stopPropagation()}
      onBlur={(event) => {
        // Moving to Save/Cancel is still inside the editor. Leaving the whole
        // region commits like the detail fields, without stealing focus back.
        if (event.relatedTarget instanceof Node && event.currentTarget.contains(event.relatedTarget)) return;
        if (cancelledRef.current || savingRef.current || !editorRef.current) return;
        const nextContent = JSON.stringify(editorRef.current.getJSON());
        if (nextContent === initialDocumentRef.current) setEditing(false);
        else void save(nextContent, false);
      }}
    >
      <EditorRoot>
        <EditorContent
          initialContent={convertToJsonContent(content)}
          extensions={extensions}
          autofocus="end"
          editable={!saving}
          onCreate={({ editor }) => { editorRef.current = editor; initialDocumentRef.current = JSON.stringify(editor.getJSON()); }}
          editorProps={{
            attributes: {
              role: 'textbox', 'aria-label': 'Card note', 'aria-multiline': 'true',
              class: 'prose prose-sm max-w-none min-h-16 max-h-80 overflow-y-auto rounded-lg border-0 bg-[rgba(109,91,208,0.06)] px-3 py-2 text-sm text-foreground/75 shadow-none outline-none focus:outline-none focus:ring-2 focus:ring-[#b6a8ef] prose-p:my-1',
            },
            handleKeyDown: (view, event) => {
              if (event.isComposing || view.composing) return false;
              if (event.key === 'Escape' && !savingRef.current) {
                event.preventDefault(); cancel(); return true;
              }
              if (event.key !== 'Enter') return false;
              event.preventDefault();
              if (savingRef.current) return true;
              if (event.ctrlKey || event.metaKey || event.shiftKey) {
                const transaction = view.state.selection.$from.parent.type.spec.code
                  ? view.state.tr.insertText('\n')
                  : view.state.tr.replaceSelectionWith(view.state.schema.nodes.hardBreak.create());
                view.dispatch(transaction.scrollIntoView());
              } else {
                void save(JSON.stringify(view.state.doc.toJSON()));
              }
              return true;
            },
          }}
        />
      </EditorRoot>
      <div className="flex items-center justify-end gap-1 text-xs text-muted-foreground">
        <button type="button" disabled={saving} onClick={cancel} className="rounded px-2 py-1 hover:bg-black/[0.04]">Cancel</button>
        <button type="button" disabled={saving} onClick={() => editorRef.current && void save(JSON.stringify(editorRef.current.getJSON()))} className="rounded px-2 py-1 font-medium text-primary hover:bg-black/[0.04]">{saving ? 'Saving…' : 'Save'}</button>
      </div>
      {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
    </div>
  );
}
