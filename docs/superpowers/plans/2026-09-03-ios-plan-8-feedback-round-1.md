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

- [ ] **Step 1:** foreign-commit audit + merge `origin/main` into the branch; resolve; re-run.
- [ ] **Step 2:** `swift test` (≥319), builds warning-free, `npm test`, UI suite ×2 (standing 3 failures only).
- [ ] **Step 3:** docs + outcome (incl. the Add-tab-wordmark assumption for Will to confirm) → commit `docs(ios): plan-8 outcome; ui-changes entry`.
- [ ] **Step 4:** TestFlight: `cd ios && ./scripts/release.sh all && ./scripts/release.sh upload` (session auth). If "login details… rejected"/`missing Xcode-Token` → STOP and report (Will must re-sign into Xcode; build stays 0.1.0 (2)). Else poll VALID and attach to group `d19f78c1-7af3-4461-9af6-1566200c251b`.

---

## Self-review notes

- **Coverage:** notes 1→T2; 2→T1; 3+8→T2; 4+5→T3; 6→T3; 7→T3; 9→T5; 10→T4; deploy→T6. Assumption (Add-tab wordmark) recorded for Will.
- **Placeholders:** none — every task names files, identifiers, and verification.
- **Type consistency:** `ChatCitations.link` return shape used identically in T4 Steps 1–3; `capture.dismissKeyboard` reused; `StashColor.gradientStops` name unchanged for existing consumers.
- **Risks accepted:** real chat answers are gate-blocked on the test account (T4 proves rendering via fixture/preview); TipTap round-trip avoided by design in T5; parallel tasks share `StashUITests.swift` (append-only + single test-name ownership).
