
import React from 'react';
import CollectionAttachmentStrip from '@/components/CollectionAttachmentStrip';
import type { Attachment } from '@/components/CollectionAttachments';
import ReadOnlyNovelRenderer from '@/components/ReadOnlyNovelRenderer';
import { extractPlainTextFromNovelContent } from '@/utils/contentExtractor';
import { CardAnnotation, formatDurationChip, formatFileSizeChip, MetaChip, mimeExtensionLabel } from '@/components/cards/CardBits';
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
}

const ContentItemContent = ({
  item,
  expandedContent,
  onToggleExpansion,
  isPublicView,
  collectionAttachments,
}: ContentItemContentProps) => {
  // Legacy multi-part items: rich note + attachment tiles (frozen design)
  if (item.type === 'collection') {
    const note = item.content?.trim();
    return (
      <div className="space-y-3">
        {note ? (
          <ReadOnlyNovelRenderer content={note} maxLines={6} />
        ) : item.description ? (
          <p className="text-muted-foreground text-sm line-clamp-2">
            {extractPlainTextFromNovelContent(item.description)}
          </p>
        ) : null}

        <CollectionAttachmentStrip itemId={item.id} attachments={collectionAttachments} />
      </div>
    );
  }

  // Text notes: the words ARE the object — show them, not the AI summary
  if (item.type === 'text') {
    const body = item.content ? extractPlainTextFromNovelContent(item.content).trim() : '';
    return (
      <div className="space-y-2.5">
        {body ? (
          <p className="line-clamp-4 whitespace-pre-line text-sm leading-relaxed text-foreground/75">{body}</p>
        ) : item.description ? (
          <p className="text-muted-foreground text-sm line-clamp-3">
            {extractPlainTextFromNovelContent(item.description)}
          </p>
        ) : null}
      </div>
    );
  }

  // Objects: extracted description speaks first; the user's annotation
  // (content) is visually theirs; extracted facts ride as chips
  const annotation = item.content ? extractPlainTextFromNovelContent(item.content).trim() : '';

  const chips: React.ReactNode[] = [];
  const fileName = item.attributes?.media?.file_name;
  if (fileName && (item.type === 'image' || item.type === 'audio' || item.type === 'video')) {
    chips.push(
      <MetaChip key="file" mono>
        {fileName}
      </MetaChip>
    );
  }
  const facts = [mimeExtensionLabel(item.mime_type), formatFileSizeChip(item.file_size)].filter(Boolean).join(' · ');
  if (facts && item.type !== 'document' && item.type !== 'link') {
    chips.push(<MetaChip key="facts">{facts}</MetaChip>);
  }
  const duration = formatDurationChip(item.attributes?.media?.duration_s);
  if (duration && item.type === 'audio') {
    chips.push(<MetaChip key="duration">{duration}</MetaChip>);
  }

  return (
    <div className="space-y-2.5">
      {item.description && (
        <p className="text-muted-foreground text-sm line-clamp-3">
          {extractPlainTextFromNovelContent(item.description)}
        </p>
      )}

      {annotation && <CardAnnotation>{annotation}</CardAnnotation>}

      {chips.length > 0 && <div className="flex flex-wrap gap-1.5">{chips}</div>}
    </div>
  );
};

export default ContentItemContent;
