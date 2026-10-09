import React, { useCallback, useEffect, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import TranscriptContent from '@/components/TranscriptContent';
import { Maximize, Sparkles } from 'lucide-react';
import { StatusLine } from '@/components/machine/Machine';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import MaximizedSource from '@/components/edit/MaximizedSource';
import { SectionHead } from '@/components/edit/EditPanelSection';
import { canSummarizeSource, useItemSourceContent } from '@/hooks/useItemSourceContent';
import { getContentTabsConfig, needsSourceContent, type ContentTabKey } from '@/utils/editPanelTabs';
import { enrichmentState } from '@/utils/itemAssembly';
import { noteIsEmpty } from '@/utils/noteContent';
import {
  isTranscribing,
  transcribingLabel,
  transcriptFailureCopy,
  transcriptRefreshKey,
} from '@/utils/transcriptStatus';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type?: string;
  title?: string;
  file_path?: string;
  attributes?: ItemAttributes;
}

interface EditItemContentSectionProps {
  item: ContentItem | null;
  content: string;
  isContentLoading: boolean;
  editorKey: string;
  onContentChange: (content: string) => void;
  onMaximize: () => void;
  isMobile: boolean;
  mobileEditorReady: boolean;
  /** Saves the summary the person edited in place */
  onSummarySave?: (summary: string) => Promise<void>;
}

const looksLikeMarkdown = (text: string): boolean =>
  /(^|\n)#{1,6}\s|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|(^|\n)\s*[-*]\s/.test(text);

// The field treatment the title and description use: plain at rest, fill on hover, white with the
// ink edge and spot ring while editing (no hover fill then — the pointer is usually still over it)
const FIELD_BOX = '-mx-2 w-[calc(100%+16px)] px-2 py-1 transition-colors';
const FIELD_AT_REST = `${FIELD_BOX} hover:bg-fill`;
const FIELD_EDITING = `${FIELD_BOX} bg-white shadow-[inset_0_0_0_1px_var(--ink),0_0_0_3px_rgb(var(--spot-rgb))]`;

// Source material sits directly on the panel surface — no nested box (the shared page reads it too)
export const ReadOnlyText = ({ text, capped = true }: { text: string; capped?: boolean }) => (
  <div className={capped ? 'max-h-[420px] overflow-y-auto pr-1' : ''}>
    {looksLikeMarkdown(text) ? (
      <div className="prose prose-sm max-w-none text-[15px] leading-[1.6] text-ink prose-headings:font-medium prose-a:text-ink">
        <ReactMarkdown>{text}</ReactMarkdown>
      </div>
    ) : (
      <div className="whitespace-pre-wrap text-[15px] leading-[1.6] text-ink">{text}</div>
    )}
  </div>
);

const TabEmptyState = ({ children }: { children: React.ReactNode }) => (
  // An empty source tab is a small stage: the dot grid, and what's true right now
  <div className="v2-dots flex min-h-[120px] flex-col items-center justify-center gap-3 px-6 py-8 text-center text-[14px] text-muted-foreground">
    {children}
  </div>
);

const LoadingState = () => (
  <div className="flex min-h-[120px] items-center justify-center">
    <StatusLine tone="busy">loading…</StatusLine>
  </div>
);

/**
 * The summary, editable in place (DESIGN-v2 §12.8): rendered as text at rest, a field on click.
 * The original content never is: it's what Stash captured.
 */
