import React, { useEffect, useMemo, useState } from 'react';

/**
 * Post-login loading interstitial: the wordmark's stitched second-S filled
 * with a drifting splash gradient, over cycling playful copy. Replaces the
 * old grey spinner + "Loading..." pair. Honors prefers-reduced-motion (static
 * gradient, single message).
 */

const MESSAGES = [
  'Unpacking your stash…',
  'Dusting off the good stuff…',
  'Rehanging the gallery…',
  'Pulling threads together…',
  'Finding where you left off…',
  'Warming up the library…',
];

/** The wordmark's second S (viewBox x≈587–726) — same glyph as the app icon */
const StitchedS = ({ animate }: { animate: boolean }) => (
  <svg viewBox="587 419 143 186" className="h-16 w-auto" role="img" aria-label="Loading">
    <defs>
      <linearGradient id="loading-s-grad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor="#667eea" />
        <stop offset="35%" stopColor="#764ba2" />
        <stop offset="65%" stopColor="#9d5fd8" />
        <stop offset="100%" stopColor="#c2418f" />
        {animate && (
          <animateTransform
            attributeName="gradientTransform"
            type="rotate"
            values="0 0.5 0.5; 360 0.5 0.5"
            dur="6s"
            repeatCount="indefinite"
          />
        )}
      </linearGradient>
    </defs>
    <g fill="url(#loading-s-grad)">
      <path d="M662.882 436.064C660.343 432.928 652.745 424.888 648.723 425.218C631.503 426.662 614.854 432.253 603.262 445.753C587.108 464.564 587.541 499.498 607.725 515.435C615.558 521.669 623.683 525.093 633.184 527.935L634.778 523.356C639.443 510.591 644.431 500.28 652.078 488.924C644.276 486.269 634.138 482.096 638.038 471.185C641.257 462.176 655.336 460.522 662.77 464.389C666.655 466.247 668.705 468.967 670.798 472.548C672.22 459.272 671.626 446.857 662.882 436.064Z" />
      <path d="M701.56 506.142C694.717 501.845 686.051 496.885 678.015 495.281C673.407 508.547 667.021 522.648 659.27 534.412C664.95 536.676 667.754 537.589 671.562 542.6C675.651 562.928 651.251 565.37 638.727 554.86C638.034 568.698 639.823 579.499 649.517 590.156C652.59 593.542 656.178 596.422 660.149 598.688C664.733 598.313 669.741 597.863 674.224 596.763C705.395 589.088 725.754 563.456 717.527 530.886C716.39 526.275 714.58 521.857 712.154 517.775C703.796 517.693 695.437 517.714 687.079 517.837L687.093 506.374C691.914 506.247 696.737 506.17 701.56 506.142Z" />
    </g>
  </svg>
);

const LoadingInterstitial = () => {
  const reducedMotion = useMemo(
    () =>
      typeof window.matchMedia === 'function' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches,
    []
  );
  // Start somewhere different each time so repeat visitors see variety
  const [index, setIndex] = useState(() => Math.floor(Math.random() * MESSAGES.length));
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    if (reducedMotion) return;
    const cycle = setInterval(() => {
      setVisible(false);
      setTimeout(() => {
        setIndex(i => (i + 1) % MESSAGES.length);
        setVisible(true);
      }, 220);
    }, 1600);
    return () => clearInterval(cycle);
  }, [reducedMotion]);

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#f7f7f9] font-montreal">
      <div className="animated-gradient pointer-events-none absolute inset-0 opacity-20" />
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-transparent via-[#f7f7f9]/70 to-[#f7f7f9]" />
      <div className="relative z-10 flex flex-col items-center">
        <div className={reducedMotion ? '' : 'animate-[loading-breathe_2.6s_ease-in-out_infinite]'}>
          <StitchedS animate={!reducedMotion} />
        </div>
        <p
          aria-live="polite"
          className={`mt-6 text-sm text-[#646b76] transition-opacity duration-200 ${visible ? 'opacity-100' : 'opacity-0'}`}
        >
          {MESSAGES[index]}
        </p>
      </div>
    </div>
  );
};

export default LoadingInterstitial;
