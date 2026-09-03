# Stash iOS Plan 8: Feedback Round 1 (post-plan-7 device review) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Act on Will's 2026-09-03 review of the plan-7 build: restore the mobile-friendly Ask buttons, make the page gradient match the web palette (tokenized in DESIGN.md), drop wordmark/titles from View/Ask/Settings, fix the composer's keyboard/lock/attachment issues, render inline citation links in chat, and modernize the notes editor — then ship the next TestFlight build.

**Architecture:** Small, surgical changes on top of plan 7's DESIGN.md-derived system. Gradient stops become DESIGN.md tokens consumed by both platforms. Citation linking is a pure StashKit port of the web's `chatCitations.ts` (tested), rendered through the existing `MarkdownBlocksView` with a `stash://item/<uuid>` link scheme that opens the detail sheet. The notes editor keeps plan-2's append-only safety for rich (TipTap JSON) notes while giving plain-text notes a modern inline, autosaving editor.

**Tech Stack:** SwiftUI (iOS 17), StashKit, XCUITest, existing release pipeline.

**Spec:** Will's 2026-09-03 notes (verbatim in Global Constraints) + `DESIGN.md` + `src/index.css` `.animated-gradient` + `src/utils/chatCitations.ts` + `src/components/ChatMole.tsx` (inline links) + `src/components/EditItemContentSection.tsx` (notes editor).

## Global Constraints

