# Before masonry — September 13, 2026

These source snapshots preserve the local UI immediately before the masonry/typeface/shorter-notes change, including the earlier inline-note and enrichment work. They are reference copies, not application source.

To restore the previous **aligned grid and serif card titles**, change `LIBRARY_PRESENTATION` in `src/utils/libraryPresentation.ts` from `'masonry'` to `'aligned'`. This restores the previous 16px grid gutters, equal-height rows, and PP Editorial New card titles without removing the other housekeeping changes.

The approved masonry variant uses natural card heights, 24px gutters, PP Neue Montreal medium 20px titles with -0.014em tracking, and the existing 1/2/3 column breakpoints (compact views cap at two columns). CSS columns flow down, then across; search relevance and reminder ordering in the source array are unchanged.

The note-editor height is independent of this switch. To restore its previous size, use the saved editor/section files as a reference: normal editor height 300px, inner minimum 270px, loading minimum 300px, and the former mobile section minimum 400px. Prefer a targeted height change over replacing entire files after further development.

## Left-to-right masonry refinement

The current default is now `'masonry-rows'`: fixed left-to-right assignment, with each column packed independently. Set the same presentation constant to `'masonry'` to restore the first top-to-bottom masonry trial, or `'aligned'` for the original grid and serif titles. All three variants remain in the source.
