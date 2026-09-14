# Card and detail housekeeping — September 13, 2026

## Implemented on the web

- Card type chips appear beside the date on hover or keyboard focus. Touch browsers keep the affordances visible.
- Card menus no longer contain Download, Open link, Edit, or Delete; remaining reminder, reporting, and public-feed controls are retained.
- “Add a note” occupies the old chip area. Existing notes have a light grey hover surface and a five-line ellipsis. Clicking opens a compact rich-document editor: Enter saves; Ctrl+Enter (also Cmd+Enter/Shift+Enter) inserts a hard break; Escape cancels. Save/Cancel buttons support touch. Failed saves retain the draft and show an error.
- Card edits patch `items.content`, the same TipTap document used by the detail editor. Formatting and embedded nodes survive editing. `supplemental_note` remains the separate legacy public sticky note.
- Notes are a standalone section above Summary/Original Content or Transcript, with the existing formatting editor and maximize action.
- Pending enrichment dims card contents to 50% while the upper-left status stays readable. Metadata arriving early does not finish the card; source extraction completes first. A failed/interrupted lookup becomes “Some information unavailable,” restores readability, and never claims success.
- Explicit status is `attributes.enrichment = { status: pending | complete | partial, updated_at: ISO timestamp }`. The RPC merges this key atomically without replacing other attributes. Pending workers time out in the UI after ten minutes. Legacy rows retain the bounded field-based indicator without inventing retrospective failure badges.
- Status is wired through server `add-url`/`add-file` and web link/image/document capture, including full PDF and Office extraction.
- `transcribe-audio` now uses `gpt-4o-transcribe-diarize`, `diarized_json`, and automatic chunking. Speaker turns and timestamps are stored as Markdown in `page_body`, so both clients render them. Labels describe detected voices, not inferred identities.
- The web transcript section has “Transcribe with speakers” to rebuild an existing recording (including Sally's) from its saved media. It preserves the old transcript on failure and never changes notes. Sally's existing recording was not reprocessed during development; no production recording was accessed.

## Implemented in native iOS

- Notes always appear above source tabs; the existing `NotesEditor` and formatting-preservation behavior are reused.
- Type chips moved from the card body to beside the date, remaining visible because touch has no hover.
- Text/annotation previews clamp to five lines.
- Pending and partial enrichment display the same status and dimming; timestamps retire interrupted workers. The unknown attribute remains losslessly preserved by `ItemAttributes.extra`.
- New speaker-formatted transcripts render through the existing Markdown source view.

## Follow-up for the mobile agent

1. Add an explicit “Add a note” affordance on empty card notes and make existing card notes editable on tap. Integrate with `NotesEditorModel`, the item store's patch/merge flow, and draft recovery; do not flatten rich `content` into plain text. A compact editor sheet is a sensible touch adaptation. Save/Cancel should be explicit; native Return adds a line. Keep five-line truncation outside editing. Check whole-card tap gesture precedence and VoiceOver.
2. Add “Transcribe with speakers” in native `ItemDetailContent`, mirroring `src/components/TranscriptContent.tsx`: call the shared endpoint with the stored media URL, patch only `page_body` and `description`, then refresh search embeddings and the item store. Preserve the previous source on failure. Do not modify `content` or claim actual speaker names.
3. Verify the new source layout with the keyboard open, long rich notes, and Dynamic Type on device. The existing UI-test expectations were updated for standalone Notes; run those flows on device before shipping.

## Rollout and verification

Apply `supabase/migrations/20260913120000_item_enrichment_state.sql` before deploying the web app and updated `add-url`, `add-file`, and `transcribe-audio` functions. The RPC is security-invoker and restricted to the item's owner or service role; ordinary RLS still applies. The initial implementation was local; production rollout is recorded below.

OpenAI documentation: https://developers.openai.com/api/docs/guides/speech-to-text

The model's existing upload-size limit still applies; this change does not add client-side compression or chunking for oversized recordings. Speaker quality needs evaluation against the original audio after deployment.

Validation: web build and TypeScript check; automated card keyboard/save/failure tests, source-section layout, enrichment lifecycle, and speaker formatting; full web suite; StashKit tests; unsigned iOS simulator build. Browser smoke check used the dev-only `/design/cards` fixtures without writing production data.

## Latest review: masonry, typography, and compact Notes

The user approved the masonry layout from `/design/cards`, its PP Neue Montreal card headings, and the “Gathering more information…” treatment. The main local web app now uses that presentation: natural-height cards, 24px gutters, one/two/three columns, and Montreal medium 20px headings with -0.014em tracking. Compact views stop at two columns. CSS columns read down and then across; existing search/reminder ranking is retained in DOM order.

The earlier aligned grid and PP Editorial New card headings remain selectable through `LIBRARY_PRESENTATION = 'aligned'` in `src/utils/libraryPresentation.ts`. Exact pre-change source copies and rollback instructions are saved in `docs/ui-snapshots/2026-09-13-before-masonry/`. This first review used `'masonry'`; the final default and production rollout are recorded below.

The web detail Notes editor is now 150px high (previously 300px); the inner editable minimum is 120px. Loading placeholders match the reduced height and the old mobile 400px spacer is removed. The formatting hint sits below the editor; full formatting, autosave, scrolling, and maximize remain available.

Native follow-up: adopt Montreal medium card headings; use natural-height cards and roughly 24pt gutters. A phone's single-column library needs no masonry redistribution; consider masonry on multi-column iPad layouts, preserving a coherent reading/VoiceOver order and stable focus during enrichment. Keep the current native layout available until the user accepts the device result. Reduce the default Notes editing footprint to approximately half its current height, while allowing scrolling, keyboard visibility, and Dynamic Type expansion. These latest native layout/height changes are documented here for the mobile agent and are not yet applied to SwiftUI.

Also remove any equivalent recurring paste/drop tutorial banner in the native app if present. The web's “Paste a link anywhere…” login hint was removed in the preceding review.

### Latest refinement: recency across masonry columns

The default is now `LIBRARY_PRESENTATION = 'masonry-rows'`. Cards are assigned left to right in fixed groups: at three columns, indices 0/1/2 form the first group, 3/4/5 the next. Each column packs independently, so later groups have uneven vertical starting positions. This is deliberately not a shortest-column algorithm: position within a group communicates recency (or the active search/reminder ranking).

`LibraryLayout.tsx` measures natural card heights with ResizeObserver and places wrappers in a one-pixel CSS grid. DOM order stays identical to ranked item order; resizing, image loads, note editing, and enrichment reposition existing nodes without moving editors between column parents. Gaps remain 24px. One/two/three-column breakpoints and compact two-column mode are unchanged.

Native multi-column adaptation should use the same fixed index-modulo-column assignment, not shortest-column placement. Keep logical accessibility order and active editor identity stable during reflow. Phone single-column ordering stays unchanged.

Rollback options remain in `src/utils/libraryPresentation.ts`: `'masonry'` restores the previous top-to-bottom masonry; `'aligned'` restores the original grid/serif presentation. Montreal headings, the 150px Notes editor, and the enrichment treatment remain in the new default.

### Card note interaction polish

The card editor now uses the detail fields' pale violet surface and soft lavender focus ring, with no dark border. Visible keyboard instructions are removed; only Save and Cancel remain. Enter still saves; modifier+Enter still inserts a line. Leaving the whole editor region saves changed content (matching detail fields); moving focus between the editor and its buttons does not save prematurely. Cancel and Escape discard the edit. An unchanged blur simply closes the editor.

After a confirmed successful save, a 450ms lavender wash settles over the note and a small checkmark/“Saved” confirmation appears briefly. Failure retains the draft and shows an error instead of success feedback. Reduced-motion users get a static confirmation. The overlays do not affect masonry geometry.

Existing notes now have a straight, square-ended violet rule along their left edge, matching the user's reference image; only the right corners of the hover surface are rounded. Carry this treatment into the native card-note work. Native saves should use the same brief, accessible success acknowledgment without adding keyboard instructions to the touch UI.

## Production release — September 13, 2026

- Implementation commit: `cfdc4a18`, pushed to `main`.
- Applied `20260913120000_item_enrichment_state.sql` through the authenticated Supabase CLI. The dry run showed this migration alone. Historical remote migrations were fetched into a temporary release directory because this checkout has older migration-history gaps; no historical migration records were repaired or replayed.
- Deployed and verified ACTIVE: `add-url` version 68, `add-file` version 15, `transcribe-audio` version 27. Existing JWT verification settings were preserved (true, true, false respectively).
- Vercel production deployment `dpl_BFywBGZqD584TgTnoJMWkDxNLPU9` is Ready and aliased to `https://www.gostash.it`. The final layout is `masonry-rows`.
- Release validation: all 363 web tests passed; TypeScript, focused lint, and production build passed. Production `/home` returns HTTP 200, and the served bundle contains the new note editor, saved animation, enrichment treatment, and speaker transcription action.
- Native source changes and follow-up instructions are checked in. No new TestFlight build was released in this step. Existing recordings were not reprocessed.
