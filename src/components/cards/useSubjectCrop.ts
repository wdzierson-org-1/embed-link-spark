import { useRef, useState } from 'react';
import { analyzeImageElement, coverObjectPosition } from '@/utils/heroFocal';

/**
 * Subject-aware `object-position` for a cover-cropped hero image. Attach
 * `frameRef` to the crop box, `onLoad` to the `<img>` (loaded with
 * `crossOrigin="anonymous"`), and spread `style` onto it. Until the image has
 * loaded — or when its pixels are unreadable — the crop stays at the centre.
 */
export const useSubjectCrop = () => {
  const frameRef = useRef<HTMLDivElement>(null);
  const [objectPosition, setObjectPosition] = useState<string | undefined>(undefined);

  const onLoad = (event: React.SyntheticEvent<HTMLImageElement>) => {
    const img = event.currentTarget;
    const analysis = analyzeImageElement(img);
    if (!analysis || !analysis.bounds) return;
    const frame = frameRef.current;
    const frameW = frame?.clientWidth || img.clientWidth;
    const frameH = frame?.clientHeight || img.clientHeight;
    const pos = coverObjectPosition(analysis.focal, img.naturalWidth, img.naturalHeight, frameW, frameH);
    setObjectPosition(`${pos.x.toFixed(1)}% ${pos.y.toFixed(1)}%`);
  };

  return { frameRef, onLoad, style: objectPosition ? { objectPosition } : undefined };
};