const EditableSummary = ({
  summary,
  onSave,
  capped = true,
}: {
  summary: string;
  onSave?: (summary: string) => Promise<void>;
  capped?: boolean;
}) => {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(summary);
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!editing) setDraft(summary);
  }, [summary, editing]);

  const resize = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = '0px';
    el.style.height = `${el.scrollHeight}px`;
  }, []);

  useEffect(() => {
    if (editing) {
      resize();
      textareaRef.current?.focus();
    }
  }, [editing, resize]);

  // Esc abandons the edit. The sheet hears Esc on the document's capture phase, so the field
  // listens earlier, on the window, and stops it there: an abandoned edit must not close the panel.
  useEffect(() => {
    if (!editing) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.stopPropagation();
      event.preventDefault();
      setDraft(summary);
      setEditing(false);
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [editing, summary]);

  const finish = async () => {
    setEditing(false);
    if (!onSave || draft === summary) return;
    setSaving(true);
    setFailed(false);
    try {
      await onSave(draft);
    } catch {
      setFailed(true);
    } finally {
      setSaving(false);
    }
  };

  if (!onSave) return <ReadOnlyText text={summary} capped={capped} />;

  if (editing) {
    return (
      <textarea
        ref={textareaRef}
        value={draft}
        aria-label="Summary"
        onChange={(event) => {
          setDraft(event.target.value);
          resize();
        }}
        onBlur={() => void finish()}
        className={`${FIELD_EDITING} block min-h-[3lh] resize-none overflow-hidden text-[15px] leading-[1.6] text-ink outline-none`}
      />
    );
  }

  return (
    <div>
      <div
        role="button"
        tabIndex={0}
        aria-label="Edit summary"
        onClick={() => setEditing(true)}
        onKeyDown={(event) => {
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            setEditing(true);
          }
        }}
        className={`${FIELD_AT_REST} cursor-text focus-visible:outline-none focus-visible:bg-fill`}
      >
        <ReadOnlyText text={summary} capped={capped} />
      </div>
      {saving && (
        <div className="mt-1.5">
          <StatusLine tone="busy">saving the summary…</StatusLine>
        </div>
      )}
      {failed && (
        <div className="mt-1.5">
          <StatusLine tone="error" live={false}>couldn't save the summary. try again</StatusLine>
        </div>
      )}
    </div>
  );
};

