# Stash iOS Plan 12: Feedback Round 3 (first on-device round) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the two on-device bugs (deleted item persists in the list; detail-sheet images not rendering), replace the unreliable iOS-26 keyboard-toolbar accessories with in-content hide-keyboard buttons, polish the View tab (search-bar fade on scroll, no item count, smart keyboard dismissal), add the Ask title and Add-tab spacing, ship a one-panel post-sign-in "How to easily stash" screen, then TestFlight build 8.

**Architecture:** Four file-disjoint tasks run two at a time (max 2 concurrent builders — plan-10 lesson): T1 Detail/Library/StashKit bugs + whole-card tap + detail hide-keyboard; T2 composer keyboard control + margins + Ask title; then T3 View-tab search polish; T4 onboarding panel (new files + assets). T5 wrap.

**Spec:** Will's 2026-09-06 device notes (verbatim below) + DESIGN.md + `docs/ETHOS.md`.

## Global Constraints

- **Will's notes (verbatim):** (1) "on the latest version of iOS, the 'minimize keyboard' button appears to occlude the 'submit note' button"; (2) "added a simple note using my own account, then deleted it from the detail sheet, and the item is still showing in the list. pull-refresh didn't help"; (3) "on iOS, clicking anywhere on the note should bring up the detail sheet (unlike the web)"; (4) "images are not showing up on the detail sheet on iOS at all"; (5) "when the keyboard is active and the user is adding a note on the detail screen, we need a 'hide keyboard' button"; (6) "on the view tab, animate the 'search your stash' bar out of view when the list is scrolled… fade to opacity 0 and have the list items continue to the top of the screen. hide the total number of items"; (7) "when the search bar is active or has been used, there's no way to hide the keyboard in a smart way after a search has been performed or the user clears the search box"; (8) "add a title back to the 'Ask' tab that says 'Chat with your Stash'"; (9) "on the 'add' tab, increase the margin on the input panel by 10% (same with the Stash logo). increase the padding inside the input panel by a similar amount (incl. the bottom of the button bar and left of the button bar)"; (10) "a single panel 'How to easily stash' screen post-sign-in that reminds the user they can use the Sharing intent from any app… basic screenshots that spell through how to use the standard iOS share sheet, then choose the Stash icon".
- **Keyboard-control decision (covers 1 + 5):** iOS 26 renders `.toolbar(placement: .keyboard)` accessories as a floating bar that can overlap content and, on the detail sheet, sometimes never appears. Retire BOTH keyboard-toolbar accessories (`CaptureComposerView.swift:153-160`, `ItemDetailView.swift:180`). Replace with in-content controls: composer → a `CircleIcon(systemImage: "keyboard.chevron.compact.down")` in the composer's own bottom bar (left group, shown only while the editor is focused; send stays the sole primary; identifier `capture.dismissKeyboard` preserved so smokes keep working); detail sheet → same control in a small row at the top-right of the notes editor while notes/title/description are focused (identifier `detail.dismissKeyboard` preserved), clearing the unified `focusedField`. Delete the plan-8 `NavigationStack` wrap ONLY if it existed solely for the toolbar (read its comment; keep if anything else depends on it).
- **Delete bug (2) — investigate, don't guess:** reproduce on the sim with the uitest account: create a note (Add tab), open it, Delete → confirm → does it vanish from the list? then pull-refresh. Trace `performDelete` → `ItemEditor.deleteItemCascade`/`delete` → `ItemStore` removal + realtime. Suspects: the just-created item's list entry came from a realtime INSERT and the DELETE event isn't applied; the delete request failing silently (surface `deleteErrorMessage`!); soft-delete vs list query filter; the store's generation token dropping the removal. Fix the root cause + a StashKit test where possible + extend `testDeleteSmoke` to cover create→delete→refresh. If it does NOT reproduce with the fixture account, report precisely what you tried and check for server-side differences (RLS on delete for items with enrichment rows).
- **Images bug (4) — investigate, don't guess:** `ItemDetailView.swift:295` uses a bare `AsyncImage(url:)`; cards (`CardHero.swift:75`) also use AsyncImage and DO render on device per Will. Find why the detail URL differs (storage signed/public URL builder, `file_path` vs `url` selection, og-image for links, an `https` upgrade, a `.image`-only gate that skips links/videos, a hero that's `nil` when `hasHero` computes false). Test on the sim with the image fixture, a link fixture WITH an og image, and a video fixture; then READ the screenshots. If everything renders on the sim, the device difference is likely the URL/ATS → ask the coordinator for one of Will's failing items (id) via the report rather than guessing.
- **Whole-card tap (3):** LibraryView wraps cards in a selection `Button` — verify what parts of `ItemCardView` currently swallow taps (hero `Link`, chips, footer) and make the ENTIRE card open the detail sheet; the only exception is an explicit external-link affordance if one exists (keep it, smaller). `testCardAnatomySmoke`/`testLibrarySmoke` must still pass.
- **View tab (6, 7):** search pill fades to opacity 0 as the list scrolls up (drive from scroll offset via a `GeometryReader`/`onScrollGeometryChange` on iOS 18+ with an iOS 17 fallback using a preference key — min iOS 17), and the list continues to the top (the pill's slot collapses, no hard margin). Remove `itemCountRow` (`LibraryView.swift:74-77`). Keyboard: `.scrollDismissesKeyboard(.immediately)` on the list; the search field gets a Cancel/clear affordance that clears AND dismisses; submitting a search (return key) dismisses; a tap on any card dismisses first.
- **Ask title (8):** "Chat with your Stash" as a small panel title (`StashType.medium(size: 22)`, ink) left-aligned in the header row with the two circle buttons right-aligned; intro bubble unchanged.
- **Add-tab spacing (9):** outer horizontal margin of the composer card and the wordmark: current value × 1.1; inner padding of the card content × 1.1; bottom bar: bottom padding × 1.1 and leading padding × 1.1 — read the current values and record before/after in the report.
- **Onboarding (10):** new `ios/Stash/Onboarding/HowToStashView.swift` — a single panel: title "How to easily stash", one-line lead ("Save from any app: tap Share, then Stash."), a three-step illustrated strip (real simulator captures, bundled as an image set: 1 Safari share button, 2 the share sheet with the Stash icon, 3 the Stash compose card), a "Got it" primary button (violet600, full width, 52pt) and a "Show me later" text link. Shown ONCE after a successful sign-in/sign-up (UserDefaults flag `onboarding.howToStash.seen`, per app install), re-openable from Settings → "How to stash". Capture the three screenshots on the sim via the existing Safari-share recipe, crop/scale to a phone-frame-free ~1:2 portrait at @2x/@3x, ≤300KB each; DESIGN.md flat-brand rules (no gradients in the illustrations; the page wash behind the panel is fine). UI test: `testOnboardingPanelShowsOnceAfterSignIn` (reset flag via the existing `--uitest-reset-auth` path or a new `--uitest-reset-onboarding` DEBUG arg).
- Tokens only; 1px strokes; no emoji; identifiers preserved (`capture.*`, `detail.*`, `card.*`, `ask.*`); new tests appended at END of `ios/StashUITests/StashUITests.swift`; single writer per file per round; max 2 concurrent builders with distinct sims (`28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` primary, `46D4EA93-94D5-451E-AC61-A5485AFB211F`) and `-derivedDataPath`. StashKit floor 341; UI suite 22 (+new) with the standing 3 gate-blocked adjudications; builds warning-free; `xcodegen generate` only for new files.
- Worktree `.claude/worktrees/ios-plan-12` (base = main `b04e8ff`): commit, never push; audit origin/main at wrap. Deploy: `CURRENT_PROJECT_VERSION` → **8**; attach to BOTH groups; Beta App Review: submit build 8 IF no build is currently WAITING_FOR_REVIEW/IN_REVIEW (check `betaAppReviewSubmission` on builds 6 and 7 first); otherwise record the blocker.

## Tasks

### Task 1 (owner: Detail/*, Library/ItemCardView.swift, StashKit) — bugs + whole-card tap + detail hide-keyboard
Delete bug (repro → root cause → fix → StashKit test + `testDeleteSmoke` extension); images bug (repro matrix image/link/video → fix); whole-card tap; detail sheet keyboard control replaces the toolbar accessory (`detail.dismissKeyboard` preserved). Smokes: testDeleteSmoke, testDetailSheetAnatomy, testEditSmoke, testCardAnatomySmoke, testLibrarySmoke. Screenshots of image/link/video detail sheets.

### Task 2 (owner: Capture/*, Ask/AskView.swift) — composer keyboard control + Add margins + Ask title
Composer accessory → in-bar control (`capture.dismissKeyboard`), margins/padding ×1.1 with before/after table, Ask header title. Smokes: testComposerKeyboardAccessory (update its accessory expectations in place if needed — it's the only test touching this), testLibraryTypeChipAndComposerCard, testAskHeaderButtonsOpenConversations. Screenshots.

### Task 3 (owner: Library/LibraryView.swift) — search bar fade + count removal + keyboard dismissal
Append `testLibrarySearchBarFadesAndKeyboardDismisses`. Smokes: testLibrarySmoke, testCardAnatomySmoke.

### Task 4 (owner: new Onboarding/*, Settings/SettingsView.swift entry, Auth sign-in completion hook, assets) — How to easily stash panel
Capture + bundle the three step images; panel; once-after-sign-in gating; Settings re-entry; `testOnboardingPanelShowsOnceAfterSignIn`; `xcodegen generate`.

### Task 5 — wrap
Whole-branch review → fix wave → docs (`ui-changes.md` entry: keyboard-control decision (web unaffected), whole-card tap, search-bar behavior, Ask title, onboarding panel + its flag, Add spacing; plan outcome) → suites ×2 → version 8 → upload → attach both groups → review submission per the constraint → merge hand-off.

## Outcome (2026-09-07)

All 10 of Will's device notes shipped. Commits on `worktree-ios-plan-12`
(base `b04e8ff`), task order: `91a5e92` (T2: composer keyboard control,
Add-tab spacing, Ask title), `5056164` (T3: View-tab search fade/count/
keyboard dismissal), `22be3a7` (T1: delete bug, detail images, whole-card
tap, detail keyboard control), `055b45c` (T4: onboarding panel), then the
whole-branch-review fix wave — `ced71da`/`90b6341`/`1777b9c`/`b51ee42`/
`e1e6b71`/`ed52e05` (F1–F8 + Will's markup: Cancel-button composer control,
onboarding step1/step3 re-crops, deferred-panel semantics, delete-error
copy + footer keyboard control, gitignore, test updates) — and this wrap's
own commits: a cosmetic leading-inset fold on the composer editor (17pt →
16pt in the first pass was the wrong direction; final `.padding(.leading,
15)` for ~20pt effective), the `origin/main` merge (16 commits, MCP server +
YouTube-thumbnail work, zero `ios/` overlap — merged clean, no conflicts),
a `testDetailSheets` test-only timing fix (see `docs/ui-changes.md`'s
"Tests" subsection under this same date for the root cause), the
`CURRENT_PROJECT_VERSION` bump to 8, and the docs/build-8 commits below.

**Suites:** StashKit 344/344. `npm test` 250/250 across 39 files. Both Xcode
targets (`Stash`, `StashShareExtension`) build warning-free against
`28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`. UI suite run 4× total during this
wrap (24 test methods each): the first two runs surfaced an unexpected,
deterministic (2/2) `testDetailSheets` failure caused by this round's own
search-focus-drops-on-card-tap change (Task 3) — fixed test-side (see
above); the final two runs after the fix landed on exactly the 3 standing
gate-blocked failures (`testCaptureSmoke`/`testLocationPinSmoke`/
`testAskSmoke`) with all 21 others green. One additional one-off failure
(`testVoiceNoteSmoke`, run 1 only, "Detail sheet did not present") did not
reproduce on any other run and coincided with visible simulator distress in
that run's log (a `Thread Performance Checker` priority-inversion warning
and an XCTest-runner auto-restart) — treated as environmental flake, not a
product bug.

**Decisions carried forward, not resolved this round:**
- **Device-only image blanks** (Will's original note 4): the gate is now
  proven identical to web's `hasImage` (see `docs/ui-changes.md`), and
  native `.image` items were never actually broken (screenshotted
  before/after) — but a device-specific cause for `.link` og-images still
  can't be fully ruled out from the simulator alone. If build 8 still shows
  blanks on Will's device, ask him for the id of one failing item to probe
  directly rather than re-guessing.
- **Onboarding tutorial redesign**: Will now wants a three-panel *swipeable*
  experience rather than the single static panel shipped this round. An
  HTML prototype is up for his review at
  `docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe.html`
  before that work starts.
- **Fixture-count drift**: the permanent `UITEST-FIXTURE` set on
  `will+uitest@dzierson.com` grew from 5 to 10 items over this round's
  several test-writing passes — noted for whoever next touches
  fixture-dependent tests; not itself a regression, just untracked growth
  worth an eventual cleanup pass.

Build 8's TestFlight outcome (upload id, processing state, beta-group
attachment, beta-review submission result) is recorded in a follow-up
amendment to this section once the pipeline finishes — see
`.superpowers/sdd/plan-12/task-5-report.md` for the full transcript.
