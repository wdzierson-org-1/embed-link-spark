
import React from 'react';
import CardInlineNote from '@/components/cards/CardInlineNote';
import CollectionAttachmentStrip from '@/components/CollectionAttachmentStrip';
import type { Attachment } from '@/components/CollectionAttachments';
import { extractPlainTextFromNovelContent } from '@/utils/contentExtractor';
import { cleanMetaText } from '@/utils/textHygiene';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  content?: string;
  description?: string;
  url?: string;
  file_path?: string;
  file_size?: number;
  mime_type?: string;
  attributes?: ItemAttributes;
}

interface ContentItemContentProps {
  item: ContentItem;
  expandedContent: Set<string>;
  onToggleExpansion: (itemId: string) => void;
  isPublicView?: boolean;
  collectionAttachments?: Attachment[];
  /** The AI description/summary just landed — print it in */
  revealDescription?: boolean;
  /** Stash is still gathering: hold the description's place with dotted lines */
  awaitingDescription?: boolean;
  onNoteSaved?: () => void;
}

const ContentItemContent = ({
  item,
  isPublicView,
  collectionAttachments,
  revealDescription,
  awaitingDescription,
  onNoteSaved,
}: ContentItemContentProps) => {
  // Legacy multi-part items: rich note + attachment tiles (frozen design)
  if (item.type === 'collection') {
    return (
      <div className="space-y-3">
        <CardInlineNote item={item} readOnly={isPublicView} onSaved={onNoteSaved} />

        <CollectionAttachmentStrip itemId={item.id} attachments={collectionAttachments} />
      </div>
    );
  }

  // Text notes: the words ARE the object — show them, not the AI summary
  if (item.type === 'text') {
    return (
      <div className="space-y-2.5">
        <CardInlineNote item={item} readOnly={isPublicView} onSaved={onNoteSaved} />
      </div>
    );
  }

  // Objects: the extracted description speaks first; the person's note (content) is visibly
  // theirs. Facts (format, size, duration, read time) ride in the meta row below.
  const description = item.description ? cleanMetaText(extractPlainTextFromNovelContent(item.description)) : '';

  return (
    <div className="space-y-3">
      {description ? (
        // Wrapper carries the print-in; the clamped paragraph's -webkit-box would clip it
        <div className={revealDescription ? 'v2-print-in' : undefined}>
          <p className="line-clamp-3 text-sm leading-[1.42] text-muted-foreground">{description}</p>
        </div>
      ) : awaitingDescription ? (
        // DESIGN-v2 "while reading": dotted skeleton lines in the machine voice
        <div aria-hidden className="space-y-0.5 overflow-hidden whitespace-nowrap font-pixel text-pixel tracking-[0.05em] text-[#b9bdb5]">
          <span className="block">··································</span>
          <span className="block">·······················</span>
        </div>
      ) : null}

      <CardInlineNote item={item} readOnly={isPublicView} onSaved={onNoteSaved} />
    </div>
  );
};

export default ContentItemContent;
