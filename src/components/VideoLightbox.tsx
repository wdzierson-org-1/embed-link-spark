import React, { useEffect } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';

interface VideoLightboxProps {
  src: string;
  fileName: string;
  isOpen: boolean;
  onClose: () => void;
}

/**
 * A video at full size over the page (used by multi-part attachments). Rendered into
 * document.body: inside a card, the card's hover lift (a transform) would pin this `fixed`
 * overlay to the card and it would flicker between the card and the screen. The close is a white
 * square fixed to the viewport's corner, visible on the dark field; Escape closes too.
 */
const VideoLightbox = ({ src, fileName, isOpen, onClose }: VideoLightboxProps) => {
  useEffect(() => {
    if (!isOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isOpen, onClose]);

  if (!isOpen || typeof document === 'undefined') return null;

  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-label={fileName}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4 sm:p-10"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <button
        type="button"
        onClick={onClose}
        aria-label="Close video"
        autoFocus
        className="fixed right-4 top-4 z-10 grid h-10 w-10 place-items-center bg-white text-ink shadow-[inset_0_0_0_1px_var(--ink)] transition-colors hover:bg-ink hover:text-white hover:shadow-[inset_0_0_0_1px_#fff] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-spot"
      >
        <X className="h-5 w-5" strokeWidth={2.5} />
      </button>
      <figure className="w-full max-w-6xl">
        <video src={src} controls autoPlay playsInline controlsList="nodownload" className="block max-h-[85vh] w-full bg-black object-contain">
          Your browser does not support the video tag.
        </video>
        <figcaption className="mt-2 truncate font-pixel text-pixel text-white/70">{fileName}</figcaption>
      </figure>
    </div>,
    document.body,
  );
};

export default VideoLightbox;
