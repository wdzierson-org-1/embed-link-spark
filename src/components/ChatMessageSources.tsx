
import React from 'react';
import { domainOfUrl } from '@/utils/linkFlavor';

interface Source {
  id: string;
  title: string;
  type: string;
  url?: string;
}

interface ChatMessageSourcesProps {
  sources: Source[];
  onSourceClick: (sourceId: string) => void;
  /** Kept for callers; the row no longer shows a "View all" control (Ask's "show sources" does it) */
  onViewAllSources?: (sourceIds: string[]) => void;
}

const KIND: Record<string, string> = { text: 'note', link: 'link', image: 'photo', audio: 'audio', video: 'video', document: 'doc', collection: 'multi-part' };

/**
 * An answer's citations that weren't already linked in its text, as small object cards
 * (DESIGN-v2 "Chat windows": citations are small object cards). Each opens its save.
 */
const ChatMessageSources = ({ sources, onSourceClick }: ChatMessageSourcesProps) => {
  if (!sources || sources.length === 0) {
    return null;
  }

  return (
    <div className="mt-3">
      <p className="mb-1.5 font-pixel text-pixel text-muted-foreground">also from</p>
      <ul className="space-y-1.5">
        {sources.map((source, index) => (
          <li key={source.id}>
            <button
              type="button"
              onClick={() => onSourceClick(source.id)}
              className="flex w-full min-w-0 items-center gap-2.5 rounded-object border border-line bg-white px-2.5 py-2 text-left transition-[border-color,box-shadow,transform] duration-150 hover:-translate-x-px hover:-translate-y-px hover:border-ink hover:shadow-print-sm"
            >
              <span className="flex-none bg-ink px-1.5 pb-[3px] pt-1 font-pixel text-pixel leading-none text-white">
                {KIND[source.type] ?? source.type}
              </span>
              <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-ink">
                {source.title || `Save ${index + 1}`}
              </span>
              {source.url && (
                <span className="hidden flex-none font-pixel text-pixel text-muted-foreground sm:inline">
                  {domainOfUrl(source.url)}
                </span>
              )}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
};

export default ChatMessageSources;
