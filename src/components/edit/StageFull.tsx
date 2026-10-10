import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { Maximize2, Minimize2 } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

/**
 * A media stage can be made **full size**: the panel goes as wide as the browser and the stage
 * fills it; Esc or minimize returns. DESIGN-v2 §12.8; Will, 2026-10-10: "media items in the
 * detail panel should be able to be made full browser height/width" (the browser's own
 * fullscreen cell was dropped the same day: players carry their own).
 *
 * Inside the item panel a provider shares the full-size flag so the sheet can widen; the stage
 * then sits `absolute inset-0` over the sheet. Without a provider (the shared page) the stage
 * sits `fixed inset-0` over the page.
 */
interface StageFullState {
  full: boolean;
  setFull: (full: boolean) => void;
  position: 'absolute' | 'fixed';
}

const StageFullContext = createContext<StageFullState | null>(null);

export const StageFullProvider = ({ children, onChange }: { children: React.ReactNode; onChange?: (full: boolean) => void }) => {
  const [full, setFullState] = useState(false);
  const setFull = useCallback(
    (next: boolean) => {
      setFullState(next);
      onChange?.(next);
    },
    [onChange],
  );
  const value = useMemo<StageFullState>(() => ({ full, setFull, position: 'absolute' }), [full, setFull]);
  return <StageFullContext.Provider value={value}>{children}</StageFullContext.Provider>;
};

export const useStageFull = (): StageFullState => {
  const shared = useContext(StageFullContext);
  const [local, setLocal] = useState(false);
  const localState = useMemo<StageFullState>(() => ({ full: local, setFull: setLocal, position: 'fixed' }), [local]);
  return shared ?? localState;
};

/** Esc leaves full size, caught before the sheet can close on it (window capture, like MaximizedSource) */
const useEscape = (active: boolean, onEscape: () => void) => {
  useEffect(() => {
    if (!active) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.stopPropagation();
      event.preventDefault();
      onEscape();
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [active, onEscape]);
};

const cell =
  'grid h-9 w-9 place-items-center border border-ink bg-white text-ink transition-colors hover:bg-ink hover:text-white focus-visible:bg-ink focus-visible:text-white focus-visible:outline-none';

/**
 * The full-size cell on a stage (top-right, visible on hover like the picture's own controls)
 * and the logic behind it. Full size shows the bar's minimize only.
 */
export const useStage = (stageRef: React.RefObject<HTMLElement>, title: string) => {
  const { full, setFull, position } = useStageFull();
  const leaveFull = useCallback(() => setFull(false), [setFull]);
  useEscape(full, leaveFull);

  // Leaving the stage (another item, the sheet closing) leaves full size too
  useEffect(() => () => setFull(false), [setFull]);

  // Full size has one way back, in the bar; the hover cell goes (two minimize controls sat
  // side by side, Will 2026-10-10: "we only need one")
  const controls = full ? null : (
    <div
      key="controls"
      className="absolute right-3 top-3 z-[5] flex gap-1.5 opacity-0 transition-opacity group-hover/stage:opacity-100 group-focus-within/stage:opacity-100 [@media(hover:none)]:opacity-100"
    >
      <Tooltip>
        <TooltipTrigger asChild>
          <button type="button" onClick={() => setFull(true)} aria-label="Full size" className={cell}>
            <Maximize2 className="h-4 w-4" />
          </button>
        </TooltipTrigger>
        <TooltipContent side="bottom">full size</TooltipContent>
      </Tooltip>
    </div>
  );

  const bar = full ? (
    <div key="bar" className="flex h-11 flex-none items-center justify-between bg-ink pl-6 pr-11 text-white">
      <h2 className="truncate font-pixel text-pixel leading-none">{title}</h2>
      <button
        type="button"
        onClick={leaveFull}
        aria-label="Minimize"
        className="grid h-8 w-8 flex-none place-items-center text-white transition-colors hover:bg-white hover:text-ink"
      >
        {/* The mirror of the full-size cell's Maximize2: two arrows pointing inward */}
        <Minimize2 className="h-4 w-4" />
      </button>
    </div>
  ) : null;

  /** The stage root's classes: the dotted stage at rest; the whole sheet or page when full */
  const rootClass = full ? `${position} inset-0 z-20 flex flex-col bg-background group/stage` : 'group/stage v2-dots relative mx-2.5 mt-8';

  return { full, controls, bar, rootClass, leaveFull };
};

/** Keeps a stage's element identity stable while its wrappers change: keyed children only */
export const StageRoot = React.forwardRef<HTMLDivElement, { className: string; children: React.ReactNode; 'data-testid'?: string; 'data-kind'?: string }>(
  ({ className, children, ...rest }, ref) => (
    <div ref={ref} className={className} {...rest}>
      {children}
    </div>
  ),
);
StageRoot.displayName = 'StageRoot';

export const useStageRef = () => useRef<HTMLDivElement>(null);
