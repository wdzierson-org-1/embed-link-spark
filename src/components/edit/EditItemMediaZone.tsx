import React from 'react';
import { Download } from 'lucide-react';
import { audioSubtype } from '@/components/cards/CardBits';
import { CropMarks } from '@/components/machine/Machine';
import EditItemPlayerStrip from '@/components/edit/EditItemPlayerStrip';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * The item panel's media zone (DESIGN-v2 §12.8). A recording or voice note gets the player
 * strip (ink play button, waveform, speed). A video is shown as a video: on the dotted stage
 * with crop marks, like a picture, as an object at its own shape (up to 420 px tall) with the
 * native controls, full screen included. Both offer the original to download.
 */

const DownloadOriginal = ({ href }: { href: string }) => (
  <div className="mt-2 flex gap-4">
    <a
      href={href}
      download
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center gap-1.5 font-pixel text-pixel text-muted-foreground underline-offset-2 transition-colors hover:text-ink hover:underline"
    >
      <Download className="h-3 w-3" />
      download original
    </a>
  </div>
);

export const EditItemVideoStage = ({ src, title }: { src: string; title?: string }) => (
  <div className="mt-8">
    <div className="v2-dots relative mx-2.5 flex justify-center px-6 py-8">
      <CropMarks />
      <video
        key={src}
        src={src}
        controls
        preload="metadata"
        playsInline
        aria-label={title ? `Video: ${title}` : 'Video'}
        className="block max-h-[420px] w-full rounded-object border border-line bg-ink object-contain shadow-object"
      >
        Your browser does not support the video tag.
      </video>
    </div>
    <DownloadOriginal href={src} />
  </div>
);

interface MediaItem {
  id: string;
  type?: string;
  attributes?: ItemAttributes;
}

const EditItemMediaZone = ({ item, src, title }: { item: MediaItem; src: string; title?: string }) =>
  item.type === 'video' ? (
    <EditItemVideoStage src={src} title={title} />
  ) : (
    <EditItemPlayerStrip
      src={src}
      itemId={item.id}
      variant={audioSubtype(item.attributes) === 'voice_note' ? 'voice' : 'warm'}
      durationHint={item.attributes?.media?.duration_s}
      downloadUrl={src}
    />
  );

export default EditItemMediaZone;
