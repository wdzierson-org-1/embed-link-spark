import React, { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { FileText, Image as ImageIcon, Link2, Music, Video as VideoIcon } from 'lucide-react';
import ImageLightbox from '@/components/ImageLightbox';
import type { Attachment } from '@/components/CollectionAttachments';

const MAX_TILES = 4;

const getFileUrl = (filePath: string): string =>
  supabase.storage.from('stash-media').getPublicUrl(filePath).data.publicUrl;

const domainOf = (url?: string): string => {
  if (!url) return '';
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
};

interface StripProps {
  itemId: string;
  /** Prefetched by ContentGrid; when absent the strip fetches its own */
  attachments?: Attachment[];
}

/**
 * The card-level view of what a multi-part stash item contains: real
 * thumbnails for images, preview/domain tiles for links, icon tiles for other
 * files — instead of a text inventory. Shows up to four tiles plus a "+N".
 */
const CollectionAttachmentStrip = ({ itemId, attachments }: StripProps) => {
  const [fetched, setFetched] = useState<Attachment[] | null>(null);
  const [lightbox, setLightbox] = useState<{ src: string; title: string } | null>(null);

  useEffect(() => {
    if (attachments) return;
    let cancelled = false;
    supabase
      .from('item_attachments')
      .select('*')
      .eq('item_id', itemId)
      .order('created_at', { ascending: true })
      .then(({ data, error }) => {
        if (!cancelled && !error) setFetched(data ?? []);
      });
    return () => {
      cancelled = true;
    };
  }, [itemId, attachments]);

  const list = attachments ?? fetched ?? [];
  if (list.length === 0) return null;

  const shown = list.slice(0, MAX_TILES);
  const extraCount = list.length - shown.length;
  // A lone image gets a bigger stage — it's the whole story of the item
  const isSingleImage = list.length === 1 && list[0].type === 'image' && Boolean(list[0].file_path);

  const renderTile = (attachment: Attachment) => {
    if (attachment.type === 'image' && attachment.file_path) {
      return (
        <ImageTile
          key={attachment.id}
          src={getFileUrl(attachment.file_path)}
          title={attachment.title || 'Image'}
          wide={isSingleImage}
          onOpen={(src) => setLightbox({ src, title: attachment.title || 'Image' })}
        />
      );
    }

    if (attachment.type === 'link') {
      const domain = domainOf(attachment.url);
      const ogImage =
        typeof attachment.metadata?.image === 'string' && attachment.metadata.image.startsWith('http')
          ? attachment.metadata.image
          : null;
      return (
        <LinkTile
          key={attachment.id}
          title={attachment.title || attachment.url || 'Link'}
          url={attachment.url}
          domain={domain}
          ogImage={ogImage}
        />
      );
    }

    const Icon = attachment.type === 'audio' ? Music : attachment.type === 'video' ? VideoIcon : FileText;
    return (
      <div
        key={attachment.id}
        title={attachment.title || attachment.type}
        className="flex h-20 w-32 flex-none flex-col justify-between rounded-xl border border-black/5 bg-gray-50/80 p-2 text-left"
      >
        <Icon className="h-4 w-4 text-muted-foreground" />
        <span className="line-clamp-2 text-xs font-medium leading-snug text-foreground/80">
          {attachment.title || attachment.type}
        </span>
      </div>
    );
  };

  return (
    <div className="flex flex-wrap items-stretch gap-2" onClick={(e) => e.stopPropagation()}>
      {shown.map(renderTile)}
      {extraCount > 0 && (
        <div className="grid h-20 w-14 flex-none place-items-center rounded-xl border border-black/5 bg-gray-50/80 text-sm font-medium text-muted-foreground">
          +{extraCount}
        </div>
      )}
      <ImageLightbox
        src={lightbox?.src || ''}
        fileName={lightbox?.title || ''}
        isOpen={Boolean(lightbox)}
        onClose={() => setLightbox(null)}
      />
    </div>
  );
};

interface ImageTileProps {
  src: string;
  title: string;
  wide: boolean;
  onOpen: (src: string) => void;
}

const ImageTile = ({ src, title, wide, onOpen }: ImageTileProps) => {
  const [failed, setFailed] = useState(false);

  // A missing file (deleted from storage) degrades to a labeled icon tile
  // instead of a broken-image glyph
  if (failed) {
    return (
      <div
        title={title}
        className="flex h-20 w-32 flex-none flex-col justify-between rounded-xl border border-black/5 bg-gray-50/80 p-2 text-left"
      >
        <ImageIcon className="h-4 w-4 text-muted-foreground" />
        <span className="line-clamp-2 text-xs font-medium leading-snug text-foreground/60">{title}</span>
      </div>
    );
  }

  return (
    <button
      onClick={() => onOpen(src)}
      title={title}
      className={`${wide ? 'h-28 w-44' : 'h-20 w-20'} flex-none overflow-hidden rounded-xl border border-black/5 bg-gray-100 transition-transform hover:scale-[1.03]`}
    >
      <img
        src={src}
        alt={title}
        onError={() => setFailed(true)}
        className="h-full w-full object-cover"
        loading="lazy"
        decoding="async"
      />
    </button>
  );
};

interface LinkTileProps {
  title: string;
  url?: string;
  domain: string;
  ogImage: string | null;
}

const LinkTile = ({ title, url, domain, ogImage }: LinkTileProps) => {
  const [imageFailed, setImageFailed] = useState(false);
  const open = () => {
    if (url) window.open(url, '_blank');
  };

  if (ogImage && !imageFailed) {
    return (
      <button
        onClick={open}
        title={title}
        className="relative h-20 w-32 flex-none overflow-hidden rounded-xl border border-black/5 bg-gray-100 text-left transition-transform hover:scale-[1.03]"
      >
        <img
          src={ogImage}
          alt=""
          onError={() => setImageFailed(true)}
          className="h-full w-full object-cover"
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
        />
        <span className="absolute inset-x-0 bottom-0 truncate bg-gradient-to-t from-black/70 to-transparent px-2 pb-1 pt-4 text-[10px] font-medium text-white">
          {domain || title}
        </span>
      </button>
    );
  }

  return (
    <button
      onClick={open}
      title={title}
      className="flex h-20 w-32 flex-none flex-col justify-between rounded-xl border border-black/5 bg-gray-50/80 p-2 text-left transition-colors hover:bg-gray-100"
    >
      <span className="flex min-w-0 items-center gap-1">
        <Link2 className="h-3.5 w-3.5 flex-none text-muted-foreground" />
        {domain && <span className="truncate text-[10px] text-muted-foreground">{domain}</span>}
      </span>
      <span className="line-clamp-2 text-xs font-medium leading-snug text-foreground/80">{title}</span>
    </button>
  );
};

export default CollectionAttachmentStrip;