- **Will's notes (verbatim intent, 2026-09-03):** (1) "the previous implementation of 'start a new chat' and 'earlier conversations' (buttons in a mobile-friendly way) was the better approach — go back to this"; (2) "gradient… web is a sweeping purple-blue-pinkish color; mobile looks streaky and doesn't animate… the color palette should remain consistent. if these colors need to be built into design.md, let's do that"; (3) "not have the STASH logo at the top of every tab… View, Ask or Settings tabs don't need any title… the Ask tab should have the intro text for each new conversation ('Ask anything')"; (4) "when focusing on the input panel and entering text, both a 'done' button and the purple 'send' button appear active — only send should be active"; (5) "show a 'minimize keyboard' button rather than a done button"; (6) "the 'remove' button for the clipped [attachment] along the top border" (the × is clipped); (7) "remove the 'lock' button from the input panel (sharing is managed from the detail screen)"; (8) "remove the stash logo from the view screen"; (9) "a more modern 'note' input option on the detail screen"; (10) "previous notes are hard to get to from the Ask tab (chips beneath)… replicate the web model where the user clicks hyperlinks from the chat itself to open the detail sheet".
- **Assumption (state in outcome):** the Add tab keeps the wordmark (it's the launch/brand moment; Will listed View/Ask/Settings explicitly). Reversible in one line.
- **DESIGN.md is the source of truth**; the gradient stops get written into it as named tokens in this plan (Task 1) so web and iOS share one recipe: `-45deg · #667eea → #764ba2 → #9d5fd8 → #c2418f → #4facfe → #38bdf8` (from `src/index.css:237`, 2026-08-30 revision). Reduced-motion honored (`DESIGN.md` rule 4).
- Tokens only (`StashColor`/`StashType`/`StashRadius`/`PillTabs`); no emoji; SF Symbols.
- Identifier contracts: `ask.newChat`, `ask.history` (move back to header buttons), `capture.dismissKeyboard` (keep on the new minimize-keyboard button), `ask.sources.N.chip.M` (chips now conditional), detail notes identifiers used by `testEditSmoke` — keep or update tests in-task. Append new tests at the END of `ios/StashUITests/StashUITests.swift`; single-writer per file when tasks run in parallel (see coexistence notes per task).
- Worktree `.claude/worktrees/ios-plan-8` (branch `worktree-ios-plan-8`, base `8ebc14f`): commit there, never push; audit `origin/main` before the final merge. Sims: `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` (primary), `46D4EA93-94D5-451E-AC61-A5485AFB211F`, `E188DE28-5253-4BC5-8117-0EE87DF1B783` (parallel tasks use distinct sims + `-derivedDataPath DerivedData-<task>`); StashKit floor **312**; UI suite 19 with the standing 3 gate-blocked adjudications; builds warning-free.
- Data lanes/ethos unchanged. Every behavior change → `docs/ui-changes.md` entry at wrap.
- Deploy at wrap: `CURRENT_PROJECT_VERSION` stays **2** (build 2 was archived but never uploaded — ASC has only build 1); upload via session auth if the Xcode session is live, else report the blocker.

## File Structure

- `DESIGN.md` — gradient token block (new); `ios/Stash/Design/StashDesign.swift` — `StashColor.gradientStops` + `AnimatedGradient`/`GradientBackdrop` rebuilt.
- `ios/Stash/Library/LibraryView.swift`, `ios/Stash/Settings/SettingsView.swift`, `ios/Stash/Ask/AskView.swift` — chrome removal / Ask buttons restored.
- `ios/Stash/Capture/CaptureComposerView.swift`, `ios/Stash/Capture/CaptureAttachmentsRow.swift` — keyboard control, lock removal, × clipping.
- `ios/StashKit/Sources/StashKit/Chat/ChatCitations.swift` (+ tests) — NEW port; `ios/Stash/Ask/ChatBubble.swift` — inline links.
- `ios/Stash/Detail/NotesEditor.swift` — NEW (replaces `NotesAppendComposer.swift`); `ios/Stash/Detail/ItemDetailContent.swift` — wiring.
- `ios/StashUITests/StashUITests.swift`; `docs/ui-changes.md`; this plan (outcome).

---

### Task 1: Gradient palette parity — DESIGN.md tokens + smooth iOS backdrop

**Files:**
- Modify: `DESIGN.md` (§Color: add "Page wash gradient" token block), `ios/Stash/Design/StashDesign.swift` (`gradientStops`, `AnimatedGradient`, `GradientBackdrop`)

**Interfaces:**
- Produces: `StashColor.gradientStops: [Color]` = the six web stops in order; `AnimatedGradient()` renders a −45° sweep (bottom-leading → top-trailing) that drifts slowly (15s, autoreverse) and is blurred enough to show no banding; `GradientBackdrop(opacity:)` unchanged signature, overlay fades to `StashColor.paper` (not `systemBackground`).

- [ ] **Step 1: DESIGN.md.** Under §Color add:
  ```
  **Page wash gradient** (the only sanctioned gradient; page backdrops + splash):
  `linear-gradient(-45deg, #667eea, #764ba2, #9d5fd8, #c2418f, #4facfe, #38bdf8)` — web `.animated-gradient`
  (400% canvas, 15s ease drift; static under reduced motion). iOS: `StashColor.gradientStops` in the same
  order, drawn bottom-leading → top-trailing over a 2× canvas with a 40pt blur so no stop banding shows;
  drift optional, palette mandatory.
  ```
- [ ] **Step 2: iOS.** Replace `gradientStops` with `#667eea, #764ba2, #9d5fd8, #c2418f, #4facfe, #38bdf8`. Rebuild `AnimatedGradient`: `LinearGradient(colors: stops, startPoint: .bottomLeading, endPoint: .topTrailing)` on a `geo.size * 2` frame, `.blur(radius: 40)`, offset drifting between two positions with `.easeInOut(duration: 15).repeatForever(autoreverses: true)`; wrap the animation in `@Environment(\.accessibilityReduceMotion)` (static when true); `.clipped()`. `GradientBackdrop` overlay: `.clear → StashColor.paper.opacity(0.5) @0.55 → StashColor.paper @1`.
- [ ] **Step 3: Verify.** Build; screenshot the sign-in screen and the Add tab on the sim; READ them next to the web (`https://www.gostash.it/auth` via headless Chrome screenshot at 1170×2532 for a like-for-like) — palette must read purple-blue-pink, no visible bands. Save both → `.superpowers/sdd/…/task-1-gradient-{ios,web}.png`. `swift test` untouched (312).
- [ ] **Step 4: Commit.** `git add DESIGN.md ios/Stash/Design/StashDesign.swift && git commit -m "feat(design): page-wash gradient tokens in DESIGN.md; iOS backdrop matches the web palette, smooth, reduced-motion aware"`

---

### Task 2: Chrome cleanup — no wordmark/title on View, Ask, Settings; Ask buttons restored

**Files:**
- Modify: `ios/Stash/Library/LibraryView.swift:54` (drop `StashHeader`; keep its trailing controls if any as a plain toolbar row), `ios/Stash/Settings/SettingsView.swift:19` (drop `StashHeader`), `ios/Stash/Ask/AskView.swift` (drop the "Ask Stash / Answers from…" title block; restore a right-aligned header row of two `CircleIcon` buttons — `square.and.pencil` = `ask.newChat`, `clock` = `ask.history` — exactly the pre-plan-7 affordance; remove the footer links; keep the intro bubble "Ask anything about what you've saved — answers cite the cards they came from." for every new conversation)
- Test: `StashUITests.swift` — replace `testAskFooterLinksRenderAndOpenConversations` body with header-button assertions (rename to `testAskHeaderButtonsOpenConversations`; append-only elsewhere).

**Interfaces:**
- Produces: identifiers `ask.newChat`/`ask.history` on the header buttons; `ask.itemCount` removed (no subtitle); `testConversationsSmoke` continues to find both buttons.

- [ ] **Step 1: RED.** Update the test: assert both buttons exist ABOVE the intro bubble (`frame.maxY < bubble.frame.minY`), tap `ask.history` → "Conversations" title exists → back; assert no element `ask.itemCount`. Run → fails (footer links still there).
- [ ] **Step 2: Implement** the three views. Library/Settings: no header text at all; content starts under the safe area with the same top padding the composer uses. Ask: `HStack { Spacer(); CircleIcon(newChat); CircleIcon(history) }` at the top, then the thread.
- [ ] **Step 3: GREEN** — new test + `testConversationsSmoke` + `testSettingsSmoke` + `testLibrarySmoke` ×1. Screenshots of the three tabs.
- [ ] **Step 4: Commit.** `git commit -m "feat(ios): no wordmark/title on View, Ask, Settings; Ask new-chat/history buttons restored (Will's call)"`

---

### Task 3: Composer — minimize-keyboard control, no lock, un-clipped attachment ×

**Files:**
- Modify: `ios/Stash/Capture/CaptureComposerView.swift` (`:106-114` keyboard toolbar "Done" → an icon-only `Button` with `keyboard.chevron.compact.down`, identifier `capture.dismissKeyboard`, a11y label "Hide keyboard", shown whenever the editor is focused; `:279-281` remove the public/lock toggle and any `isPublic` UI — the view model's `isPublic` stays `false`), `ios/Stash/Capture/CaptureAttachmentsRow.swift` (`.padding(.vertical, 2)` → `.padding(.top, 10).padding(.trailing, 8)` on the row content and `.scrollClipDisabled()` on its ScrollView so the `xmark.circle.fill` at `offset(6,-6)` isn't clipped)

**Interfaces:**
- Consumes: `CaptureViewModel.isPublic` (default false — verify; if it persisted a user preference, keep default private).
- Produces: only the violet send button reads as the primary action while typing; the keyboard accessory shows the minimize icon only.

- [ ] **Step 1: RED.** Append `testComposerKeyboardAccessory`: focus `capture.editor` (or whatever the input identifier is — read the file), type "x", assert `capture.dismissKeyboard` exists with label "Hide keyboard" and NO button titled "Done"; assert no `capture.publicToggle`/lock identifier exists (read the current identifier and assert absence); tap `capture.dismissKeyboard` → keyboard hidden (assert the accessory button disappears). Run → fails.
- [ ] **Step 2: Implement** per Files. Attachments: add an image attachment in the smoke if a fixture path is cheap (else screenshot manually) and verify the × is fully visible — screenshot → `task-3-attachment-x.png` and READ it.
- [ ] **Step 3: GREEN** — new test + `testCaptureSmoke` pre-gate assertions (gate-blocked adjudication unchanged) + `testLocationPinSmoke` pre-gate ×1.
- [ ] **Step 4: Commit.** `git commit -m "fix(ios): composer keyboard accessory is a minimize control (no Done), lock toggle removed, attachment × no longer clipped"`

---

### Task 4: Inline citation links in chat (StashKit port of chatCitations.ts)

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Chat/ChatCitations.swift`, `ios/StashKit/Tests/StashKitTests/ChatCitationsTests.swift`
- Modify: `ios/Stash/Ask/ChatBubble.swift` (assistant content through `MarkdownBlocksView` with links; chips only when no inline links resolved), `ios/Stash/Ask/AskView.swift` (`.environment(\.openURL, …)` handler for `stash://item/<uuid>` → existing `onCitationTap`)

**Interfaces:**
- Produces:
```swift
public enum ChatCitations {
    public static let itemLinkPrefix = "stash://item/"
    /// Port of src/utils/chatCitations.ts: `[Title](#3)` → `[Title](stash://item/<uuid>)`;
    /// bare `[3]` → `[[3]](stash://item/<uuid>)` (skips already-linked); unknown numbers untouched.
    public static func link(answer: String, sources: [ChatSource]) -> (text: String, linkedSourceIDs: Set<UUID>)
}
```
- `ChatSource` already carries the citation number the web uses (check `ChatSource`/SSE payload for `citation`/index; if only order is available, use 1-based order — disclose).

- [ ] **Step 1: Failing tests** (RED): linked-title form, bare-marker form, already-linked skip, unknown number untouched, multiple markers, no sources → unchanged text + empty set, malformed `[abc]` untouched.
- [ ] **Step 2: Implement** (single pass, no regex catastrophes) mirroring `chatCitations.ts` order of operations.
- [ ] **Step 3: Render.** In `ChatBubble`, assistant text = `MarkdownBlocksView(text: linked.text)`; `MarkdownBlocksView` paragraphs already use `AttributedString(markdown:)` so links become tappable `Text` links styled `violet600` underline-free; add `.environment(\.openURL, OpenURLAction { url in if url.scheme == "stash", let id = UUID(uuidString: url.lastPathComponent) { onCitationTap(id); return .handled } ; return .systemAction })` at the thread level. Source chips render ONLY when `linkedSourceIDs` is empty (answers without markers). Identifiers: links can't carry identifiers per-run inside `Text`; keep `ask.sources.N.chip.M` for the fallback and add `ask.bubble.N.hasLinks` (a11y hint) for the smoke.
- [ ] **Step 4: GREEN** — `swift test` (312 + ~7); `testAskSmoke` pre-gate assertions; build warning-free. Since the account is gate-blocked for real answers, prove rendering with a SwiftUI `#Preview` using a fixture answer containing `[Title](#1)` and READ a screenshot of the preview or a DEBUG-only seeded bubble.
- [ ] **Step 5: Commit.** `git commit -m "feat(ios): inline citation links in chat (chatCitations port, stash://item/<id> → detail sheet); chips only as fallback"`

---

### Task 5: Modern notes editor on the detail sheet

**Files:**
- Create: `ios/Stash/Detail/NotesEditor.swift`; Delete: `ios/Stash/Detail/NotesAppendComposer.swift`
- Modify: `ios/Stash/Detail/ItemDetailContent.swift` (Notes tab wiring), `StashUITests.swift` (`testEditSmoke` notes steps — read them first; keep `detail.notesComposer.*` identifiers on the new editor or update in-task)

**Interfaces:**
- Consumes: `ItemEditor.save(itemId:patch:)`, `appendNoteParagraph(to:note:)`, `renderTipTap`, `isTipTapJSON`-style detection (grep StashKit for how rich notes are recognized — `{"type":"doc"` prefix).
- Design: web's notes editor is a quiet rich editor with autosave. iOS v1 "modern" = inline, borderless, auto-growing `TextEditor`-style field on `wash` fill (radius 12), placeholder "Add a note…", Neue Montreal body, autosave (600ms debounce, same `SaveStatus` the title uses → footer "Saving…/Changes saved automatically"), the keyboard-minimize accessory from Task 3 (shared control), no separate Save button. **Plain-text notes**: the field shows the FULL existing note, fully editable (content lane). **Rich notes (TipTap JSON)**: existing note renders read-only via `renderTipTap` above the field, and the field appends a paragraph on blur/debounce via `appendNoteParagraph` (plan-2 safety preserved — never round-trip TipTap JSON through a plain editor). A small muted line under the field states which mode ("Editing note" / "Adding to a rich note").

- [ ] **Step 1: RED.** Update/append `testEditSmoke`'s notes step: type into `detail.notes.editor`, wait for `detail.autosave` to read "Changes saved automatically", REST-verify `content` contains the marker (the smoke already has REST helpers + the restore-first fixture pre-flight to undo). Run → fails (identifier absent).
- [ ] **Step 2: Implement** `NotesEditor` per Design; wire; delete the old composer.
- [ ] **Step 3: GREEN** — `testEditSmoke` + `testDetailSheetAnatomy` ×1; screenshot → `task-5-notes.png`.
- [ ] **Step 4: Commit.** `git commit -m "feat(ios): inline autosaving notes editor on the detail sheet (plain notes editable; rich notes append-safe)"`

---

### Task 6: Wrap — docs, suites ×2, TestFlight build

**Files:** `docs/ui-changes.md` (new top entry "2026-09-03 · iOS feedback round 1": Ask buttons decision REVERSED (header circle buttons are the iOS affordance; footer text links retired — note for web: no change), gradient tokens now in DESIGN.md (web should reference the token block), no wordmark/title on View/Ask/Settings, composer keyboard-minimize + lock removed (sharing only on detail), attachment × fix, inline citation links (`stash://item/` on iOS ≙ `#item=` on web), notes editor semantics (plain editable / rich append)), this plan (outcome), `DESIGN.md` already edited in T1.

- [x] **Step 1:** foreign-commit audit + merge `origin/main` into the branch; resolve; re-run.
- [x] **Step 2:** `swift test` (≥341), builds warning-free, `npm test`, UI suite ×2 (21 tests, standing 3 failures only).
- [x] **Step 3:** docs + outcome (incl. the Add-tab-wordmark assumption for Will to confirm) → commit `docs(ios): plan-8 outcome; ui-changes entry`.
- [x] **Step 4:** TestFlight: `cd ios && ./scripts/release.sh all && ./scripts/release.sh upload` (session auth). If "login details… rejected"/`missing Xcode-Token` → STOP and report (Will must re-sign into Xcode; build stays 0.1.0 (2)). Else poll VALID and attach to group `d19f78c1-7af3-4461-9af6-1566200c251b`. **Done** — session auth worked, build 2 uploaded/VALID/attached (see Outcome → Build 2).

---

## Self-review notes

- **Coverage:** notes 1→T2; 2→T1; 3+8→T2; 4+5→T3; 6→T3; 7→T3; 9→T5; 10→T4; deploy→T6. Assumption (Add-tab wordmark) recorded for Will.
- **Placeholders:** none — every task names files, identifiers, and verification.
- **Type consistency:** `ChatCitations.link` return shape used identically in T4 Steps 1–3; `capture.dismissKeyboard` reused; `StashColor.gradientStops` name unchanged for existing consumers.
- **Risks accepted:** real chat answers are gate-blocked on the test account (T4 proves rendering via fixture/preview); TipTap round-trip avoided by design in T5; parallel tasks share `StashUITests.swift` (append-only + single test-name ownership).

---

## Outcome (2026-09-03)

**Commit range:** `8ebc14f..HEAD` (base = `main` at plan authoring time).

| Commit | Task | Message |
|---|---|---|
| `9147377` | — | docs(ios): plan 8 — feedback round 1 (Ask buttons, gradient tokens, chrome, composer, citations, notes) |
| `cbf1a15` | T1 | feat(design): page-wash gradient tokens in DESIGN.md; iOS backdrop matches the web palette, smooth, reduced-motion aware |
| `70f3470` | T2 | feat(ios): no wordmark/title on View, Ask, Settings; Ask new-chat/history buttons restored (Will's call) |
| `3a5ad95` | T3 | fix(ios): composer keyboard accessory is a minimize control (no Done), lock toggle removed, attachment × no longer clipped |
| `9d20b2c` | T4 | feat(ios): inline citation links in chat (chatCitations port, stash://item/<id> → detail sheet); chips only as fallback |
| `a67198f` | T5 | feat(ios): inline autosaving notes editor on the detail sheet (plain notes editable; rich notes append-safe) |
| `1f28704` | T4 fix round 1 | fix(ios): bake citation links before persist (cross-platform #item= convention), per-source chip filter, dead-link guard |
| `55cfd3c` | T5 fix round 1 | fix(ios): notes editor — flush on dismiss (both modes) + cross-field save generation guard |
| `2412cda` | — (foreign) | fix(cards): clean scraped titles/descriptions, subject-aware hero crops, report-a-problem (merged from origin/main at T6) |
| `55595f7` | final wave | fix(ios): plan-8 final wave — lowercase citation ids, detail keyboard focus, rich-note append on blur only, save-failure state, minors |
| `3b31f62` | T6 | Merge remote-tracking branch 'origin/main' into worktree-ios-plan-8 (foreign commit audit, step 1) |

### Verification

- **StashKit:** `swift test` → **341/341 passing, 0 failures.** Growth over the plan: 312 → 341
  (T1 untouched it; T4 added `ChatCitationsTests` twice — port + fix-round-1 lowering; T5 added
  `SaveGenerationTests`, `ItemMergeTests` content-flag cases, a `Debouncer.cancel` test; final wave
  added `tipTapLastParagraphText` coverage).
- **App + extension build:** `xcodegen generate` → `xcodebuild build` (sim
  `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, `-derivedDataPath DerivedData`) → **BUILD SUCCEEDED**,
  zero compiler warnings (`StashShareExtension` embeds into the same build; grepped the full log
  for `warning:` — none from any project file).
- **Web:** `npm install` + `npm test` (worktree root) → **32 test files, 197 tests, all passed**
  (includes the merged-in `2412cda` hero-crop/card-feedback/text-hygiene suites).
- **UI suite ×2:** full `StashUITests` (21 tests — the plan-7 19 plus `testComposerKeyboardAccessory`
  new in T3 and `testAskFooterLinksRenderAndOpenConversations` renamed to
  `testAskHeaderButtonsOpenConversations` in T2, both counted; `testDetailSheetAnatomy` extended
  in place by the final wave, not a new test) run twice against production. `STASH_DELETE_MARKER`
  freshly reseeded via the `add-note` REST endpoint before each run (a disposable item titled
  `UITEST-DELETE-<run>-<epoch>`, deleted by the test itself). Both runs: exactly the standing 3
  gate-blocked failures (`testAskSmoke`, `testCaptureSmoke`, `testLocationPinSmoke` — Stripe comp
  decision still pending, unchanged since plan 4) and every other test green, including
  `testDeleteSmoke` and both notes-editor/detail-focus tests. No investigation needed — no
  unexpected failures either run.

### Decisions of record

1. **Ask affordance reversed** — the plan-7 call ("footer text links, header icons retired") was
   wrong on a real phone; the header `CircleIcon` pair (`ask.newChat`/`ask.history`) is the
   permanent iOS affordance, footer links retired instead (T2). Plan-7's own bullets amended in
   place with dated notes rather than rewritten.
2. **Page-wash gradient stops are DESIGN.md tokens** — `#667eea, #764ba2, #9d5fd8, #c2418f,
   #4facfe, #38bdf8`, `-45deg`, shared by web's `.animated-gradient` and iOS's
   `StashColor.gradientStops` (T1); iOS draws it over a 2× canvas with a 40pt blur, plus
   `.drawingGroup()` after the blur (final wave, perf) so the 15s drift animation translates a
   cached bitmap instead of re-blurring every frame.
3. **No wordmark/title on View, Ask, or Settings** — `StashHeader` is Add-tab + share-sheet only
   now (T2). **Assumption, unconfirmed — Will to weigh in**: the Add tab keeps the wordmark as the
   brand/launch moment. One-line reversal if wrong (drop the `StashHeader(...)` call site in
   `CaptureComposerView.swift`).
4. **Composer**: minimize-keyboard icon replaces the "Done" text button (`capture.dismissKeyboard`,
   shared with the notes editor's own keyboard accessory); the public/lock toggle is gone from the
   composer — sharing is detail-sheet-only (T3).
5. **`#item=<uuid>` is the cross-platform citation-link convention**, baked into `messages.content`
   at persist time on both platforms (not just at render) — **uuid must be lowercase** (web's
   extraction regex is case-sensitive `[0-9a-f-]+`; this was wrong for one intermediate commit
   within this plan — `9d20b2c` briefly used `stash://item/` and uppercase `UUID.uuidString` — and
   corrected in `1f28704`/`55595f7` before merge). iOS keeps read-only recognition of the old
   `stash://item/<uuid>` form so nothing already baked that way goes dead (T4, fix round 1, final
   wave item A).
6. **Notes editor semantics**: plain-text notes are now fully editable with whole-field autosave
   (600ms debounce, flush on blur/Done/dismiss); rich (TipTap JSON) notes stay read-only-render +
   append-only, and — after the whole-branch review caught mid-keystroke paragraph-splitting — the
   append now fires on blur/Done only, never on the debounce tick (T5, final wave item C).
7. **`SaveGeneration`** (new StashKit type, mirrors `ItemStore`/`SubscriptionStore`'s plain-Int-on-
   `@MainActor` pattern) guards `saveChangedFields`/`saveAttributes`/`flushNotes` against an
   out-of-order network response clobbering newer local state — added because T5's second
   debouncer (the notes field) made a pre-existing cross-field race actually reachable (T5, fix
   round 1).
8. **A failed autosave now surfaces to the user** — `SaveStatus.failed(String)`, rendered as
   "Couldn't save — try again." in the destructive color under `detail.autosave.error`, distinct
   from the resting `detail.autosave` identifier; applies to both the notes flush and the
   title/description field save. Nothing typed is discarded on a failed save (final wave item D).

### Carried items (not blocking, flagged for follow-up)

1. **Inline citation links render violet with no underline on iOS; web underlines them**
   (`underline decoration-violet-300`) — a real, disclosed visual divergence, not reconciled this
   round (T4 / final wave; flagged in `docs/ui-changes.md` for a decision).
2. **`MarkdownBlocksView` styles every markdown link it renders violet/no-underline, not just
   citation links** — disclosed in the view's own doc comment (T4). It can't currently distinguish
   a `ChatCitations`-baked item link from any other markdown link that might appear in AI-generated
   text (Summary/Original/Transcript tabs also route through this view), so the blanket styling is
   a known simplification, not a bug.
3. **`Debouncer.cancel()` can't stop an already-started action** — `onDisappear` now cancels the
   pending field debounce *before* its own explicit save (final wave item E/7), which closes the
   common case, but if the 600ms timer had already fired and the save was already in flight at the
   moment `cancel()` runs, that save still completes — a rare, harmless duplicate PATCH (T5
   re-review; not re-attempted this plan).
4. **A dropped `SaveGeneration` response can still duplicate a rich-note's appended paragraph, once,
   in a narrow window** — `flushNotes()` now checks the trailing paragraph against the draft before
   appending and skips if they already match (final wave item C, minor 6), but only if a
   realtime/adopt refresh has already folded the dropped save into local `item.content` by the time
   the *next* flush runs; explicitly disclosed as not a complete fix (closing it fully would need
   re-fetching the row before every append — judged not worth the round trip for this rare race).
5. **`MarkdownBlocks.looksLikeMarkdown` doesn't trigger on "N)" numbered lists** — unchanged from
   plan 7; intentional parity with web's own detection gap, not an iOS-only miss.
6. **`.orange`/`.green` still have no `DESIGN.md` token** — unchanged from plan 7; iOS keeps using
   the system colors at a few warning/success sites pending a web/mac decision on whether to
   standardize one.
7. **Apple 5.1.1(v) in-app account-deletion requirement is still pending** — unchanged from plan 7
   (iOS can create accounts via sign-up, so deletion must ship before the app leaves TestFlight for
   the public App Store; TestFlight itself is unaffected). Not addressed by this plan — still a
   named requirement for whichever plan takes it on.
8. **The `ios-plan6-visual` worktree (`worktree-ios-plan6-visual`) is still unmerged** — a parallel
   visual-overhaul branch predating plan 7's own consolidation, still sitting in
   `.claude/worktrees/ios-plan6-visual`. Whatever it has that plan 7/8 didn't already absorb is a
   plan-9 harvest candidate, not touched by this plan.

### Process note

T2's commit (`70f3470`) swept an in-progress stub of T3's `testComposerKeyboardAccessory` out of
`StashUITests.swift` mid-edit — two parallel writers touching the same file in the same round. The
whole-branch review adjudicated this as a git-hygiene-only issue (the shipped test is functionally
correct and the header-button affordance is byte-identical to the pre-plan-7 UI); rewriting four
commits of history mid-plan to fix attribution was judged not worth the risk. **Rule going
forward** (already true for T4/T5 in this same plan): single writer per file per parallel round —
don't let two tasks edit `StashUITests.swift` in the same wave.

### Build 2 (TestFlight)

- Version: `MARKETING_VERSION 0.1.0` / `CURRENT_PROJECT_VERSION 2` (`ios/project.yml`, unchanged
  by this plan — verified before upload: ASC had only build 1 on record).
- Xcode session was live (unlike plan 7's outcome) — the full pipeline ran unattended:
  `./scripts/release.sh all` (generate → archive → export) → **ARCHIVE SUCCEEDED** / **EXPORT
  SUCCEEDED**, then `./scripts/release.sh upload` → **Upload succeeded** (session auth throughout,
  no `--key-auth` needed).
- Polled `./scripts/asc-api.sh GET "/v1/builds?filter[app]=6806459949&sort=-uploadedDate&limit=3"`
  every 20s: build 2 (`1e082eda-ec36-467e-a139-bf4e2c59b7ed`, uploaded 2026-09-03T09:39:43-07:00)
  reached `processingState: VALID` in under 3 minutes (faster than Apple's typical 5–15 minute
  quote, in line with the ~1 minute observed 2026-08-30). `usesNonExemptEncryption: false`
  resolved automatically — no manual export-compliance step needed.
- Attached to the `Internal` beta group (`d19f78c1-7af3-4461-9af6-1566200c251b`) via
  `POST /v1/betaGroups/<id>/relationships/builds` → **HTTP 204**; confirmed via
  `GET /v1/betaGroups/<id>/builds` — group now lists both build 1 (`517e1f68…`) and build 2
  (`1e082eda…`). Internal testers get no beta-review gate; the build is installable the moment
  this attachment lands.
- **Not yet done, out of scope for this task**: bumping `CURRENT_PROJECT_VERSION` for a build 3 —
  the next release should bump it before archiving, per `docs/RELEASING.md`'s rule (ASC rejects a
  byte-identical re-upload of a version+build pair it has already seen).
