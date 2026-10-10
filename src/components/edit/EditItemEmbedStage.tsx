import React, { useEffect, useRef } from 'react';
import { CropMarks } from '@/components/machine/Machine';
import { StageRoot, useStage, useStageRef } from '@/components/edit/StageFull';
import { useMediaClock } from '@/components/edit/MediaClock';
import type { Embed } from '@/utils/embeds';

const YOUTUBE_ORIGIN = 'https://www.youtube-nocookie.com';

/**
 * YouTube's player talks over postMessage once asked to: it then reports `currentTime` as it
 * plays, and takes `seekTo`. That is enough for `+ note at 1:42` and `[1:42]` seeks.
 */
const useYouTubeClock = (iframeRef: React.RefObject<HTMLIFrameElement>, enabled: boolean) => {
  const { report, registerSeek } = useMediaClock();
  useEffect(() => {
    if (!enabled) return;
    const post = (message: Record<string, unknown>) => iframeRef.current?.contentWindow?.postMessage(JSON.stringify(message), YOUTUBE_ORIGIN);
    const listen = () => post({ event: 'listening', id: 'stash', channel: 'widget' });
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== YOUTUBE_ORIGIN || event.source !== iframeRef.current?.contentWindow) return;
      let data: { event?: string; info?: { currentTime?: number } } | null = null;
      try {
        data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
      } catch {
        return;
      }
      if (data?.event === 'onReady') listen();
      const time = data?.info?.currentTime;
      if (typeof time === 'number' && Number.isFinite(time)) report(time);
    };
    window.addEventListener('message', onMessage);
    const iframe = iframeRef.current;
    iframe?.addEventListener('load', listen);
    const retry = window.setTimeout(listen, 1500);
    registerSeek((seconds) => {
      post({ event: 'command', func: 'seekTo', args: [seconds, true] });
      post({ event: 'command', func: 'playVideo', args: [] });
    });
    return () => {
      window.removeEventListener('message', onMessage);
      iframe?.removeEventListener('load', listen);
      window.clearTimeout(retry);
      registerSeek(null);
      report(null);
    };
  }, [enabled, iframeRef, report, registerSeek]);
};

/**
 * The item panel's embed stage (DESIGN-v2 §12.8): a link's own player — YouTube, Vimeo, Loom,
 * TikTok, Instagram, Google Slides, Figma — on the dotted stage with crop marks, in place of
 * its picture. Landscape players take the stage's width; phone-shaped ones sit centred at phone
 * width. Full size and full screen like every stage. Will, 2026-10-10.
 */
const EditItemEmbedStage = ({ embed, title }: { embed: Embed; title?: string }) => {
  const stageRef = useStageRef();
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const { full, controls, bar, rootClass } = useStage(stageRef, embed.label.toLowerCase());
  useYouTubeClock(iframeRef, embed.clock === 'youtube');

  const src =
    embed.clock === 'youtube' && typeof window !== 'undefined'
      ? `${embed.src}&origin=${encodeURIComponent(window.location.origin)}`
      : embed.src;
  const frameStyle: React.CSSProperties = full
    ? embed.portrait
      ? { height: '100%', aspectRatio: String(embed.aspect) }
      : { width: '100%', height: '100%' }
    : embed.portrait
      ? { width: 340, height: 604 }
      : { width: '100%', aspectRatio: String(embed.aspect) };

  return (
    <StageRoot ref={stageRef} className={rootClass} data-testid="embed-stage">
      {bar}
      {!full && <CropMarks key="marks" />}
      <div key="frame" className={full ? 'flex min-h-0 flex-1 items-center justify-center p-6' : 'flex justify-center px-6 py-8'}>
        <iframe
          ref={iframeRef}
          src={src}
          title={title ? `${embed.label}: ${title}` : embed.label}
          style={frameStyle}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen"
          allowFullScreen
          referrerPolicy="strict-origin-when-cross-origin"
          loading="lazy"
          className="block max-w-full rounded-object border border-line bg-ink shadow-object"
          data-provider={embed.provider}
        />
      </div>
      {controls}
    </StageRoot>
  );
};

export default EditItemEmbedStage;
