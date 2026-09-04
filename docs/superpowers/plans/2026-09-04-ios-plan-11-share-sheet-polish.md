# Stash iOS Plan 11: Share-Sheet Polish + Build 5 → Beta Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Will's six share-sheet design notes, then TestFlight build 5 attached to both groups and submitted for Beta App Review (the external "Trusted Testers" flow deliberately waited for this).

**Architecture:** All changes live in `ios/StashShareExtension/ShareComposeView.swift` + one new DESIGN.md token (`success` green — first legitimate need). One implement task, one review, one wrap.

**Spec:** Will 2026-09-04 (verbatim in Global Constraints) + DESIGN.md + the current file anatomy (line refs below from `2b112b5`).

## Global Constraints

- **Will's notes (verbatim):** "remove the gray stroke around the cards; remove the gray stroke from the X button; make the 'add a note' text 'optional note...'; make the 'save' button full size (standard iOS guidance) and pin it to the bottom of the screen; we can probably make the save preview larger (currently it's a thumbnail, but we have the rest of the width of the screen to work with, so why not); make the background color of the 'will save' / 'saved' icon purple / green."
- **Anatomy (current, ShareComposeView.swift):** `hairlineCard()` helper (:596, fill + hairline stroke + soft shadow) used by the note field (:207) and preview cards (:332, :341, :367) → drop the STROKE from the helper, keep fill + shadow (the amber gate strip's `gateBorder` at :281 is intentional — unchanged). X/close circle (:157) → remove the hairline stroke (keep the fill/shadow treatment CircleIcon-style minus the border). Save capsule (:470) → replaced by a full-width pinned button. Placeholder (:202) `"Add a note…"` → `"Optional note…"` (identifier `share.note` unchanged; grep StashUITests for placeholder-text assertions and update in-task if any). Outcome icon (:539-544): "Saved to Stash" checkmark currently on violet600 → **green**; "Saved — will sync" clock currently on `.orange` literal → **violet600**. Identifiers `share.outcome`, `share.save`, `share.cancel`, `share.gate`, `share.note` all preserved.
- **Save button (standard iOS):** full-width (screen minus 20pt margins), 52pt height, `StashRadius.input` (12), `StashColor.violet600` fill, white `StashType.bodyMedium(size: 17)`, pinned to the bottom via `.safeAreaInset(edge: .bottom)` (content scrolls beneath; keyboard pushes it up naturally); disabled state = existing gating (`canAddContent`/empty), rendered at reduced opacity but never hidden. Identifier `share.save` moves onto it.
- **Preview larger:** staged images → full-content-width contained hero, aspect-fit, max height ~45% of the sheet, `StashRadius.card` (16) + `.stashCardShadow()` (mirrors the detail sheet's hero treatment); URL previews → full-width card with a larger favicon (32pt) + title/domain stack; multi-item shares keep a leading full-width hero for the first item + the existing compact row for the rest ("+N" pattern preserved). Memory rule unchanged: render from the STAGED file via thumbnailing APIs — never decode the original whole.
- **NEW token (DESIGN.md §Color, dated):** `success` green — the implementer picks a hex harmonious with the palette (muted, ink-compatible; e.g. the #2f9e63 family), records it in DESIGN.md ("status: success — confirmation icons/labels; web should adopt; iOS `StashColor.success`") and adds `StashColor.success` to StashDesign.swift. Also migrate the ChatBubble "Saved to your stash" `.green` literal (ChatBubble.swift:59) to the token — the only other green in the app (grep to confirm).
- 1px strokes only; tokens only; no emoji. Worktree `.claude/worktrees/ios-plan-11` (base `2b112b5`): commit, never push; audit origin/main at wrap. Sim `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, derivedDataPath DerivedData; StashKit floor 341; UI suite 22 (standing 3 gate-blocked); builds warning-free; max 2 concurrent build agents.
- **Wrap/deploy:** `CURRENT_PROJECT_VERSION` → **5**; upload; attach to BOTH groups (Internal `d19f78c1-7af3-4461-9af6-1566200c251b` + Trusted Testers `d0d24fce-73d1-4f0c-864d-a8cfd029461e`); then `POST /v1/betaAppReviewSubmissions` for build 5 (the betaAppReviewDetail incl. contact phone + demo account is already set) → expect WAITING_FOR_REVIEW; public link `https://testflight.apple.com/join/7xCGKxCT` goes live on approval. STOP with the exact message if the Xcode session expired.

---

### Task 1: Share-sheet polish (all six notes) + success token

**Files:** Modify `ios/StashShareExtension/ShareComposeView.swift`, `ios/Stash/Design/StashDesign.swift` (+`success`), `ios/Stash/Ask/ChatBubble.swift` (green literal → token), `DESIGN.md` (token, dated); Test: `ios/StashUITests/StashUITests.swift` only if a placeholder-text assertion exists.

- [ ] **Step 1:** Implement per Global Constraints. Live-verify via a real Safari share on the sim (the T5/T7 recipe in the old task reports; the account is gate-blocked so ALSO verify the gate branch renders with the new save button disabled-but-visible).
- [ ] **Step 2:** Screenshots: compose card (URL variant + image variant with the big hero), the pinned save button with keyboard up, gate state, and the outcome view in BOTH states (seed or briefly force each; the will-sync state is reachable by sharing while offline — `xcrun simctl status_bar`… simpler: temporarily hit the queued path by sharing a >8MB file) → task-1-share-*.png; READ them (no strokes on cards/X; "Optional note…"; full-width bottom save; big preview; violet clock / green check).
- [ ] **Step 3:** `testShareExtensionURLSmoke` ×1 green (update in-task only if a text assertion broke — disclose); `swift test` 341; both targets build warning-free. Commit: `feat(ios): share sheet round 2 — strokeless cards, full-width pinned Save, larger preview, Optional note copy, violet/green outcome icons, success token`

### Task 2: Review (fresh reviewer: verify all six notes against screenshots + code; token/scope/identifier audit; memory rule on the bigger hero — no whole-file decodes)

### Task 3: Wrap — suites (StashKit, npm, UI ×2), ui-changes entry (share sheet round 2 + success token, web should adopt), outcome, version 5, upload, attach BOTH groups, submit Beta App Review, record state.
