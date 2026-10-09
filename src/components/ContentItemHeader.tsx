
import React, { useState } from 'react';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { isReadingDocument } from '@/utils/itemAssembly';
import { libraryTitleClass } from '@/utils/libraryPresentation';
import { decodeHtmlEntities } from '@/utils/textHygiene';
import { useNow } from '@/hooks/useNow';
import { reminderState } from '@/utils/reminders';
import {
  AspectAwareImage,
  DocumentHero,
  FilePlate,
  LinkCover,
  LinkPlaceholder,
  PlayerHero,
  RepoPlate,
  VideoPosterHero,
} from '@/components/cards/CardHero';
import {
  audioSubtype,
  formatFileSizeChip,
  mimeExtensionLabel,
} from '@/components/cards/CardBits';
import { kindGlyph, kindLabel } from '@/components/cards/ItemTypeChip';
import KindTag, { type KindTagPhase } from '@/components/cards/KindTag';
import { Tag } from '@/components/machine/Machine';
import { useDecrypt } from '@/components/machine/useDecrypt';
import type { ItemAttributes } from '@/types/itemAttributes';

interface ContentItem {
  id: string;
  type: 'text' | 'link' | 'image' | 'audio' | 'video' | 'document' | 'collection';
  title?: string;
  content?: string;
  description?: string;
  file_path?: string;
  file_size?: number;
  mime_type?: string;
  is_public?: boolean;
  url?: string;
  summary?: string;
  created_at?: string;
  attributes?: ItemAttributes;
  remind_at?: string | null;
  reminder_cleared_at?: string | null;
  pinned_at?: string | null;
}

interface ContentItemHeaderProps {
  item: ContentItem;
  imageErrors: Set<string>;
  onImageError: (itemId: string) => void;
  onEditItem: (item: ContentItem) => void;
  isPublicView?: boolean;
  /** Enrichment pieces that just landed — animate them in */
  reveals?: { title?: boolean; preview?: boolean };
  /** Stash is reading this save right now: its picture stays unresolved until it's done */
  reading?: boolean;
  /** The machine's status line for a card without a hero ("| gathering more info…"), under the title */
  status?: React.ReactNode;
  /** On a hero, the kind tag carries the status instead (KindTag) */
  kindTag?: { phase: KindTagPhase; busyLabel: string };
}

