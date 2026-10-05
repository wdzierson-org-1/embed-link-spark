# Stash iOS Plan 16: Ask keyboard fixes, HIG + accessibility pass, white-S icon

> **October 4 completion update:** The user approved a bounded stabilization pass and local
> integration. [Completion report](../../ios-plan-16-completion.md) is the current status source.
> The unfinished checkboxes and October 3 Outcome below are historical. The original open-ended
> review/fix rounds and two complete test passes have been replaced by the report's fixed
> acceptance set. TestFlight publishing remains a separate step.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the Ask tab's stuck keyboard / missing composer after picking a previous conversation, give Ask the same "Cancel" affordance as the Add tab, bring every control and text style up to Apple's Human Interface Guidelines and accessibility expectations (Dynamic Type, 44 pt targets, contrast), make the icon's S white on every surface, fix two visual bugs seen in Will's device screenshots, then ship TestFlight build 10.

**Architecture:** Round 1 runs three file-disjoint tasks in parallel (Ask keyboard; icon pipeline; detail title + View-tab search bar). Round 2 is the accessibility sweep: a foundation task that runs alone (type roles, tokens, shared controls, DESIGN.md), then two parallel surface passes on disjoint files (Detail + View; everything else). Then a whole-branch review, a fix wave, and the wrap (docs, suites, build 10 upload, TestFlight, App Store record).

