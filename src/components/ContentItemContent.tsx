
import React from 'react';
import CollectionAttachmentStrip from '@/components/CollectionAttachmentStrip';
import type { Attachment } from '@/components/CollectionAttachments';
import ReadOnlyNovelRenderer from '@/components/ReadOnlyNovelRenderer';
import { extractPlainTextFromNovelContent } from '@/utils/contentExtractor';
import { cleanMetaText } from '@/utils/textHygiene';
import { AudioLines, File, Mic, ScanLine, Table2 } from 'lucide-react';
import {
  audioSubtype,
  CardAnnotation,
  formatDurationChip,
  formatFileSizeChip,
  isScreenshotItem,
  isSpreadsheetExt,
  MetaChip,
  mimeExtensionLabel,
  TypeChip,
} from '@/components/cards/CardBits';
import type { ItemAttributes } from '@/types/itemAttributes';

const CHIP_ICON = 'h-[11px] w-[11px]';

const LINK_FLAVOR_LABELS: Record<string, string> = {
  article: 'article',
  video: 'video',
  repo: 'repo',
  book: 'book',
  social: 'post',
  generic: 'link',
};

/**
 * Chips grammar (DESIGN.md), in order, nothing else: tinted type chip
 * (always visible) → format·size (mono) → one salient fact.
 */
const typeChipFor = (item: {
  type: string;
  title?: string;
  mime_type?: string;
  attributes?: ItemAttributes;
}): React.ReactNode => {
  switch (item.type) {
    case 'audio':
      return audioSubtype(item.attributes) === 'voice_note' ? (
        <TypeChip key="type" tint="voice" icon={<Mic className={CHIP_ICON} />}>
          voice note
        </TypeChip>
      ) : (
        <TypeChip key="type" tint="audio" icon={<AudioLines className={CHIP_ICON} />}>
          recording
        </TypeChip>
      );
    case 'document': {
      const ext = mimeExtensionLabel(item.mime_type);
      return isSpreadsheetExt(ext) ? (
        <TypeChip key="type" tint="doc" icon={<Table2 className={CHIP_ICON} />}>
          spreadsheet
        </TypeChip>
      ) : (
        <TypeChip key="type" tint="doc" icon={<File className={CHIP_ICON} />}>
          {ext ? ext.toLowerCase() : 'document'}
        </TypeChip>
      );
    }
    case 'image':
      return isScreenshotItem(item) ? (
        <TypeChip key="type" tint="shot" icon={<ScanLine className={CHIP_ICON} />}>
          screenshot
        </TypeChip>
      ) : (
        <MetaChip key="type">photo</MetaChip>
      );
    case 'video':
      return <MetaChip key="type">video</MetaChip>;
    case 'text':
      return <MetaChip key="type">note</MetaChip>;
    case 'link':
      return (
        <MetaChip key="type">{LINK_FLAVOR_LABELS[item.attributes?.link?.flavor ?? 'generic'] ?? 'link'}</MetaChip>
      );
    default:
      return null;
  }
};

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
}

const ContentItemContent = ({
  item,
  expandedContent,
  onToggleExpansion,
  isPublicView,
  collectionAttachments,
  revealDescription,
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
            {cleanMetaText(extractPlainTextFromNovelContent(item.description))}
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
            {cleanMetaText(extractPlainTextFromNovelContent(item.description))}
          </p>
        ) : null}
        <div className="flex flex-wrap gap-1.5">{typeChipFor(item)}</div>
      </div>
    );
  }

  // Objects: extracted description speaks first; the user's annotation
  // (content) is visually theirs; extracted facts ride as chips
  const annotation = item.content ? extractPlainTextFromNovelContent(item.content).trim() : '';

  // Chips, in grammar order: type chip → format·size (mono) → one salient fact
  const chips: React.ReactNode[] = [];
  const typeChip = typeChipFor(item);
  if (typeChip) chips.push(typeChip);

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

      {annotation && <CardAnnotation>{annotation}</CardAnnotation>}

      {chips.length > 0 && <div className="flex flex-wrap gap-1.5">{chips}</div>}
    </div>
  );
};

export default ContentItemContent;
