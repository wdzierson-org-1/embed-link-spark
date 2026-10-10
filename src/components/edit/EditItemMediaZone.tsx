import React, { useRef } from 'react';
import { Download } from 'lucide-react';
import { audioSubtype } from '@/components/cards/CardBits';
import { CropMarks } from '@/components/machine/Machine';
import EditItemPlayerStrip from '@/components/edit/EditItemPlayerStrip';
import { StageRoot, useStage, useStageRef } from '@/components/edit/StageFull';
import { useMediaElementClock } from '@/components/edit/MediaClock';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * The item panel's media zone (DESIGN-v2 §12.8). A recording or voice note gets the player
 * strip (ink play button, waveform, speed). A video is shown as a video: on the dotted stage
 * with crop marks, like a picture, as an object at its own shape (up to 420 px tall) with the
 * native controls, and the stage's full size / full screen. Both offer the original to download
 * and report their time to the panel's clock (timestamped notes).
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

export const EditItemVideoStage = ({ src, title }: { src: string; title?: string }) => {
  const stageRef = useStageRef();
  const videoRef = useRef<HTMLVideoElement>(null);
  const { full, controls, bar, rootClass } = useStage(stageRef, 'video');
  useMediaElementClock(videoRef);
  return (
    <div>
      <StageRoot ref={stageRef} className={rootClass} data-testid="video-stage">
        {bar}
        {!full && <CropMarks key="marks" />}
        <div key="video" className={full ? 'flex min-h-0 flex-1 items-center justify-center p-6' : 'flex justify-center px-6 py-8'}>
          <video
            ref={videoRef}
            key={src}
            src={src}
            controls
            preload="metadata"
            playsInline
            aria-label={title ? `Video: ${title}` : 'Video'}
            className={`block rounded-object border border-line bg-ink object-contain shadow-object ${full ? 'max-h-full max-w-full' : 'max-h-[420px] w-full'}`}
          >
            Your browser does not support the video tag.
          </video>
        </div>
        {controls}
      </StageRoot>
      <DownloadOriginal href={src} />
    </div>
  );
};

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
