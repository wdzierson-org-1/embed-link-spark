import React, { useEffect, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import TranscriptContent from '@/components/TranscriptContent';
import { Maximize, Sparkles } from 'lucide-react';
import { StatusLine } from '@/components/machine/Machine';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import { SectionHead } from '@/components/edit/EditPanelSection';
import { canSummarizeSource, useItemSourceContent } from '@/hooks/useItemSourceContent';
import { getContentTabsConfig, needsSourceContent, type ContentTabKey } from '@/utils/editPanelTabs';
import {
  isTranscribing,
  transcribingLabel,
  transcriptFailureCopy,
  transcriptRefreshKey,
} from '@/utils/transcriptStatus';
import { enrichmentState } from '@/utils/itemAssembly';
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
}

const looksLikeMarkdown = (text: string): boolean =>
  /(^|\n)#{1,6}\s|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|(^|\n)\s*[-*]\s/.test(text);

// Source material sits directly on the panel surface — no nested box
const ReadOnlyText = ({ text, capped = true }: { text: string; capped?: boolean }) => (
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

const EditItemContentSection = ({
  item,
  content,
  isContentLoading,
  editorKey,
  onContentChange,
  onMaximize,
  isMobile,
  mobileEditorReady,
}: EditItemContentSectionProps) => {
  const config = getContentTabsConfig(item?.type);
  const [activeTab, setActiveTab] = useState<ContentTabKey>(config.defaultTab);

  // Reset to the type's default tab when switching items
  useEffect(() => {
    setActiveTab(getContentTabsConfig(item?.type).defaultTab);
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
  } = useItemSourceContent(item?.id, needsSourceContent(item?.type), transcriptRefreshKey(transcript));

  const isDocument = item?.type === 'document' || item?.type === 'pdf';
  // Only pending enrichment is still extracting. Once it settles with no text (the extraction
  // failed, e.g. a PDF over OpenAI's 50 MB limit), "still being extracted" would be false.
  const noDocumentText = item && enrichmentState(item, Date.now()) === 'pending'
    ? 'Content is still being extracted from this document.'
    : "We couldn't read the text in this document.";

  const notesEditor = (
    <div className="relative">
      {isContentLoading ? (
        <div className="flex min-h-[150px] items-center justify-center">
          <StatusLine tone="busy">loading the editor…</StatusLine>
        </div>
      ) : !mobileEditorReady && isMobile ? (
        <div className="flex min-h-[150px] items-center justify-center">
          <StatusLine tone="busy">starting the editor…</StatusLine>
        </div>
      ) : (
        <div>
          <EditItemContentEditor
            content={content}
            onContentChange={onContentChange}
            itemId={item?.id}
            editorInstanceKey={editorKey}
            isMaximized={false}
          />
        </div>
      )}
      <div className="mt-2 text-right font-pixel text-pixel text-muted-foreground">
        type / for formatting
      </div>
    </div>
  );

  const summaryView = isSourceLoading ? (
    <LoadingState />
  ) : summary ? (
    <div className="prose prose-sm max-w-none text-[15px] leading-[1.6] text-ink prose-headings:font-medium prose-strong:font-medium prose-a:text-ink">
      <ReactMarkdown>{summary}</ReactMarkdown>
    </div>
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

  const originalView = isSourceLoading ? (
    <LoadingState />
  ) : pageBody ? (
    <ReadOnlyText text={pageBody} />
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

  const tabViews: Record<ContentTabKey, React.ReactNode> = {
    notes: notesEditor,
    summary: summaryView,
    original: originalView,
    transcript: transcriptView,
  };

  const sourceTabs = config.tabs.filter((tab) => tab.key !== 'notes');
  return (
    <>
      <section className="mt-[30px]" aria-label="Notes">
        <SectionHead label="Notes" aside={
          <button onClick={onMaximize} title="Maximize editor" aria-label="Maximize editor"
            className="grid h-6 w-6 place-items-center text-muted-foreground hover:bg-ink hover:text-white">
            <Maximize className="h-3.5 w-3.5" />
          </button>
        } />
        <div className="mt-3.5">{notesEditor}</div>
      </section>
      {sourceTabs.length > 0 && (
        <section className="mt-[30px]" aria-label={config.title}>
          <SectionHead label={config.title} aside={sourceTabs.length > 1 && (
            <div className="-mb-1.5 flex flex-wrap gap-[3px]" role="tablist" aria-label="Source content">
              {sourceTabs.map((tab) => (
                <button key={tab.key} role="tab" aria-selected={activeTab === tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`h-7 px-2 font-pixel text-pixel lowercase leading-none transition-colors ${
                    activeTab === tab.key ? 'bg-ink text-white' : 'text-muted-foreground hover:bg-fill hover:text-ink'
                  }`}>
                  {tab.label}
                </button>
              ))}
            </div>
          )} />
          <div className="mt-3.5">{tabViews[activeTab === 'notes' ? sourceTabs[0].key : activeTab]}</div>
        </section>
      )}
    </>
  );
};

export default EditItemContentSection;
