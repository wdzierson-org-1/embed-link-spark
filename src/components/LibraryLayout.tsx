import React, { useLayoutEffect, useRef } from 'react';
import { LIBRARY_PRESENTATION, libraryLayoutClass } from '@/utils/libraryPresentation';
import { masonryPlacement } from '@/utils/masonryPlacement';

/** Keep cards in source order and in the same DOM nodes while packing their
 * columns. Resizing or enriching a card never reparents an active note editor. */
function RowMasonry({ children, compact }: { children: React.ReactNode; compact: boolean }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let frame: number | undefined;
    const measure = () => {
      const columns = getComputedStyle(container).gridTemplateColumns.trim().split(/\s+/).filter(Boolean).length || 1;
      const cards = Array.from(container.children) as HTMLElement[];
      const placements = masonryPlacement(cards.map(card => card.getBoundingClientRect().height), columns);
      cards.forEach((card, index) => {
        const { column, start, span } = placements[index];
        card.style.gridColumn = String(column);
        card.style.gridRow = `${start} / span ${span}`;
      });
    };
    measure();
    // Image loading, note editing, enrichment, and breakpoint changes all
    // affect geometry. One frame batches their reads/writes without polling.
    if (typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(() => {
      if (frame !== undefined) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => { frame = undefined; measure(); });
    });
    observer.observe(container);
    Array.from(container.children).forEach(card => observer.observe(card));
    return () => {
      observer.disconnect();
      if (frame !== undefined) cancelAnimationFrame(frame);
    };
  }, [children, compact]);

  return (
    <div ref={containerRef} className={libraryLayoutClass(compact)} style={{ gridAutoRows: '1px', rowGap: 0 }}>
      {React.Children.toArray(children).map((child, index) => (
        <div key={React.isValidElement(child) ? child.key ?? index : index} className="flow-root min-w-0 self-start [&>*]:h-auto">
          {child}
        </div>
      ))}
    </div>
  );
}

export default function LibraryLayout({ children, compact = false }: { children: React.ReactNode; compact?: boolean }) {
  return LIBRARY_PRESENTATION === 'masonry-rows'
    ? <RowMasonry compact={compact}>{children}</RowMasonry>
    : <div className={libraryLayoutClass(compact)}>{children}</div>;
}