**Tech Stack:** SwiftUI (iOS 17 floor, Will's phone on iOS 26), StashKit, XCUITest, `xcrun simctl ui … content_size` for Dynamic Type screenshots, `brand/build.mjs` (headless Chrome) for icons, `ios/scripts/release.sh` + `ios/scripts/asc-api.sh`.

**Spec:** Will's 2026-09-30 notes (verbatim below) + his five device screenshots + Apple Human Interface Guidelines (typography, layout, accessibility) + WCAG 2.2 AA contrast + DESIGN.md + `docs/ETHOS.md`.

## Global Constraints

- **Will's notes (verbatim, authorized):** "Navigating to ask tab > then previous conversations view > picking a conversation then back to the 'Ask' view causes the input area to disappear (see attached image where keyboard is shown but no input element is shown) and causes the keyboard to appear stuck in the on position. need a way to dismiss keyboard or minimize keyboard automatically when showing a previous conversation in the context of the Ask view (conversational / chat view)" · "When keyboard is shown and input is active while composing on Ask view, upper right should become 'cancel' (same as when composing on the home screen)" · "Some elements (cancel button in upper right while composing/inputting is a good example) appear smaller than iOS standard guidelines for on-screen elements. Please review iOS guidelines for all controls (buttons, cancel elements, navigation, text controls etc.) and be sure they meet standard guidelines and comply with accessibility standards (if user has increased text size at the OS level for readibility, etc.) The font sizes on the detail screen appear to be especially small, and should match the user's prefernces for accessibility/increased font sizing (if necessary)" · "let's update the color of the S on the icon to be white across the board (not just the iOS icon, but also the favicon)".
- **Also fixed (from Will's screenshots):** the detail sheet shows a raw UUID file name as an audio item's title (`f200ad94-…`) — the card-only title fallback must apply there too; the View tab's search bar gets half-covered by the first card while it hides on scroll.
- **Measured baseline (why text reads small):** `StashType.body()` is 14 pt, `meta()` 12, `chip()`/`microLabel()`/`kicker()` 11 (HIG default body is 17; footnote 13; caption 12; 11 is the floor). The Add tab's "Cancel" is 14 pt text with a hit area the size of the word; `CircleIcon` defaults to 40 pt (HIG minimum hit target 44×44 pt); `StashColor.faint` (#959ba6) is 2.79:1 on white (WCAG AA needs 4.5:1 for text) and is used for dates/meta.
- **Typography contract (Task 2 — iOS only; web keeps its desktop scale):** every `StashType` role maps to an iOS text style and scales with Dynamic Type via `Font.custom(_:size:relativeTo:)` (the fallback path must scale too). Default (Large) sizes follow HIG: reading text 17 (`.body`: detail description/notes/summary/transcript, chat bubbles + Ask composer, Add-tab editor, share-sheet note, search fields), secondary 15 (`.subheadline`: card descriptions/previews/notes, settings secondary lines), meta 13 (`.footnote`: dates, facts, footers, status lines), chips 12 (`.caption`), section micro-labels/kickers 12 (`.caption`, caps, tracking kept), text buttons 17 (`.body`: Cancel, primary text actions) and inline text actions ≥15; titles keep their sizes but scale (panel 28 `.title`, Ask title 22 `.title2`, card 20 `.title3`, display 32 `.largeTitle`). Record the table in DESIGN.md's iOS typography section.
- **Controls contract (Task 2):** every tappable element has a hit area ≥ 44×44 pt (visual size may stay smaller — expand via frame + `contentShape`); keyboard "Cancel" is ONE shared component (`StashCancelButton`, created in Task 1) at 17 pt, violet-600, ≥44 pt hit area, used by the Add tab, Ask, and the View-tab search; containers that hold text use `minHeight` (never a fixed height) so text can grow; screens that can overflow at large sizes scroll; at accessibility sizes, labels wrap instead of truncating critical text.
- **Contrast contract (Task 2):** text that carries information meets WCAG AA (≥ 4.5:1 normal, ≥ 3:1 large) on its actual background; `faint` is reserved for decorative/disabled elements; add a compliant token if `muted` isn't enough; honor Bold Text (the next heavier Neue Montreal face when `UIAccessibility.isBoldTextEnabled`) and keep VoiceOver labels on every icon-only control. Record rules in DESIGN.md (web can adopt the contrast fix).
- **Icon contract (Task 3):** the app icon's S is **white (#ffffff)** on the unchanged purple→blue wash, everywhere it's generated: `brand/icon-src.html` + `brand/build.mjs` (favicon.svg) are the only sources — run `node brand/build.mjs` to regenerate web favicons/PWA icons, Chrome-extension icons, iOS AppIcon (app + extension) and the onboarding tile. The "Stash" wordmark stays ink. The macOS app lives in another repo (note it for Will).
- **Keep:** look and feel otherwise (palette, layout, components), all accessibility identifiers (tests depend on them), DESIGN.md tokens, 1 px strokes, no emoji, light-only.
- **Process:** worktree `.claude/worktrees/ios-plan-16` based on LOCAL main (8db8a4db — local main is ahead of origin and other sessions commit to it; audit `git log` before the final merge). Single writer per file per round. Max 2 concurrent `xcodebuild` users; `swift test --package-path ios/StashKit --scratch-path /tmp/sk-<task>`. UI tests: EXPORTED `TEST_RUNNER_*` from `ios/.env.test.local` — the `will+uitest` account is now comped (subscription Active), so capture/Ask/share smokes should pass again; anything that still fails must be explained. Never print secrets; never push; commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task 1: Ask — keyboard never stuck, composer always reachable, "Cancel" while composing

**Files:** `ios/Stash/Ask/*`, `ios/Stash/Design/StashDesign.swift` (add `StashCancelButton` only), `ios/StashUITests/AskUITests.swift`.

- [ ] Reproduce on the iOS 26.5 sim and the iOS 17.5 sim: Ask → history → pick a conversation → back. Find the real cause (e.g. the conversations search field keeps first responder across the pop; the composer isn't lifted by keyboard avoidance) before changing code.
- [ ] Fix: opening a previous conversation (from history, the restore banner, or a citation) never leaves a keyboard up without a visible, focused input; the keyboard auto-dismisses when a previous conversation is shown; the composer is always visible above the keyboard whenever the keyboard is up.
- [ ] While `ask.input` is focused, the header's right side shows `StashCancelButton` (identifier `ask.dismissKeyboard`, label "Cancel") in place of the two circle buttons; tap = dismiss keyboard, keep the draft. `StashCancelButton`: 17 pt body style, violet-600, ≥ 44×44 hit area, `relativeTo: .body`.
- [ ] UI tests: history → pick → back ⇒ keyboard hidden and `ask.input` hittable; focus → Cancel visible, header buttons hidden → tap ⇒ keyboard hidden, text preserved. Run on 17.5 and once on 26.5.
- [ ] Commit `fix(ios): Ask keyboard — no stuck keyboard after picking a conversation, Cancel while composing`.

### Task 3: White S on every icon

**Files:** `brand/icon-src.html`, `brand/build.mjs`, all generated assets it writes, `extension/manifest.json` (patch version bump) + the hosted-zip refresh (`extension/scripts/publish-hosted-zip.sh` outputs), `DESIGN.md` (icon description).

- [ ] S fill → #ffffff in both sources; run `node brand/build.mjs`; READ the 1024 iOS icon, a 32 px favicon, and the 128 px extension icon to confirm legibility.
- [ ] Bump the extension's patch version (icons changed) and refresh the hosted zip + page stamps with the existing script.
- [ ] Commit `feat(brand): white S on every icon (iOS app + extension, favicons, PWA, Chrome extension)`.

### Task 4: Detail title fallback + View-tab search bar

**Files:** `ios/Stash/Detail/*`, `ios/Stash/Library/LibraryView.swift`, `ios/StashKit/Sources/StashKit/ItemDisplay.swift` (+ tests), `ios/StashUITests/StashUITests.swift` (only the tests it must adjust), a NEW `ios/StashUITests/LibraryDetailUITests.swift` for new tests.

- [ ] Detail title: when `ItemDisplay` says the stored title is a placeholder (UUID/timestamp object name), the title field starts EMPTY with the type label as placeholder text ("Voice note", "Photo", "Video", "File"); nothing is written unless the user types a title; server AI titles still replace it via realtime.
- [ ] Search bar: rebuild the hide-on-scroll so the pill scrolls away with the content (first element inside the scroll view, fading by its own position) — no clipping, no overlap with cards; keep every plan-12 keyboard behavior and identifier.
- [ ] Tests: detail placeholder title (unit + UI), search bar never overlaps the first card while visible (UI, frames), existing library/detail smokes green.
- [ ] Commit `fix(ios): placeholder titles show the type label in the detail sheet; search bar scrolls away cleanly`.

### Task 2: HIG + accessibility sweep (round 2, after round 1 is closed)

Split by the coordinator (2026-09-30) into a foundation task and two parallel, file-disjoint surface passes. The UI layer is ~12.5k lines; one serial sweep would have had to hold all of it at once. The contracts in Global Constraints bind all three.

#### Task 2a: Foundation (runs alone)

**Files:** `ios/Stash/Design/*` (`StashType`, `StashDesign`/`StashColor`, `PillTabs`, `CachedImage` untouched unless needed), `ios/Stash/StashApp.swift` (DEBUG launch hooks only), `DESIGN.md`, a NEW `ios/StashUITests/A11yScreenshotSupport.swift` (shared helpers for the screenshot matrix).

- [ ] `StashType` role API that scales with Dynamic Type: every role is `Font.custom(_:size:relativeTo:)` at the contract's default size, and the fallback scales too (e.g. the matching text style). Arbitrary-size helpers take `relativeTo:`, defaulting to the nearest text style for the size. `mono` scales. A clearly named non-scaling helper exists for DECORATIVE art only (miniature illustrations/plates that are `accessibilityHidden`). The old fixed-size helpers are marked `@available(*, deprecated, message:)` so the build's warnings become the surface passes' migration checklist; Task 5 deletes them.
- [ ] Bold Text: verify empirically whether SwiftUI emboldens the bundled custom faces under `legibilityWeight == .bold`. If it doesn't, ship the least-invasive mechanism that updates live (no root `.id` rebuild that would drop drafts or navigation). A DEBUG launch argument forces `legibilityWeight = .bold` for screenshots.
- [ ] `StashColor`: a WCAG-AA informational meta-text token, or a documented decision to use `muted`. Include a computed contrast table on the real backgrounds (white, page wash, chip bg, the type tints). `faint` is documented as decorative/disabled only.
- [ ] Shared controls reach ≥ 44×44 pt hit areas without moving their visuals (e.g. `CircleIcon`/`CircleSubmitIcon`, `PillTabs`). Prove it with a UI test that taps just outside the visual edge.
- [ ] DESIGN.md: the iOS typography table (role → pt → text style → where used), controls rules, contrast rules (with the table), Bold Text. The web keeps its own scale and can adopt the contrast fix.
- [ ] Commit `feat(ios): accessibility foundation — Dynamic Type type roles, AA meta token, 44 pt shared controls, Bold Text`.

#### Task 2b: Detail + View surfaces (parallel with 2c)

**Files:** `ios/Stash/Detail/*`, `ios/Stash/Library/*`, `ios/StashUITests/{StashUITests,DetailUITests,LibraryDetailUITests}.swift`, a NEW `ios/StashUITests/A11yDetailLibraryUITests.swift`.

#### Task 2c: Add, Settings, onboarding, sign-in, tab bar, share sheet (parallel with 2b/2d)

**Files:** `ios/Stash/{Capture,Settings,Onboarding,Auth}/*`, `ios/Stash/MainTabView.swift`, `ios/StashShareExtension/*`, `ios/StashUITests/{ComposerUITests,AccountUITests,SessionUITests,StoreScreenshotsUITests}.swift`, a NEW `ios/StashUITests/A11yAppUITests.swift`.

#### Task 2d: Ask (parallel with 2b/2c; split from 2c by the coordinator so it can fold in the Task 1b review)

**Files:** `ios/Stash/Ask/*`, `ios/StashUITests/AskUITests.swift`, a NEW `ios/StashUITests/A11yAskUITests.swift`.

Both surface passes do the following, in their own files only:
- [ ] Migrate every call site to a role; the build shows zero `StashType` deprecation warnings in their files. Detail reading text renders at 17. Replace every `.system(size:)` with a scaled equivalent, or with the decorative helper plus `accessibilityHidden`.
- [ ] Controls contract: 44 pt targets (audit list in the report). `StashCancelButton` adopted: the Add tab (2c) and the View-tab search (2b). Fixed text heights become `minHeight`; overflow scrolls; at accessibility sizes, rows that can't fit reflow (e.g. HStack→VStack) instead of truncating critical text.
- [ ] Contrast contract on informational text. VoiceOver labels on icon-only controls. Bold Text honoured.
- [ ] Screenshot matrix → `.superpowers/sdd/plan-16/a11y-<screen>-<size>.png` at Large, xxxLarge and accessibility-extra-large (AX3), plus Bold Text at Large. 2b covers View, detail (link + audio). 2c covers Add, Ask with an answer, Conversations, Settings, share sheet, onboarding, sign-in. READ every shot and fix clipping and overlap.
- [ ] Update the size-asserting tests in their own files. Their UI tests pass on iOS 17.5, and a smoke run passes on 26.5.
- [ ] Commit `feat(ios): HIG + accessibility pass — <surfaces>`.

### Task 5: Wrap + build 10

- [ ] Merge local `main` (audit foreign commits); `docs/ui-changes.md` entry "2026-09-30 · iOS accessibility pass, Ask keyboard, white-S icon (plan 16)"; DESIGN.md (typography table, controls, contrast, icon); plan Outcome.
- [ ] Suites ×2 (StashKit, npm, Debug + Release builds warning-free, full UI suite); boot-time API scan of the archive.
- [ ] `release.sh all` → upload build 10 → VALID → both TestFlight groups → App Store version `c5b26d42-dcd6-466f-abd4-d91d37cf6d59` → Beta App Review submission. No App Store review submission (Will's click).

## Outcome

**Status (2026-10-03, written at `5a5ac4d1`; Task 1d's first commit `ece068c9` landed meanwhile).**
Everything except Task 1d is committed and has been
reviewed; four things are still open and each has a `TODO(wrap)` slot at the end: Task 1d (Ask
thread follow-ups, running), the batch B fix round (its review said NEEDS FIXES, one item), the
whole-branch review with its fix wave, and the release (suites, build 10, App Store
screenshots). The history, with every ruling, is the ledger
`.superpowers/sdd/plan-16/progress.md`; each task's report and review sit beside it.

**Commits and review outcomes** (branch `worktree-ios-plan-16`, base `8db8a4db` = local `main`,
not pushed). Task 2 was split into 2a / 2b / 2c / 2d, and the reviews opened follow-up tasks
(1b–1d, 4c–4e, 2bf, batch B, a polish batch), listed under the plan task they belong to.

- **Task 1 — Ask keyboard.** `41c15e1b`, fix wave `23384f1e`. No stuck keyboard after picking a
  conversation (iOS 26.5 hands the keyboard back to the composer when the stack pops, and
  keyboard avoidance misses it); Cancel while composing (`ask.dismissKeyboard`, the shared
  `StashCancelButton`); the keyboard is put away before History, the restore banner and
  citations. Fix wave: citation focus race, a keyboard-up streaming test. Review: APPROVED WITH
  NITS; its N3 (three Save-Password handlers) is still open.
- **Task 1b — Ask thread blank after a far jump.** `fb9f5aca`. New in-plan bug found while
  testing (iOS 17.5 and 18.5 blank, 26.5 hang): the lazy thread's unbuilt rows are estimated and
  every jump to the end aimed at an estimate. Fix: a non-lazy tail after the lazy history and one
  `scrollToEnd` primitive. Review: CHANGES REQUIRED (small; the design was approved) → Task 1c.
- **Task 1c — Ask thread structure.** `7e1a69d6` (StashKit `ChatThreadTail`, 17 tests),
  `3cc763d3`. Near sends don't shed; the tail is sized by height and bounded while following,
  through one UIKit hold; two more bugs fixed on the way (the keyboard coming up while reading the
  last answer dropped the line by 816 pt on 18.5 / 26.5; a composer tap at the end of a long
  thread left it about 2,640 pt short on 26.5). Review: APPROVED WITH NITS, with one Important
  report correction on perf (see Corrections).
- **Task 1d — Ask thread follow-ups.** Running. Its first commit, `ece068c9` (2026-10-03 12:03), is a
  pure move: the thread's scroll machinery goes verbatim into `AskThreadScrolling.swift` (the 2d
  review's M-6; `AskView.swift` 1,945 → 1,188 lines, no logic change, proved by one build and
  `AskUITests` on iOS 17.5: 14 run, 13 passed, 1 skipped by design). The rest is in its `TODO(wrap)`
  slot.
- **Task 3 — white S.** `e43ca44b` (22 files: both brand sources, the 15 regenerated assets,
  extension 1.2.0 → 1.2.1 with the hosted zip) and `c2d591ca` (store docs name 1.2.1). Pixel
  checks: centred, no halo, white against the wash at least 3.44:1. Review: none filed; the
  coordinator read the 1024 icon and closed it.
- **Task 4 — detail title fallback and View search pill.** `8588907c`, fix wave `8436c46e`. A
  placeholder title opens the detail sheet empty with the type label; the pill is one scroll view
  that scrolls away, snaps, and scrims the status bar; a clear after a typed title now sticks
  (StashKit `DetailFieldEdits`); an empty media title reads as its type. Review: CHANGES REQUIRED
  (I-1: a clear after a sent title didn't stick) → fixed → re-review APPROVED WITH NITS.
- **Task 4c — edit-queue data safety.** `9b63316b`, `0364eea0`. A queue confirm never drops a later
  equal value; description and sticky note read the queue like the title; a failed un-share
  restores the note; plain notes get a draft check. Review: CHANGES REQUIRED (F1: a failed
  un-share's re-queue could resurrect a note over a closed sheet's clear; pre-existing P-3 and
  P-4) → Task 4d.
- **Task 4d — share privacy, last value wins, title Return, AX footer.** `353b8e8c`. Review:
  CHANGES REQUIRED (A-1 and A-3 privacy, A-2 data, B-1 to B-4) → Task 4e.
- **Task 4e — sharing never publishes against the last thing the user saw; a delivered note is
  never appended twice.** `aad20e17`, fix round 1 `a0793f97`, fix round 2 `634b270a`. Reviews:
  NEEDS FIXES (C-1: a citation sheet could overwrite a rich note) → round 1 re-review: findings
  remain open (M-4) → round 2 re-review: all addressed, three new minors → batch B.
- **Batch B — a rich note leaves the box once the sheet shows it; the empty-search pane follows
  the keyboard down.** `5a5ac4d1`. The three round-2 minors, plus the iOS 17.0 pane bug that a
  real keyboard exposed. Review: NEEDS FIXES, one item (I-1: "Couldn't save — try again." stays
  up after the note it reports is on the server) and four minors; fix round 1 is running.
- **Task 2a — accessibility foundation.** `53b995de`, fix wave `1f01207d`. Type roles and Bold
  Text, the AA `muted` and `violet700` tokens, `StashCancelButton`, 44 pt targets, the type
  specimen and the screenshot support. Review: CHANGES REQUIRED (C1: the Bold Text hook stopped at
  the first hosting controller; I1 to I4) → fix wave; the fix wave was not re-reviewed on its own.
- **Task 2b — detail sheet and View tab.** `b8324128`, `f60a7b3e`; fix wave 2bf `6b9d0201`,
  `8188e2fd`; follow-up `7bb5ce22`. The 2bf wave added the leading taper, the link underline, the
  AX URL cap and the busy-action contrast. Reviews: CHANGES REQUIRED for I-1 only (title Return,
  fixed in 4d) and minors → 2bf; 2bf APPROVED (0 Critical, 0 Important, 7 minors) → follow-up (one
  shared 80 % underline, busy actions as one control, scheme-less AX URLs); re-review: all 8
  addressed.
- **Task 2c — Add, Settings, onboarding, sign-in, share sheet.** `e3dbe3cc`, `bbc5ae3c` (step-3
  art), fix round `d4d2d20c`. Review: CHANGES REQUIRED for I-1 only (the onboarding card filled
  the screen) → fixed; re-review: all addressed.
- **Task 2d — Ask accessibility pass.** `381964cd`, fix round `99242cc9`. Review: NEEDS FIXES (C-1:
  a status-bar tap mid-answer could freeze the app on iOS 26.5) → the status-bar tap is now the
  thread's own cut, links in answers use the shared underline; re-review: C-1's code addressed, R-1
  (report claims about the stall) corrected by the coordinator, four minors carried to Task 1d.
- **Polish batch.** `44859e0b`, `0b6df704`. Skip and the attachment × take their taps, the
  `--uitest-tab-*` hooks are DEBUG-only, an accessibility audit that never finishes ends as a
  visible skip. Review: NEEDS FIXES (I-1: a sibling audit helper still passed silently) → fixed;
  re-review: all addressed.
- **Plan and docs.** `c82fa97c` (the plan), `e5a9ebba` (Task 2 split), `2ed9e1c3` (2d split),
  `c2d591ca` (extension store docs), and this wrap's docs commits.

**Totals so far** (at `5a5ac4d1`; Task 1d's uncommitted work is not counted).
- 33 commits since the base: 8 `feat`, 21 `fix`, 4 `docs`, plus the wrap's docs.
- 95 files changed, +17,693 / −1,481 lines: `ios/Stash` 44 files (+5,805 / −1,258), `ios/StashKit` 13
  (+3,962 / −30), `ios/StashUITests` 13 (+7,330 / −135), the share extension 2, `ios/scripts` 1,
  `ios/README.md` 1, DESIGN.md (+230 / −12), and the regenerated brand, extension and public assets.
- 122 test functions added in StashKit's tests and 79 in the UI suites (counted as added
  `func test…` lines in the diff; a rename counts once as an addition). StashKit is 845 / 845
  at `5a5ac4d1`.
- 21 review and re-review documents and 17 task reports in `.superpowers/sdd/plan-16/`, with about
  620 screenshots.
- Not yet run: the wrap's two full-suite passes (below).

**Rulings** (every `Ruling:` line in the ledger, condensed, in ledger order; *cost* is the ledger's
cost-if-wrong).
1. Relaunch fresh agents for 2d, 2bf, T4e and the 2c review from the recovered briefs: the dead
   agents belonged to another session and couldn't be resumed, and Will's request authorized
   finishing the plan. *Cost:* duplicated verification time only.
2. At most 3 live agents and 2 `xcodebuild` users (the last run died with 4 live opus agents).
   *Cost:* slower wall-clock, for a lower risk of another session-limit death mid-edit.
3. Fold 2c's M-1 to M-5 and N-1 to N-4 into the I-1 fix round; only I-1 and new breakage gate the
   re-review. *Cost:* a larger fix diff to re-review.
4. The outbox badge reverts to the pre-2c orange with ink digits (about 6.9:1): Will's "leave look
   and feel alone otherwise", and violet wasn't contrast-required. *Cost:* one colour flip if Will
   prefers violet.
5. The partial-save toast glyph is warning amber (3:1 or better on paper, `#7a4b00`), not
   destructive red, which keeps meaning "refused". *Cost:* one colour literal.
6. The opaque iOS 26 delete sheet stays; the fix round shoots it at Large for Will. *Cost:* Will
   asks for the glass sheet back (its contrast is then unprovable).
7. Apply the A11yFoundation leading patch in the 2bf follow-up (the direct consequence of 2bf's own
   taper; 2a was closed). *Cost:* none (test-only, proven in an export).
8. The link underline must clear 3:1 non-text contrast (SC 1.4.11): one shared Design-level style
   at violet-600 **0.75** alpha. **Superseded by ruling 10.** *Cost:* a slightly more visible
   underline.
9. The 2c fix round owns `ios/Stash/Capture/CaptureTestHooks.swift`, so its two DEBUG hooks live
   where the codebase keeps test hooks. *Cost:* none.
10. The link underline is ONE Design-level style, violet-600 at **80 %** alpha (3.52:1 on white,
    3.26:1 on `#F2F2F7`: 75 % was 2.99:1 on Ask's bubble), defined in `StashDesign.swift`, used by
    `MarkdownBlocksView` and then Ask; the pixel check retuned; DESIGN.md and the docs restated.
    *Cost:* a slightly darker underline.
11. The busy inline action is one `Button` with one `ButtonStyle` for idle and busy (the reviewer's
    fix), or VoiceOver users lose focus. *Cost:* none visible.
12. Revert N-6's one line: the rich note goes back to its pre-2bf leading (Will's "keep the look");
    per-block rich-note rendering is deferred. *Cost:* rich notes a touch tighter than plain notes.
13. At AX sizes show the URL without its scheme (the VoiceOver label and the long press keep it
    whole); zero-width breaks in the preview string; log the janitor's stale-row count including
    0; doc and report fixes; shot-only coverage accepted. *Cost:* trivial.
14. Fold T4e's M-1 to M-4 into C-1's fix round (they close "last typed wins" and "honest errors"
    gaps the plan's rules name). *Cost:* a larger fix diff.
15. Parked: a citation sheet's revert after a foreign flush is never sent (pre-existing, Ask
    citation sheets only); real and deferred, not widening a subtle queue change right before build
    10; the final review triages. *Cost:* in that sequence the server keeps the value the user
    reverted away from (visible on reopen, re-editable).
16. Stop 2d's D22 investigation after the current run (the 26.5 precondition flake sits on M-3,
    Task 1d's scope); 2d re-verifies, commits and hands Task 1d the underline retune, the two
    `StashUITests` fixes and the flake. *Cost:* the flake waits one task longer.
17. Accept no "Saving…" at AX4 and AX5: errors still surface, the footer stays still, and a
    reserved line would re-add the height B-3 removed. *Cost:* AX4 / AX5 users lose a transient
    progress cue.
18. Run the already-ruled non-Ask deferred minors now as a polish batch on the idle slot (18.5
    search focus, Skip at 44 pt, the attachment × on iOS 17, a visible audit timeout, DEBUG-only
    `--uitest-tab-*`, the ⌘. keyboard poisoning). *Cost:* the final review sees them done rather
    than triaging them.
19. The refusal toast no longer tap-dismisses at AX sizes: accepted (it auto-dismisses after 3 s and
    the tap-through keeps the circles usable). *Cost:* a refusal can't be tapped away early at AX
    sizes.
20. 2d's C-1: structural fix first (a foreign scroll heading for the top cuts, non-animated, to the
    content top); pass = 0 stalls in 24 iterations on 26.5 and no main-thread gap over 250 ms;
    fallback = restore HEAD's pull-back for streaming foreign scrolls (keeping VoiceOver's half of
    M-6). *Cost:* status-bar taps mid-answer get pulled back to the end (pre-plan-16 behaviour).
21. 2d's fix round goes to a fresh opus agent (the original implementer's context was about 965k
    tokens). *Cost:* re-reading time.
22. Scope split: 2d fix round 1 takes C-1, I-1, I-3, both `StashUITests` Ask patches, M-1 to M-4
    and M-5's AX5 shot; Task 1d takes I-2, the 1c leftovers, the file split, the shared URL / anon
    helper and V5's cost. *Cost:* none (sequential, same files).
23. T4e's fix round 2 includes the overlapping rich-note-save duplication (it violates "a rich note
    is delivered exactly once" in 4e's own bookkeeping) and the M-2 side effect. *Cost:* a longer
    round.
24. Accept the Skip "Contrast failed" audit flag as a false positive (measured 5.38:1) rather than
    revert to the 42.3 pt target: the 44 pt contract outranks an audit heuristic. *Cost:* one noisy
    audit line at Large / Large-bold.
25. Leave `44859e0b`'s Sonnet trailer (accurate for the agent that wrote it). *Cost:* none.
26. The round-2 duplicated-note regression is MUST-FIX before build 10 but goes to a fresh agent,
    not a T4e round 3 (T4e's context was about 0.96 M tokens). *Cost:* the final fixer re-learns the
    edit queue.
27. Run the known non-Ask MUST-FIX items now as batch B (the duplicated rich note, the carry test,
    the rule-text corrections, the 17.0 "No matches" pane). *Cost:* the final review sees them done
    rather than triaging them.
28. Close the 2d review's R-1 by appending the re-review's correction to `task-2d-report.md`
    instead of resuming a roughly 0.7 M-token agent for a doc edit. *Cost:* none.
29. Task 1d Q1: also shed once a send-from-inside-the-tail's jump has landed at the end (end-held,
    never before the jump). *Cost:* a visible shed right after a far send.
30. Task 1d Q2: a DEBUG tail marker and one UI test as M-2's permanent proof, absent from Release.
    *Cost:* +1.5 min per class run.
31. Task 1d Q3: if I-2 won't reproduce, pass = 0 of 24 on 26.5 plus far-send stress runs on 26.5 and
    18.5 measuring zero end-versus-last-row gap plus new failure diagnostics, stated plainly as "not
    reproduced". *Cost:* a rare defect ships with good diagnostics.
32. Task 1d gets both build slots for phase 2. *Cost:* machine load (2 sims at most).
33. Start the wrap's docs now with `TODO(wrap)` slots for Task 1d, the final review and the
    release. *Cost:* one more pass to fill the TODOs.

**Parked residuals and deferred minors, still open.**
- *Edit queue and detail sheet.*
  - Ask citation sheets: a revert after a flush the sheet never saw is never sent (ruling 15).
  - By design, and written into the rule text: a citation sheet can show Private while the item is
    still public until the next flush; a failed share can stay on with no error for about one round
    trip while the item is private (nothing publishes it); a share in flight is lost if the app is
    killed (the item stays private).
  - Batch B's I-1 (the stale "Couldn't save — try again." caption) and its minors m-1 to m-4: the
    fix round is running.
  - Pre-existing: a failed un-share whose note matches neither the server nor the queue isn't
    restored; with a hardware keyboard the search bar keeps focus on a drag, so the snap can move a
    focused row out (rare). A draft whose document the sheet never shows stays in the note ledger
    until the sheet closes (no behaviour cost). Rich notes are set solid (a touch tighter than plain
    notes) until per-block rendering.
- *Accessibility and UI.*
  - The two long "Saved…" toasts that open the library take taps over the bottom-bar circles at AX
    sizes for 3 s; the refusal toast no longer tap-dismisses at AX sizes (ruling 19); the AX5 phone
    add-field placeholder renders small (pre-existing).
  - The tile's file name is capped at xxxLarge in its 64 pt tile, and `CollectionStrip`'s 9 pt names
    are pictures of text (legacy type): accepted.
  - The accessibility audit on iOS 26.5 hangs at one scroll position (Details at xxxLarge); the
    tests now end that case as an UNVERIFIED skip naming the screen, and a matrix on 26.5 may hit it
    again.
  - 2bf: the idle `InlineActionStyle` overhang and its 0.4 press dim are untested (the 0.4 is a
    guess); the URL preview and the N-4 to N-6 fixes are covered by screenshots only.
- *Ask thread.* Per-answer perf at answers 3 to 5 (see Corrections). Task 1d owns: the 2d re-review's
  four minors; Voice Control, Full Keyboard Access and hardware-keyboard scrolls that can still
  animate across the lazy history unheld; the 18.5 run that 2d's fix round didn't make; the 17.5
  `A11yAskUITests` class, which has never run green as one run (audit timeouts at load 17 to 36;
  every test passed on the final code). VoiceOver's animated scrolls keep a small absorption race
  (an end hold between a scroll's start and its first frame), and iOS 17.0 to 17.3 have no
  animated-scroll flag at all. The stall's root cause is SwiftUI's lazy-stack placement looping
  with no app code on the stack; the structural fix closes the status-bar path only.
- *Tests and tooling.*
  - `testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel` uses `typeKey`, which makes iOS write
    `AutomaticMinimizationEnabled` into the simulator, so the keyboard is parked off screen from the
    next boot (a reboot doesn't restore it; `xcrun simctl spawn <udid> defaults delete
    com.apple.keyboard.preferences AutomaticMinimizationEnabled` does). The test passes on an
    affected simulator, and its intermittent failure on iOS 17.2 (also on pure HEAD) is unexplained.
    Consider making it restore the software-keyboard state.
  - Every simulator that ever ran that test may carry the flag, so earlier keyboard-dependent passes
    on it may be vacuous: clear it on every simulator before the full-suite runs, and the final
    review should weigh keyboard claims made on flagged ones.
  - Polish minors: `⌘A` callers (`testEditSmoke`'s title clear, `A11yDetailLibraryUITests.openDetail`)
    unmeasured; no multi-chip or trailing-edge test for the attachment ×; the Release hook check is
    a `/tmp` script, not a committed test; two comment nits at `A11yAppUITests.swift:911-913` and
    `:959`; `testShareComposeScreenshot` (host-run, token-gated) hasn't run since the audit change.
  - Task 1's N3: three Save-Password handlers remain (`A11yScreenshotSupport`, `SessionUITests`,
    `AskUITests`).
  - The 16 deprecated pre-plan-16 `StashType` helpers are still defined with no call sites left; the
    plan's Task 5 deletes them, and DESIGN.md's "their build warnings are the migration list" goes
    with them.
  - Stale comments that the reviews and this wrap found, not edited (the wrap was limited to two
    comments): `StashDesign.swift:133` (the underline is "for Ask's answers next") and `:50` (the
    `success` doc's "Ask's saved-chip", gone since plan 15), `StashCancelButton`'s doc (its "moves
    nothing" is true at the default size only), `ChatBubble.swift:585` ("CSS line-height 1.35",
    should be ≈ 1.55) and `ItemDetailView.swift:474` (`DESIGN.md "~1.55"`, should be ≈ 1.75, and
    ≈ 1.55 at AX sizes).
- *Store.* The Chrome Web Store submission (B13) is still pending; the extension store screenshots 02
  and 04 show older art (optional).

**Corrections owed to Will.** The coordinator told Will that the Ask thread's worst case was "within
6 dropped frames of the original". That compared peaks. Per answer, at answers 3 to 5, Task 1c drops
8 / 17 / 12 more frames than the code before Task 1b on iOS 17.5 / 18.5 / 26.5 (the 1b review's bar
was within about 10), though far fewer than 1b's +20 to +35, which kept climbing. The plateau is
real. The device check V4 decides whether it hitches; Task 1d re-measures with the final 17 pt type.

**Device checks for Will** (these need a device and a person: XCUITest can't drive VoiceOver, and the
iOS 26.5 Simulator refuses the app's VoiceOver focus requests).
1. *VoiceOver focus on busy inline actions* (2bf m1; N-2 too). Open a link item with no summary,
   swipe to "Generate summary, button" and double-tap: the cursor stays on that control and reads
   "Generating summary…, dimmed, button" (at once, or after a swipe away and back), and doesn't jump
   to the top or the next element. Repeat with "Transcribe again" on an audio item with a stored
   file. Then open the rotor on Headings: DETAILS should be listed with the other sections.
2. *Close-button order* (4d N-9; `.accessibilitySortPriority(1)` is applied but XCUITest's order is
   unchanged). Open a link card's detail sheet: VoiceOver's first stop should be "Close, button" or
   the eyebrow / title, never "Delete item"; swiping to the end should go Close → eyebrow → Title →
   Description → URL bar → tabs → content → DETAILS → SHARING → Delete item → caption. Read All
   should match, and touching the top-right corner says "Close, button". Repeat on an Ask citation
   sheet and at AX3, where the footer shows Delete only. If Delete comes before the content, add
   `.accessibilitySortPriority(-1)` to the footer or an explicit container.
3. *VoiceOver on the Ask thread (V4 / V5).* On the long-thread fixture with VoiceOver on, scroll to
   the top and swipe right: focus must reach "Long question 2", "3" and so on in order before "Long
   question 8"; from the first tail row, swipe left: focus lands on the last history row. Also
   confirm focus goes to the last answer after Cancel (Ask) and back to the editor (Add). With
   VoiceOver on, every row is laid out, so watch a followed answer for hitches.
4. *The VoiceOver focus moves the iOS 26.5 Simulator refused* (2b; R-5). On an iOS 26 device with
   VoiceOver on, scroll the View tab down, focus card 0 and swipe left: the search field
   should be read and its row come back whole. Then focus the search field, type, and activate Cancel
   (and, separately, the ×): the cursor stays on the field. If it fails, observe
   `UIAccessibility.elementFocusedNotification` for `library.search`.
5. *Animation Hitches (V4).* On iOS 26, in a real long conversation scroll up three screens and send:
   it must land and follow. Tap the composer at the end of a long conversation. Then ask five
   follow-ups at the end under Instruments' "Animation Hitches" template.
6. *Title Return and input methods* (4d I-1, by hand). "Teh" + done gives "The" and the keyboard
   hides; Japanese romaji with Return twice ends editing with no newline; a Korean syllable + Return
   ends editing; dictating "groceries new line milk" gives "groceries milk"; pasting "a⏎b" gives "a b"
   and shake-to-undo removes the paste cleanly; with a hardware keyboard, Shift-arrow to select a
   word then Return leaves the title unchanged and ends editing.
7. *The empty-search pane on iOS 26* (batch B m-4). Does it move with the keyboard's animation or
   snap after it? If it snaps, animate the height write or keep `containerRelativeFrame` where it is
   correct.
8. *Feel.* The 0.4 press opacity on the inline actions is a guess. Reduce Motion in Ask (the near
   send cuts, the cursor is static) is verified by reading only.

**Server issues for Will** (not iOS bugs; fixes need edge-function deploys).
- `transcribe-audio` (`supabase/functions/transcribe-audio/index.ts:368-397`) re-reads the title,
  runs its LLM calls (seconds), then writes `title` and `description` unconditionally (`patchItem`
  at `:249`): a title typed in that window is overwritten, and a fresh voice note now shows an
  inviting empty title. Fix: guard the title write on the value that was read.
- `add-url`: four link rows created by plan-15 share UI tests on 2026-09-30 at 14:41 UTC
  (`http://example.com/?p15t4=…`) store the description "T h i s d o m a i n i s …" (letters
  space-joined, word spaces dropped: the signature of JS `.split(/\s*/).join(' ')`). Real links with
  an og:description are fine, so it is probably the no-og:description fallback path. `add-url` v72
  was deployed 2026-09-30 09:46 UTC and is not in local `main`: production drift.
- `chat-with-all-content` (`index.ts:274`, and the model's context line at `:425`) sends the literal
  "Untitled" for an empty title, so Ask's source chips read "Untitled" for a cleared voice note while
  the card reads "Voice note", and a fresh voice note's chip shows its object name. Fix: send the raw
  title (null when empty) and use a type label in the model's context.

**Look changes to confirm with Will** (what is visible; "required" means a contract forced it).
- *The link underline* (violet-600 at 80 %, on summaries and in Ask answers): required for WCAG
  1.4.1, but a visible change; the coordinator decided it and Will can veto it.
- *The toast pill* on the Add tab (paper, intent glyph, ink text): required in substance (white on
  `success` is 3.39:1, on orange 2.20); the partial-save glyph is amber.
- *The opaque iOS 26 delete sheet*: contrast-motivated. Look at `a11y-2cf-ios26-settings-delete-L.png`
  and its `-before` pair in `.superpowers/sdd/plan-16/`.
- *The outbox badge*: kept the old orange with ink digits (ruling 4); violet-600 also passes AA if
  Will prefers it.
- *The step-3 onboarding art*: re-shot at native resolution, showing today's share card.
- *The gradient wash strength.* Not changed in plan 16. `AnimatedGradient` / `GradientBackdrop` apply
  their opacity per tier without a `compositingGroup`, so the wash renders at about 51 % on the View
  tab and 39 % on the Add tab instead of 30 % / 22 %: darker than web. Fixing it is a visible look
  change, so it is Will's call.
- *Smaller*: the Cancel paper capsule on the wash (violet on the wash is 2.8 to 3.3:1); the status-bar
  scrim, a white band over the wash once content scrolls under it; the search pill snapping to rest
  or out; pill tabs stopping at xxxLarge (the Large Content Viewer beyond); the resting Add header
  25 pt taller at AX3; the gap under the last Ask bubble 19 → 14 pt; and, required and kept: reading
  text 14 → 17 and the other size changes, the voice-recorder buttons, darker Settings captions and
  red, bigger legal links and Forgot password.

**`TODO(wrap)` slots** (open at the time of writing; fill in when each lands).
- **TODO(wrap) — Task 1d.** Ask thread follow-ups: commits, review, the per-OS perf table (before
  1b / 1c / 2d / 1d, answers 1 and 3 to 5), the I-2 outcome (fixed, or "not reproduced" with the
  diagnostics), V-b / V-d / V-c, V5's cost, and the unheld Voice Control / Full Keyboard Access
  paths. Besides the pure-move commit `ece068c9`, phase 1's shed rule in StashKit (853 / 853 on the
  live tree) and the rest were uncommitted at the time of writing. Also fill the `TODO(wrap)` in the
  `docs/ui-changes.md` entry.
- **TODO(wrap) — batch B fix round 1 and its review** (I-1 plus the folded minors): outcome and
  commit; if it ships, delete the "known gap" bullet in the ui-changes entry.
- **TODO(wrap) — the whole-branch review and fix wave.** Findings, fix commits, and which of the
  residuals above it triages in or out (the ledger's final-fix-wave list was already closed by the
  polish batch, 2d's fix round and batch B).
- **TODO(wrap) — suites ×2.** `swift test` for StashKit, `npm test`, the Debug and Release builds
  warning-free, and the full UI suite, twice. Clear `AutomaticMinimizationEnabled` on every
  simulator first, run the ⌘. test last and alone (`-skip-testing:StashUITests/A11yFoundationUITests/testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel`
  in the full run), pass `-collect-test-diagnostics never`, and scan the archive for boot-time APIs.
- **TODO(wrap) — merge.** Merge local `main` (audit foreign commits first; base `8db8a4db`).
- **TODO(wrap) — build 10.** `release.sh all` → upload build 10 → VALID → both TestFlight groups →
  App Store version `c5b26d42-dcd6-466f-abd4-d91d37cf6d59` → Beta App Review submission. No App
  Store review submission (Will's click). Delete the deprecated `StashType` helpers first.
- **TODO(wrap) — App Store screenshots.** All six 1.0 screenshots are stale (the logo refresh, then
  plan 16's typography and icon); re-shoot them (the extension store screenshots 02 and 04 are
  optional). The accounts can sign in: `will+review` and `will+uitest` are ACTIVE (checked
  2026-10-01 00:16Z and 2026-10-03 07:40Z), `will+lapsed` is the paused fixture.