const ContentItemHeader = ({
  item,
  imageErrors,
  onImageError,
  onEditItem,
  isPublicView = false,
  reveals,
  reading = false,
  status,
  kindTag,
}: ContentItemHeaderProps) => {
  const [linkCoverFailed, setLinkCoverFailed] = useState(false);
  const now = useNow();
  // Only while the PDF is genuinely being read: one whose extraction failed must still open
  const isProcessing = isReadingDocument(item, now.getTime());
  const isDue = !isPublicView && reminderState(item, now) === 'due';
  const isPinned = !isPublicView && Boolean(item.pinned_at);
  const title = item.title ? decodeHtmlEntities(item.title) : '';
  // A title that lands while the person watches decrypts in; static titles never scramble
  const decrypted = useDecrypt(title, Boolean(reveals?.title));

  const getFileUrl = () => {
    if (item.file_path && !item.file_path.startsWith('http')) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return null;
  };

  const handleTitleClick = () => {
    if (isPublicView && item.type === 'link' && item.url) {
      window.open(item.url, '_blank');
    } else if (!isPublicView) {
      onEditItem(item);
    }
  };

  const fileUrl = getFileUrl();
  const flavor = item.attributes?.link?.flavor ?? 'generic';
  const mediaFileName = item.attributes?.media?.file_name ?? null;
  const fileFactsLine = [mimeExtensionLabel(item.mime_type), formatFileSizeChip(item.file_size)]
    .filter(Boolean)
    .join(' · ');

  // The link's preview image: storage paths serve directly, external og
  // images route through the proxy first (CORS/hotlinking)
  const linkCoverSource = (() => {
    if (item.type !== 'link' || !item.file_path) return null;
    if (!item.file_path.startsWith('http')) {
      const { data } = supabase.storage.from('stash-media').getPublicUrl(item.file_path);
      return data.publicUrl;
    }
    return `${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(item.file_path)}`;
  })();

  // A picture that lands while the person watches resolves in from coarse pixel blocks
  const arriving = Boolean(reveals?.preview);

  /** Object zone per type; null = the card opens with its title */
  const renderHero = (): React.ReactNode => {
    switch (item.type) {
      case 'text':
      case 'collection':
        return null;

      case 'audio': {
        if (!fileUrl) return null;
        return (
          <PlayerHero
            itemId={item.id}
            src={fileUrl}
            kind={audioSubtype(item.attributes)}
            durationS={item.attributes?.media?.duration_s}
            reading={reading}
          />
        );
      }

      case 'video': {
        if (!fileUrl) return null;
        return (
          <VideoPosterHero src={fileUrl} durationS={item.attributes?.media?.duration_s} />
        );
      }

      case 'document':
        return <DocumentHero ext={mimeExtensionLabel(item.mime_type)} reading={reading} />;

      case 'image': {
        if (fileUrl && !imageErrors.has(item.id)) {
          return (
            <AspectAwareImage
              src={fileUrl}
              alt={item.title || 'Image'}
              onError={() => onImageError(item.id)}
              reading={reading}
              arriving={arriving}
            />
          );
        }
        return <FilePlate kind="image" fileName={mediaFileName} factsLine={fileFactsLine || null} />;
      }

      case 'link': {
        if (!item.url) return null;
        if (flavor === 'repo') {
          return <RepoPlate url={item.url} description={item.description} />;
        }
        if (linkCoverSource && !linkCoverFailed && !imageErrors.has(item.id)) {
          const tall = flavor === 'video' || flavor === 'book';
          return (
            <LinkCover
              imageSource={linkCoverSource}
              alt={item.title || 'Link preview'}
              tall={tall}
              playOverlay={flavor === 'video'}
              onFailed={() => setLinkCoverFailed(true)}
              reading={reading}
              arriving={arriving}
            />
          );
        }
        return <LinkPlaceholder url={item.url} glyph={kindGlyph(item)} reading={reading} />;
      }

      default:
        return null;
    }
  };

  const hero = renderHero();
  const isVideoHero = item.type === 'video' && Boolean(fileUrl);
  // Pictures resolve in from pixel blocks on arrival; drawn heroes print in
  const heroIsPicture =
    (item.type === 'image' && Boolean(fileUrl) && !imageErrors.has(item.id)) ||
    (item.type === 'link' && flavor !== 'repo' && Boolean(linkCoverSource) && !linkCoverFailed && !imageErrors.has(item.id));
  const kind = kindLabel(item);
  const stateTags = !isPublicView && (
    <>
      {isPinned && <Tag>pinned</Tag>}
      {item.is_public && <Tag variant="white">public</Tag>}
      {isDue && (
        <Tag data-testid="due-pill">due</Tag>
      )}
    </>
  );

  return (
    <div>
      {hero ? (
        <div className={`relative ${arriving && !heroIsPicture ? 'v2-print-in' : ''}`}>
          {isVideoHero ? (
            hero
          ) : (
            <div
              onClick={!isProcessing ? handleTitleClick : undefined}
              className={!isProcessing ? 'cursor-pointer' : undefined}
            >
              {hero}
            </div>
          )}

          {/* The machine's labels on the object: its kind top-left (the status while reading;
              hidden at rest until hovered), its states top-right */}
          <KindTag
            kind={kind}
            phase={isPublicView ? 'idle' : kindTag?.phase}
            busyLabel={kindTag?.busyLabel}
            className="pointer-events-none absolute left-2.5 top-2.5 z-[4]"
          />
          {stateTags && (item.is_public || isDue || isPinned) && (
            <div className="absolute right-2.5 top-2.5 z-[4] flex gap-1">{stateTags}</div>
          )}
        </div>
      ) : (item.is_public || isDue || isPinned) && !isPublicView ? (
        <div className="flex gap-1 px-5 pt-4">{stateTags}</div>
      ) : null}

      {/* Title: the AI's (or the person's) reading of the object, never a filename */}
      {title ? (
        <div className={`px-5 ${hero ? 'pt-4' : (item.is_public || isDue || isPinned) && !isPublicView ? 'pt-3' : 'pt-[18px]'}`}>
          <button
            type="button"
            onClick={handleTitleClick}
            disabled={isPublicView ? !(item.type === 'link' && item.url) : isProcessing}
            aria-disabled={!isPublicView && isProcessing}
            aria-label={decrypted.scrambling ? title : undefined}
            className={`group/title w-full text-left ${
              isPublicView && !(item.type === 'link' && item.url) ? 'cursor-default' : isProcessing ? 'cursor-progress' : 'cursor-pointer'
            }`}
          >
            <h3
              className={`${libraryTitleClass()} line-clamp-2 text-object-title text-ink ${
                decrypted.scrambling ? 'v2-decrypting' : ''
              } ${!isProcessing ? 'decoration-1 underline-offset-[3px] group-hover/title:underline' : ''}`}
            >
              {decrypted.display}
            </h3>
          </button>
          {status && !hero && <div className="mt-1.5">{status}</div>}
        </div>
      ) : status && !hero ? (
        // No title yet and no hero to carry the status: the line stands in for the title
        <div className="px-5 pt-[18px]">{status}</div>
      ) : null}
    </div>
  );
};

export default ContentItemHeader;
