// 'masonry' keeps the previous top-to-bottom columns; 'aligned' restores
// the original equal-height grid and serif titles.
export const LIBRARY_PRESENTATION: 'masonry-rows' | 'masonry' | 'aligned' = 'masonry-rows';

export function libraryLayoutClass(compact = false, presentation = LIBRARY_PRESENTATION): string {
  if (presentation === 'aligned') {
    return `grid grid-cols-1 md:grid-cols-2 gap-4 ${compact ? '' : 'lg:grid-cols-3'}`;
  }
  if (presentation === 'masonry-rows') {
    return `grid grid-cols-1 md:grid-cols-2 gap-x-6 items-start ${compact ? '' : 'lg:grid-cols-3'}`;
  }
  // Match the approved preview: natural card heights, 24px gutters, and
  // one uninterrupted card per column fragment. Source/ranking order stays
  // unchanged; CSS columns read top-to-bottom, then left-to-right.
  return `columns-1 md:columns-2 gap-6 [&>*]:mb-6 [&>*]:break-inside-avoid [&>*]:h-auto ${compact ? '' : 'lg:columns-3'}`;
}

export function libraryTitleClass(presentation = LIBRARY_PRESENTATION): string {
  return presentation === 'aligned'
    ? 'font-editorial'
    : 'font-montreal font-medium tracking-[-0.014em]';
}
