
import React from 'react';
import CardInlineNote from '@/components/cards/CardInlineNote';
import CollectionAttachmentStrip from '@/components/CollectionAttachmentStrip';
import type { Attachment } from '@/components/CollectionAttachments';
import { extractPlainTextFromNovelContent } from '@/utils/contentExtractor';
import { cleanMetaText } from '@/utils/textHygiene';
import {
  formatDurationChip,
  formatFileSizeChip,
  MetaChip,
  mimeExtensionLabel,
} from '@/components/cards/CardBits';
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
  /** The AI description/summary just landed — animate it in */
  revealDescription?: boolean;
  onNoteSaved?: () => void;
}

const ContentItemContent = ({
  item,
  expandedContent,
  onToggleExpansion,
  isPublicView,
  collectionAttachments,
  revealDescription,
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

  // Objects: extracted description speaks first; the user's annotation
  // (content) is visually theirs; extracted facts ride as chips

  // Type identity lives beside the date; facts remain in the body.
  const chips: React.ReactNode[] = [];

  const facts = [mimeExtensionLabel(item.mime_type), formatFileSizeChip(item.file_size)].filter(Boolean).join(' · ');
  if (facts && item.type !== 'link') {
    chips.push(
      <MetaChip key="facts" mono>
        {facts}
      </MetaChip>
    );
  }

  const salientFact = (() => {
    if (item.type === 'audio' || item.type === 'video') {
      return formatDurationChip(item.attributes?.media?.duration_s);
    }
    if (item.type === 'link') {
      const link = item.attributes?.link;
      if (link?.flavor === 'video') return formatDurationChip(link.duration_s);
      if (typeof link?.read_time_min === 'number' && link.read_time_min > 0) {
        return `${Math.round(link.read_time_min)} min read`;
      }
    }
    return null;
  })();
  if (salientFact) {
    chips.push(<MetaChip key="fact">{salientFact}</MetaChip>);
  }

  return (
    <div className="space-y-2.5">
      {item.description && (
        // Wrapper carries the reveal animation — the clamped paragraph's
        // -webkit-box/overflow-hidden would clip the highlight wash
        <div className={revealDescription ? 'animate-piece-in' : undefined}>
          <p className="text-muted-foreground text-sm line-clamp-3">
            {cleanMetaText(extractPlainTextFromNovelContent(item.description))}
          </p>
        </div>
      )}

      <CardInlineNote item={item} readOnly={isPublicView} onSaved={onNoteSaved} />

      {chips.length > 0 && <div className="flex flex-wrap gap-1.5">{chips}</div>}
    </div>
  );
};

export default ContentItemContent;
