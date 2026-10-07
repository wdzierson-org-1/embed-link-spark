import React, { useState } from 'react';
import { St4shSymbol } from '@/components/brand/St4sh';
import { PaperBackdrop } from '@/components/machine/PaperBackdrop';
import { LOADING_LINES, takeLoadingLine, useDecryptCycle } from '@/components/machine/decryptCycle';

/**
 * Loading interstitial for /home (DESIGN-v2 §8, "decrypt"): the library's paper, the Stash
 * symbol, and a terminal line in the code voice that decrypts behind a spot head, holds, and
 * scrambles over to the next. Each load opens one line further on ("opening your stash", "the
 * door creaks open…", "hey, you <3"), so it greets you differently every time. Screen readers
 * hear one plain label; under reduced motion the line is simply there, still.
 */
const LoadingInterstitial = () => {
  const [start] = useState(() => takeLoadingLine());
  const { cells } = useDecryptCycle(LOADING_LINES, start);

  return (
    <div className="relative isolate flex min-h-screen items-center justify-center bg-paper px-6">
      <PaperBackdrop />
      <div role="status" aria-label="Opening your stash" className="w-[34ch] max-w-full font-code text-[15px] leading-[1.6] sm:text-[17px]">
        <St4shSymbol className="mb-5 h-7 w-[27px] text-ink" />
        <p aria-hidden className="whitespace-pre text-ink [font-variant-ligatures:none]">
          <span className="text-ink-muted">&gt; </span>
          {cells.map((cell, index) => (
            <span
              key={index}
              className={cell.head ? 'bg-spot text-spot-on' : cell.settled ? undefined : 'text-ink-muted'}
            >
              {cell.ch}
            </span>
          ))}
          <span className="v2-caret" />
        </p>
      </div>
    </div>
  );
};

export default LoadingInterstitial;
