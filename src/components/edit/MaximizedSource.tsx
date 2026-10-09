import React, { useEffect } from 'react';
import { Minimize } from 'lucide-react';

/**
 * The source, full size (DESIGN-v2 §12.8): the summary, original content or transcript fills
 * the panel in the same window chrome the notes' maximize uses: an ink bar naming the tab, a
 * minimize control, a reading column. Esc returns.
 */
const MaximizedSource = ({
  title,
  onMinimize,
  children,
}: {
  title: string;
  onMinimize: () => void;
  children: React.ReactNode;
}) => {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      // A field being edited inside (the summary) takes Esc first: it abandons its edit, not the view
      if ((event.target as HTMLElement | null)?.closest?.('textarea, input')) return;
      event.stopPropagation();
      onMinimize();
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onMinimize]);

  return (
    <div className="absolute inset-0 z-10 flex flex-col bg-background" role="region" aria-label={`${title}, full size`}>
      <div className="flex h-11 flex-none items-center justify-between bg-ink pl-6 pr-11 text-white">
        <h2 className="font-pixel text-pixel leading-none">{title}</h2>
        <button
          type="button"
          onClick={onMinimize}
          aria-label="Minimize"
          className="grid h-8 w-8 place-items-center text-white transition-colors hover:bg-white hover:text-ink"
        >
          <Minimize className="h-4 w-4" />
        </button>
      </div>
      <div className="flex-1 overflow-y-auto px-6 py-6">
        <div className="mx-auto max-w-3xl">{children}</div>
      </div>
    </div>
  );
};

export default MaximizedSource;