const EditItemContentSection = ({
  item,
  content,
  isContentLoading,
  editorKey,
  onContentChange,
  onMaximize,
  isMobile,
  mobileEditorReady,
  onSummarySave,
}: EditItemContentSectionProps) => {
  const config = getContentTabsConfig(item?.type);
  const [activeTab, setActiveTab] = useState<ContentTabKey>(config.defaultTab);
  const [sourceMaximized, setSourceMaximized] = useState(false);

  // Reset to the type's default tab when switching items
  useEffect(() => {
    setActiveTab(getContentTabsConfig(item?.type).defaultTab);
    setSourceMaximized(false);
  }, [item?.id, item?.type]);

  // Audio/video: the transcript job reports progress in attributes; each
  // landed chunk changes the key and re-pulls page_body so the tab fills in
  const transcript = item?.attributes?.media?.transcript;
  const {
    summary,
    pageBody,
    isLoading: isSourceLoading,
    isGenerating,
    generateError,
    generateSummary,
    setSummary,
  } = useItemSourceContent(item?.id, needsSourceContent(item?.type), transcriptRefreshKey(transcript));

  const isDocument = item?.type === 'document' || item?.type === 'pdf';
  // Only pending enrichment is still extracting. Once it settles with no text (the extraction
  // failed, e.g. a PDF over OpenAI's 50 MB limit), "still being extracted" would be false.
  const noDocumentText = item && enrichmentState(item, Date.now()) === 'pending'
    ? 'Content is still being extracted from this document.'
    : "We couldn't read the text in this document.";

  const saveSummary = onSummarySave
    ? async (next: string) => {
        await onSummarySave(next);
        setSummary(next.trim() ? next : null);
      }
    : undefined;

  // ── Notes: one line of body text until it's needed (DESIGN-v2 §12.8) ──────────────────────
  // Empty notes don't mount the editor: a click does, focused. Once the person is in it, the
  // field takes the title's treatment (fill on hover, white with the ink edge and spot ring).
  const hasNote = !noteIsEmpty(content);
  const [notesOpen, setNotesOpen] = useState(false);
  const [notesFocused, setNotesFocused] = useState(false);
  const notesRef = useRef<HTMLDivElement>(null);
  const wantsFocus = useRef(false);

  useEffect(() => {
    setNotesOpen(false);
    setNotesFocused(false);
  }, [item?.id]);

  // Focus the editor once it exists, after a click on the empty line
  useEffect(() => {
    if (!notesOpen || !wantsFocus.current) return;
    let tries = 0;
    let frame = 0;
    const tryFocus = () => {
      const editable = notesRef.current?.querySelector<HTMLElement>('.ProseMirror');
      if (editable) {
        wantsFocus.current = false;
        editable.focus();
        const selection = window.getSelection();
        if (selection) {
          const range = document.createRange();
          range.selectNodeContents(editable);
          range.collapse(false);
          selection.removeAllRanges();
          selection.addRange(range);
        }
        return;
      }
      if (tries++ < 60) frame = requestAnimationFrame(tryFocus);
    };
    frame = requestAnimationFrame(tryFocus);
    return () => cancelAnimationFrame(frame);
  }, [notesOpen]);

  const openNotes = () => {
    wantsFocus.current = true;
    setNotesOpen(true);
  };

  const editorMounted = hasNote || notesOpen;
  const notesEditor = (
    <div
      ref={notesRef}
      onFocusCapture={() => setNotesFocused(true)}
      onBlurCapture={(event) => {
        if (!notesRef.current?.contains(event.relatedTarget as Node | null)) {
          setNotesFocused(false);
          if (!hasNote) setNotesOpen(false);
        }
      }}
    >
      {!editorMounted ? (
        <button
          type="button"
          onClick={openNotes}
          className={`${FIELD_AT_REST} block text-left text-[15px] leading-[1.6] text-muted-foreground focus-visible:outline-none focus-visible:bg-fill`}
        >
          Add a note…
        </button>
      ) : isContentLoading ? (
        <div className="flex min-h-[40px] items-center">
          <StatusLine tone="busy">loading the editor…</StatusLine>
        </div>
      ) : !mobileEditorReady && isMobile ? (
        <div className="flex min-h-[40px] items-center">
          <StatusLine tone="busy">starting the editor…</StatusLine>
        </div>
      ) : (
        <div className={`${notesFocused ? FIELD_EDITING : FIELD_AT_REST} min-h-[2lh] text-[15px] leading-[1.6]`}>
          <EditItemContentEditor
            content={content}
            onContentChange={onContentChange}
            itemId={item?.id}
            editorInstanceKey={editorKey}
            isMaximized={false}
            inline
          />
        </div>
      )}
      {notesFocused && (
        <div className="mt-2 text-right font-pixel text-pixel text-muted-foreground">
          type / for formatting
        </div>
      )}
    </div>
  );

  // ── Source tabs ───────────────────────────────────────────────────────────────────────────
  const summaryView = (capped: boolean) =>
    isSourceLoading ? (
      <LoadingState />
    ) : summary ? (
      <EditableSummary summary={summary} onSave={saveSummary} capped={capped} />
    ) : canSummarizeSource(pageBody) ? (
      <TabEmptyState>
        <span>No summary yet for this {isDocument ? 'document' : 'link'}.</span>
        {isGenerating ? (
          <StatusLine tone="busy">summarizing…</StatusLine>
        ) : (
          <button
            type="button"
            onClick={() => void generateSummary()}
            className="inline-flex h-9 items-center gap-1.5 bg-ink px-3.5 text-[14px] font-medium text-white transition-colors hover:bg-ink-soft"
          >
            <Sparkles className="h-3.5 w-3.5" />
            Generate summary
          </button>
        )}
        {generateError && !isGenerating && <StatusLine tone="error">{generateError}</StatusLine>}
      </TabEmptyState>
    ) : pageBody ? (
      <TabEmptyState>Too little text was captured to summarize. It's all under Original Content.</TabEmptyState>
    ) : (
      <TabEmptyState>
        {isDocument ? noDocumentText : "We haven't been able to read this page's content yet."}
      </TabEmptyState>
    );

  const originalView = (capped: boolean) =>
    isSourceLoading ? (
      <LoadingState />
    ) : pageBody ? (
      <ReadOnlyText text={pageBody} capped={capped} />
    ) : (
      <TabEmptyState>
        {isDocument ? noDocumentText : 'No page content captured from this link yet.'}
      </TabEmptyState>
    );

  const transcriptView = isSourceLoading ? (
    <LoadingState />
  ) : pageBody && item ? (
    <>
      {transcript && isTranscribing(transcript) && (
        <div className="mb-3">
          <StatusLine tone="busy">{transcribingLabel(transcript).toLowerCase()}</StatusLine>
        </div>
      )}
      <TranscriptContent key={item.id} itemId={item.id} filePath={item.file_path} transcript={pageBody} />
    </>
  ) : transcript && isTranscribing(transcript) ? (
    <TabEmptyState>
      <StatusLine tone="busy">{transcribingLabel(transcript).toLowerCase()}</StatusLine>
    </TabEmptyState>
  ) : transcript?.status === 'failed' ? (
    <TabEmptyState>{transcriptFailureCopy(transcript)}</TabEmptyState>
  ) : (
    <TabEmptyState>No transcript available for this recording.</TabEmptyState>
  );

  const viewFor = (tab: ContentTabKey, capped: boolean): React.ReactNode =>
    tab === 'summary' ? summaryView(capped) : tab === 'original' ? originalView(capped) : tab === 'transcript' ? transcriptView : null;

  const sourceTabs = config.tabs.filter((tab) => tab.key !== 'notes');
  const shownTab = activeTab === 'notes' ? sourceTabs[0]?.key : activeTab;
  const shownLabel = sourceTabs.find((tab) => tab.key === shownTab)?.label.toLowerCase() ?? config.title.toLowerCase();

  return (
    <>
      {/* The source first (DESIGN-v2 §12.8): the tabs on the rule, no label, full size on the right */}
      {sourceTabs.length > 0 && shownTab && (
        <section className="mt-[30px]" aria-label={config.title}>
          <div className="flex min-h-7 items-end justify-between gap-3 border-b border-ink pb-1.5">
            <div className="-mb-1.5 flex flex-wrap gap-[3px]" role="tablist" aria-label="Source content">
              {sourceTabs.map((tab) => (
                <button
                  key={tab.key}
                  role="tab"
                  aria-selected={shownTab === tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`h-7 px-2 font-pixel text-pixel lowercase leading-none transition-colors ${
                    shownTab === tab.key ? 'bg-ink text-white' : 'text-muted-foreground hover:bg-fill hover:text-ink'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>
            <button
              onClick={() => setSourceMaximized(true)}
              title="View full size"
              aria-label="View full size"
              className="grid h-6 w-6 place-items-center text-muted-foreground hover:bg-ink hover:text-white"
            >
              <Maximize className="h-3.5 w-3.5" />
            </button>
          </div>
          <div className="mt-3.5">{viewFor(shownTab, true)}</div>
        </section>
      )}

      <section className="mt-[30px]" aria-label="Notes">
        <SectionHead label="Notes" aside={
          <button onClick={onMaximize} title="Maximize editor" aria-label="Maximize editor"
            className="grid h-6 w-6 place-items-center text-muted-foreground hover:bg-ink hover:text-white">
            <Maximize className="h-3.5 w-3.5" />
          </button>
        } />
        <div className="mt-3.5">{notesEditor}</div>
      </section>

      {sourceMaximized && shownTab && (
        <MaximizedSource title={shownLabel} onMinimize={() => setSourceMaximized(false)}>
          {viewFor(shownTab, false)}
        </MaximizedSource>
      )}
    </>
  );
};

export default EditItemContentSection;
