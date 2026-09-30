# Stash iOS Plan 16: Ask keyboard fixes, HIG + accessibility pass, white-S icon

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the Ask tab's stuck keyboard / missing composer after picking a previous conversation, give Ask the same "Cancel" affordance as the Add tab, bring every control and text style up to Apple's Human Interface Guidelines and accessibility expectations (Dynamic Type, 44 pt targets, contrast), make the icon's S white on every surface, fix two visual bugs seen in Will's device screenshots, then ship TestFlight build 10.

**Architecture:** Round 1 runs three file-disjoint tasks in parallel (Ask keyboard; icon pipeline; detail title + View-tab search bar). Round 2 is one cross-cutting accessibility sweep that owns every UI file (it must run alone). Then a whole-branch review, a fix wave, and the wrap (docs, suites, build 10 upload, TestFlight, App Store record).

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

### Task 2: HIG + accessibility sweep (runs alone, after round 1)

**Files:** every UI file in `ios/Stash/**` and `ios/StashShareExtension/**`, `ios/Stash/Design/*`, `DESIGN.md`, UI tests that assert sizes.

- [ ] Typography contract (table above) in `StashType`, applied through every call site; detail sheet reading text at 17.
- [ ] Controls contract: 44 pt targets everywhere (audit list in the report), `StashCancelButton` adopted by the Add tab and View-tab search, fixed heights → `minHeight`, overflow scrolls.
- [ ] Contrast contract + Bold Text + VoiceOver labels.
- [ ] Screenshot matrix → `.superpowers/sdd/plan-16/a11y-<screen>-<size>.png` for Add, View, detail (link + audio), Ask (with an answer), Settings, share sheet, onboarding at Large (default), xxxLarge, and accessibility3; READ them all; fix clipping/overlap.
- [ ] All suites green (update size-asserting tests to the new contract).
- [ ] Commit(s) `feat(ios): HIG + accessibility pass — Dynamic Type everywhere, 44 pt targets, WCAG AA text contrast, Bold Text`.

### Task 5: Wrap + build 10

- [ ] Merge local `main` (audit foreign commits); `docs/ui-changes.md` entry "2026-09-30 · iOS accessibility pass, Ask keyboard, white-S icon (plan 16)"; DESIGN.md (typography table, controls, contrast, icon); plan Outcome.
- [ ] Suites ×2 (StashKit, npm, Debug + Release builds warning-free, full UI suite); boot-time API scan of the archive.
- [ ] `release.sh all` → upload build 10 → VALID → both TestFlight groups → App Store version `c5b26d42-dcd6-466f-abd4-d91d37cf6d59` → Beta App Review submission. No App Store review submission (Will's click).
