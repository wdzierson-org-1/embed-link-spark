
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Badge } from '@/components/ui/badge';
import { Expand } from 'lucide-react';
import { supabase, SUPABASE_URL } from '@/integrations/supabase/client';
import { isDocumentProcessing } from '@/utils/documentProcessing';
import { domainOfUrl } from '@/utils/linkFlavor';
import {
  AspectAwareImage,
  FaviconPlate,
  FilePlate,
  LinkCover,
  RepoPlate,
} from '@/components/cards/CardHero';
import { formatDurationChip, formatFileSizeChip, mimeExtensionLabel } from '@/components/cards/CardBits';
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
  attributes?: ItemAttributes;
}

interface ContentItemHeaderProps {
  item: ContentItem;
  imageErrors: Set<string>;
  onImageError: (itemId: string) => void;
  onEditItem: (item: ContentItem) => void;
  onVideoExpand?: () => void;
  isPublicView?: boolean;
  /** Enrichment pieces that just landed — animate them in */
  reveals?: { title?: boolean; preview?: boolean };
}

const ContentItemHeader = ({
  item,
  imageErrors,
  onImageError,
  onEditItem,
  onVideoExpand,
  isPublicView = false,
  reveals
}: ContentItemHeaderProps) => {
  const [linkCoverFailed, setLinkCoverFailed] = useState(false);
  const isProcessing = isDocumentProcessing(item);

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
  const domain = domainOfUrl(item.url);
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

  /** Object zone per type; null = the card opens with its title */
  const renderHero = (): React.ReactNode => {
    switch (item.type) {
      case 'text':
      case 'audio':
      case 'collection':
        return null;

      case 'video': {
        if (!fileUrl) return null;
        const duration = formatDurationChip(item.attributes?.media?.duration_s);
        return (
          <div className="relative w-full h-48 bg-black rounded-t-2xl overflow-hidden">
            <video src={fileUrl} className="w-full h-full object-cover" controls preload="metadata">
              Your browser does not support the video tag.
            </video>
            {duration && (
              <span className="pointer-events-none absolute bottom-2 right-2 rounded-md bg-black/70 px-1.5 py-0.5 text-[11px] font-medium text-white">
                {duration}
              </span>
            )}
            <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
              <Button
                variant="ghost"
                size="sm"
                onClick={onVideoExpand}
                className="h-8 w-8 rounded-full bg-black/50 hover:bg-black/70 text-white p-0"
              >
                <Expand className="h-4 w-4" />
              </Button>
            </div>
          </div>
        );
      }

      case 'document':
        return <FilePlate kind="document" fileName={mediaFileName} factsLine={fileFactsLine || null} />;

      case 'image': {
        if (fileUrl && !imageErrors.has(item.id)) {
          return (
            <AspectAwareImage
              src={fileUrl}
              alt={item.title || 'Image'}
              onError={() => onImageError(item.id)}
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
              domainPill={tall ? domain : undefined}
              onFailed={() => setLinkCoverFailed(true)}
            />
          );
        }
        return <FaviconPlate url={item.url} />;
      }

      default:
        return null;
    }
  };

  const hero = renderHero();
  const isVideoHero = item.type === 'video' && Boolean(fileUrl);
  const showInlineBadges = !hero && !isPublicView && (isProcessing || item.is_public);
  const showKicker = item.type === 'link' && Boolean(domain);

  return (
    <TooltipProvider>
      <div>
        {hero ? (
          <div className={`relative ${reveals?.preview ? 'animate-piece-in' : ''}`}>
            {isVideoHero ? (
              hero
            ) : (
              <div
                onClick={!isProcessing ? handleTitleClick : undefined}
                className={!isProcessing ? 'cursor-pointer' : undefined}
                title={!isProcessing ? 'Click to edit' : undefined}
              >
                {hero}
              </div>
            )}

            {/* Badges in top right corner */}
            {!isPublicView && (
              <div className="absolute top-2 right-2 z-10 flex gap-2">
                {isProcessing && (
                  <Badge variant="secondary" className="animate-pulse">
                    Processing...
                  </Badge>
                )}
                {item.is_public && (
                  <div className="bg-primary text-primary-foreground px-2 py-1 rounded text-xs font-medium">
                    PUBLICLY SHARED
                  </div>
                )}
              </div>
            )}
          </div>
        ) : showInlineBadges ? (
          <div className="flex gap-2 px-6 pt-4">
            {isProcessing && (
              <Badge variant="secondary" className="animate-pulse">
                Processing...
              </Badge>
            )}
            {item.is_public && (
              <span className="inline-block rounded bg-primary px-2 py-1 text-xs font-medium text-primary-foreground">
                PUBLICLY SHARED
              </span>
            )}
          </div>
        ) : null}

        {/* Kicker: the object's source, clickable */}
        {showKicker && (
          <div className={`px-6 ${hero ? 'pt-5' : 'pt-6'}`}>
            <button
              onClick={() => window.open(item.url, '_blank')}
              className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground transition-colors hover:text-violet-600"
              title={item.url}
            >
              {domain}
            </button>
          </div>
        )}

        {/* Title section with clickable link */}
        {item.title && (
          <div className={`mb-3 px-6 ${showKicker ? 'pt-1.5' : 'pt-6'} ${reveals?.title ? 'animate-piece-in' : ''}`}>
            {!isPublicView ? (
              <Tooltip>
                <TooltipTrigger asChild>
                  <button
                    onClick={handleTitleClick}
                    disabled={isProcessing}
                    className={`text-left w-full group/title ${isProcessing ? 'cursor-not-allowed opacity-60' : ''}`}
                  >
                    <h3 className={`text-xl font-editorial leading-tight line-clamp-2 ${!isProcessing ? 'group-hover/title:underline transition-all duration-200 cursor-pointer' : ''}`}>
                      {item.title}
                    </h3>
                  </button>
                </TooltipTrigger>
                <TooltipContent>
                  <p className="max-w-xs break-words">
                    {isProcessing ? 'Please wait while content is being extracted' : `Click to edit: ${item.title}`}
                  </p>
                </TooltipContent>
              </Tooltip>
            ) : (
              <button
                onClick={handleTitleClick}
                className={`text-left w-full group/title ${
                  item.type === 'link' && item.url ? 'cursor-pointer' : 'cursor-default'
                }`}
                disabled={!(item.type === 'link' && item.url)}
              >
                <h3 className={`text-xl font-editorial leading-tight line-clamp-2 ${
                  item.type === 'link' && item.url ? 'group-hover/title:underline transition-all duration-200 text-blue-600' : ''
                }`}>
                  {item.title}
                </h3>
              </button>
            )}
          </div>
        )}
      </div>
    </TooltipProvider>
  );
};

export default ContentItemHeader;
