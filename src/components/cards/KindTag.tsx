import React, { useEffect, useRef, useState } from 'react';
import { Spinner, Tag } from '@/components/machine/Machine';
import { useDecrypt } from '@/components/machine/useDecrypt';
import { cn } from '@/lib/utils';

export type KindTagPhase = 'reading' | 'done' | 'gave-up' | 'idle';

/** `✓ all done!` holds this long before the kind decrypts in */
export const ALL_DONE_MS = 900;
/** `some info unavailable` is worth reading; it holds longer */
export const GAVE_UP_MS = 1800;
/** The kind shows this long after a reading, then fades like every other card's */
export const KIND_HOLD_MS = 1400;

type Stage =
  | { name: 'reading' }
  | { name: 'closing'; text: string; tone: 'done' | 'idle' }
  | { name: 'revealing' }
  | { name: 'settled' };

/**
 * The kind tag (DESIGN-v2 §12.3, §12.4): the object's kind, top-left on its hero. While Stash
 * reads the save the tag is the machine's status instead (`| gathering more info…`); when the
 * reading ends it says `✓ all done!` (or `some info unavailable`), decrypts into the kind,
 * holds a moment and fades. At rest every card's kind tag is hidden until the card is hovered
 * or focused (and always shown where there is no pointer to hover with). Will, 2026-10-09.
 */
const KindTag = ({
  kind,
  phase = 'idle',
  busyLabel = 'gathering more info',
  className,
}: {
  kind: string;
  phase?: KindTagPhase;
  busyLabel?: string;
  className?: string;
}) => {
  const [stage, setStage] = useState<Stage>(() => (phase === 'reading' ? { name: 'reading' } : { name: 'settled' }));
  const previousPhase = useRef(phase);

  // Only a reading that ends plays the closing sequence; a card born finished is simply settled
  useEffect(() => {
    const was = previousPhase.current;
    previousPhase.current = phase;
    if (phase === 'reading') {
      setStage({ name: 'reading' });
      return;
    }
    if (was !== 'reading') return;
    if (phase === 'done') setStage({ name: 'closing', text: 'all done!', tone: 'done' });
    else if (phase === 'gave-up') setStage({ name: 'closing', text: 'some info unavailable', tone: 'idle' });
    else setStage({ name: 'revealing' });
  }, [phase]);

  useEffect(() => {
    if (stage.name === 'closing') {
      const timer = window.setTimeout(() => setStage({ name: 'revealing' }), stage.tone === 'done' ? ALL_DONE_MS : GAVE_UP_MS);
      return () => window.clearTimeout(timer);
    }
    if (stage.name === 'revealing') {
      const timer = window.setTimeout(() => setStage({ name: 'settled' }), KIND_HOLD_MS);
      return () => window.clearTimeout(timer);
    }
    return undefined;
  }, [stage]);

  const { display } = useDecrypt(kind, stage.name === 'revealing');
  const live = stage.name === 'reading' || stage.name === 'closing';

  return (
    <Tag
      role={live ? 'status' : undefined}
      aria-live={live ? 'polite' : undefined}
      data-stage={stage.name}
      className={cn(
        'transition-opacity duration-300 ease-v2 motion-reduce:transition-none',
        stage.name === 'settled' &&
          'opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 [@media(hover:none)]:opacity-100',
        className,
      )}
    >
      {stage.name === 'reading' && (
        <>
          <Spinner />
          <span>{busyLabel}…</span>
        </>
      )}
      {stage.name === 'closing' && (
        <>
          {stage.tone === 'done' && <span aria-hidden>✓</span>}
          <span>{stage.text}</span>
        </>
      )}
      {(stage.name === 'revealing' || stage.name === 'settled') && <span>{display}</span>}
    </Tag>
  );
};

export default KindTag;
