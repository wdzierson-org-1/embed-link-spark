import React, { useEffect, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import { Button } from '@/components/ui/button';
import { Maximize, Loader2, Sparkles } from 'lucide-react';
import EditItemContentEditor from '@/components/EditItemContentEditor';
import { SectionHead } from '@/components/edit/EditPanelSection';
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

const looksLikeMarkdown = (text: string): boolean =>
  /(^|\n)#{1,6}\s|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|(^|\n)\s*[-*]\s/.test(text);

// Source material sits directly on the panel surface — no nested box
const ReadOnlyText = ({ text, capped = true }: { text: string; capped?: boolean }) => (
  <div className={capped ? 'max-h-[420px] overflow-y-auto pr-1' : ''}>
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
  <div className="flex min-h-[120px] flex-col items-center justify-center gap-3 px-6 py-8 text-center text-sm text-[#959ba6]">
    {children}
  </div>
);

const LoadingState = () => (
  <div className="flex min-h-[120px] items-center justify-center text-sm text-[#959ba6]">
    <Loader2 className="mr-2 h-4 w-4 animate-spin motion-reduce:animate-none" />
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
        <div className="flex min-h-[300px] items-center justify-center text-sm text-[#959ba6]">
          Loading editor...
        </div>
      ) : !mobileEditorReady && isMobile ? (
        <div className="flex min-h-[300px] items-center justify-center text-sm text-[#959ba6]">
          <div className="text-center">
            <div className="animate-pulse motion-reduce:animate-none">Initializing editor...</div>
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
      <div className="absolute bottom-3 right-3 rounded bg-background/80 px-2 py-1 text-xs text-[#959ba6] backdrop-blur-sm">
        Press / for formatting options
      </div>
    </div>
  );

  const summaryView = isSourceLoading ? (
    <LoadingState />
  ) : summary ? (
    <div className="prose prose-sm max-w-none text-foreground/90">
      <ReactMarkdown>{summary}</ReactMarkdown>
    </div>
  ) : pageBody ? (
    <TabEmptyState>
      <span>No summary yet for this {isDocument ? 'document' : 'link'}.</span>
      <Button
        size="sm"
        onClick={() => void generateSummary()}
        disabled={isGenerating}
        className="rounded-xl bg-[#6d5bd0] text-white shadow-sm hover:bg-[#5f4ec2]"
      >
        {isGenerating ? (
          <>
            <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin motion-reduce:animate-none" />
            Summarizing...
          </>
        ) : (
          <>
            <Sparkles className="mr-1.5 h-3.5 w-3.5" />
            Generate summary
          </>
        )}
      </Button>
      {generateError && <span className="text-xs text-[#c93a3a]">{generateError}</span>}
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
    <div className="mt-[30px]">
      <SectionHead
        label={config.title}
        aside={
          <div className="flex flex-wrap items-center justify-end gap-1.5">
            {config.tabs.length > 1 && (
              <div className="flex gap-0.5">
                {config.tabs.map((tab) => (
                  <button
                    key={tab.key}
                    onClick={() => setActiveTab(tab.key)}
                    className={`rounded-full px-2.5 py-[3px] text-[12.5px] font-medium transition-colors ${
                      activeTab === tab.key
                        ? 'bg-[rgba(20,22,30,0.06)] text-[#22262f]'
                        : 'text-[#959ba6] hover:text-[#646b76]'
                    }`}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>
            )}
            {activeTab === 'notes' && (
              <button
                onClick={onMaximize}
                title="Maximize editor"
                aria-label="Maximize editor"
                className="grid h-6 w-6 place-items-center rounded-md text-[#959ba6] transition-colors hover:bg-black/[0.04] hover:text-[#22262f]"
              >
                <Maximize className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        }
      />

      <div className="mt-3.5">{tabViews[activeTab]}</div>
    </div>
  );
};

export default EditItemContentSection;
