import React, { useEffect, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { Button } from '@/components/ui/button';
import { Maximize, FileText, Loader2, Sparkles } from 'lucide-react';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import { useItemSourceContent } from '@/hooks/useItemSourceContent';
import { getContentTabsConfig, needsSourceContent, type ContentTabKey } from '@/utils/editPanelTabs';

interface ContentItem {
  id: string;
  type?: string;
  title?: string;
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

const sectionCard =
  'rounded-2xl border border-black/5 bg-white p-4 shadow-[0_1px_2px_rgba(0,0,0,0.05),0_6px_18px_rgba(160,120,200,0.08)]';
const sectionLabel = 'flex items-center gap-1.5 text-[13px] font-medium text-muted-foreground';

const looksLikeMarkdown = (text: string): boolean =>
  /(^|\n)#{1,6}\s|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|(^|\n)\s*[-*]\s/.test(text);

const ReadOnlyText = ({ text, capped = true }: { text: string; capped?: boolean }) => (
  <div className={`rounded-xl border border-black/5 bg-gray-50/60 px-4 py-3 ${capped ? 'max-h-[420px] overflow-y-auto' : ''}`}>
    {looksLikeMarkdown(text) ? (
      <div className="prose prose-sm max-w-none text-foreground/90">
        <ReactMarkdown>{text}</ReactMarkdown>
      </div>
    ) : (
      <div className="whitespace-pre-wrap text-sm leading-relaxed text-foreground/90">{text}</div>
    )}
  </div>
);

const TabEmptyState = ({ children }: { children: React.ReactNode }) => (
  <div className="flex min-h-[140px] flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-black/10 bg-gray-50/40 px-6 py-8 text-center text-sm text-muted-foreground">
    {children}
  </div>
);

const LoadingState = () => (
  <div className="flex min-h-[140px] items-center justify-center rounded-xl border border-black/5 bg-gray-50/40 text-sm text-muted-foreground">
    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
    Loading...
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

  const {
    summary,
    pageBody,
    isLoading: isSourceLoading,
    isGenerating,
    generateError,
    generateSummary,
  } = useItemSourceContent(item?.id, needsSourceContent(item?.type));

  const isDocument = item?.type === 'document' || item?.type === 'pdf';

  const notesEditor = (
    <div className="relative">
      {isContentLoading ? (
        <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
          Loading editor...
        </div>
      ) : !mobileEditorReady && isMobile ? (
        <div className="border rounded-md p-4 min-h-[300px] flex items-center justify-center text-muted-foreground">
          <div className="text-center">
            <div className="animate-pulse">Initializing editor...</div>
          </div>
        </div>
      ) : (
        <div className={`${isMobile ? 'min-h-[400px]' : ''}`}>
          <EditItemContentEditor
            content={content}
            onContentChange={onContentChange}
            itemId={item?.id}
            editorInstanceKey={editorKey}
            isMaximized={false}
          />
        </div>
      )}
      <div className="absolute bottom-3 right-3 text-xs text-muted-foreground bg-background/80 backdrop-blur-sm px-2 py-1 rounded">
        Press / for formatting options
      </div>
    </div>
  );

  const summaryView = isSourceLoading ? (
    <LoadingState />
  ) : summary ? (
    <div className="prose prose-sm max-w-none px-1 text-foreground/90">
      <ReactMarkdown>{summary}</ReactMarkdown>
    </div>
  ) : pageBody ? (
    <TabEmptyState>
      <span>No summary yet for this {isDocument ? 'document' : 'link'}.</span>
      <Button
        size="sm"
        onClick={() => void generateSummary()}
        disabled={isGenerating}
        className="rounded-xl bg-gradient-to-b from-violet-500 to-violet-600 text-white shadow-sm hover:from-violet-600 hover:to-violet-700"
      >
        {isGenerating ? (
          <>
            <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
            Summarizing...
          </>
        ) : (
          <>
            <Sparkles className="mr-1.5 h-3.5 w-3.5" />
            Generate summary
          </>
        )}
      </Button>
      {generateError && <span className="text-xs text-red-500">{generateError}</span>}
    </TabEmptyState>
  ) : (
    <TabEmptyState>
      {isDocument
        ? 'Content is still being extracted from this document.'
        : "We haven't been able to read this page's content yet."}
    </TabEmptyState>
  );

  const originalView = isSourceLoading ? (
    <LoadingState />
  ) : pageBody ? (
    <ReadOnlyText text={pageBody} />
  ) : (
    <TabEmptyState>
      {isDocument
        ? 'Content is still being extracted from this document.'
        : 'No page content captured from this link yet.'}
    </TabEmptyState>
  );

  const transcriptView = isSourceLoading ? (
    <LoadingState />
  ) : pageBody ? (
    <ReadOnlyText text={pageBody} />
  ) : (
    <TabEmptyState>No transcript available for this recording.</TabEmptyState>
  );

  const tabViews: Record<ContentTabKey, React.ReactNode> = {
    notes: notesEditor,
    summary: summaryView,
    original: originalView,
    transcript: transcriptView,
  };

  return (
    <div className={`${sectionCard} space-y-2`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <label className={sectionLabel}>
          <FileText className="h-3.5 w-3.5" />
          {config.title}
        </label>
        <div className="flex items-center gap-1.5">
          {config.tabs.length > 1 && (
            <div className="inline-flex rounded-xl border border-black/5 bg-gray-100/80 p-0.5">
              {config.tabs.map((tab) => (
                <button
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`rounded-[10px] px-2.5 py-1 text-[12px] font-medium transition-colors ${
                    activeTab === tab.key
                      ? 'bg-white text-foreground shadow-sm'
                      : 'text-muted-foreground hover:text-foreground'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>
          )}
          {activeTab === 'notes' && (
            <Button
              variant="ghost"
              size="sm"
              onClick={onMaximize}
              className="h-8 w-8 rounded-lg border border-black/5 bg-white p-0 shadow-sm"
              title="Maximize editor"
            >
              <Maximize className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>

      {tabViews[activeTab]}
    </div>
  );
};

export default EditItemContentSection;
