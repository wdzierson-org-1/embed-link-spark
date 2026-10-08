import React, { useEffect, useState } from 'react';
import { CropMarks } from '@/components/machine/Machine';
import { PixelMosaic } from '@/components/machine/PixelMosaic';

/** The stage's height never changes: the image's cap (384 px) plus its padding */
const STAGE_HEIGHT = 'h-[448px]';

/**
 * The item panel's picture (DESIGN-v2 §12.8): an image as an object on the dotted stage with
 * crop marks. The stage is the same height before the picture arrives as after, so nothing
 * under it moves while the picture loads; until it has, the stage shows the mosaic of a picture
 * not yet here. Nothing stores an image's size, so the stage reserves its full height and the
 * picture sits in it at its own shape, up to 384 px tall. A picture that fails to load takes the
 * stage with it.
 */
const EditItemImageStage = ({
  src,
  alt,
  onOpen,
  controls,
}: {
  src: string;
  alt: string;
  onOpen?: () => void;
  /** Hover controls (replace, remove) laid over the picture */
  controls?: React.ReactNode;
}) => {
  const [state, setState] = useState<'loading' | 'loaded' | 'failed'>('loading');

  useEffect(() => {
    setState('loading');
  }, [src]);

  if (state === 'failed') return null;

  return (
    <div className={`v2-dots relative mx-2.5 mt-8 flex ${STAGE_HEIGHT} items-center justify-center px-6 py-8`} data-testid="image-stage">
      <CropMarks />
      {state === 'loading' && (
        <div className="absolute inset-6 overflow-hidden" data-testid="image-stage-mosaic">
          <PixelMosaic />
        </div>
      )}
      <div className="group/image relative flex h-full max-w-full items-center justify-center">
        <img
          src={src}
          alt={alt}
          onLoad={() => setState('loaded')}
          onError={() => setState('failed')}
          onClick={onOpen}
          className={`block max-h-96 max-w-full cursor-pointer rounded-object border border-line bg-white object-contain shadow-object transition-opacity duration-200 hover:opacity-95 ${
            state === 'loaded' ? 'opacity-100' : 'opacity-0'
          }`}
        />
        {state === 'loaded' && controls}
      </div>
    </div>
  );
};

export default EditItemImageStage;
