import React from 'react';
import { StatusLine, Tag } from '@/components/machine/Machine';
import { PixelMosaic } from '@/components/machine/PixelMosaic';

interface ContentItemSkeletonProps {
  showProgress?: boolean;
  title?: string;
  description?: string;
  type?: string;
  fileSize?: number;
}

const KIND: Record<string, string> = {
  audio: 'voice note',
  video: 'video',
  image: 'photo',
  document: 'document',
  link: 'link',
  text: 'note',
  collection: 'multi-part',
};

const formatFileSize = (bytes?: number) => {
  if (!bytes) return '';
  const mb = bytes / (1024 * 1024);
  return mb > 1 ? `${mb.toFixed(1)} mb` : `${(bytes / 1024).toFixed(0)} kb`;
};

/**
 * A save on its way in (the optimistic card, shown until the row exists): the card in its
 * DESIGN-v2 "reading" state. The media is a shimmering pixel mosaic (a picture not yet
 * resolved), the machine line says
 * the one thing that's true right now (`| saving…`), and dotted lines hold the description's
 * place. No rotating messages: they claimed steps the client can't see.
 */
const ContentItemSkeleton = ({ title, type = 'text', fileSize }: ContentItemSkeletonProps) => {
  // The optimistic handler fills in "Processing …" when it has no real title; that's not a title
  const realTitle = title && !/^processing\b/i.test(title) ? title : '';
  const hasMedia = type !== 'text' && type !== 'collection';
  const size = formatFileSize(fileSize);

  return (
    <div aria-busy className="v2-arrive flex h-full flex-col rounded-object border border-line bg-white shadow-object">
      {hasMedia && (
        <div className="relative h-40 overflow-hidden rounded-t-[1px] border-b border-line bg-fill">
          <PixelMosaic />
          <Tag className="absolute left-2.5 top-2.5 z-[4]">{KIND[type] ?? type}</Tag>
        </div>
      )}
      <div className="flex flex-1 flex-col px-5 pb-3.5 pt-4">
        {realTitle ? (
          <>
            <h3 className="line-clamp-2 text-object-title font-medium text-ink">{realTitle}</h3>
            <div className="mt-1.5">
              <StatusLine tone="busy">saving…</StatusLine>
            </div>
          </>
        ) : (
          <StatusLine tone="busy">saving…</StatusLine>
        )}
        <div aria-hidden className="mt-3 space-y-0.5 overflow-hidden whitespace-nowrap font-pixel text-pixel tracking-[0.05em] text-[#b9bdb5]">
          <span className="block">··································</span>
          <span className="block">·······················</span>
        </div>
        <div className="mt-auto flex items-center justify-between border-t border-line-soft pt-3 font-pixel text-pixel text-muted-foreground">
          <span>{hasMedia ? size || KIND[type] : 'note'}</span>
          <span>just now</span>
        </div>
      </div>
    </div>
  );
};

export default ContentItemSkeleton;
