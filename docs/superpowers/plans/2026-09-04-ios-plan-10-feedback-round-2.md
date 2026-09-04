# Stash iOS Plan 10: Feedback Round 2 (gradient bug, composer height, detail polish, 1px strokes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the "animated white box" gradient rendering bug, cap the composer card at 2/3 screen height, unify the detail sheet's margins/heading-hairline/typography rhythm, enforce a 1px-stroke rule everywhere, and ship TestFlight build 4.

**Architecture:** The gradient gets a deterministic rendering path (pre-rendered blurred image, no per-frame blur, no `.drawingGroup()` — correctness on every OS/GPU beats the micro-optimization that likely caused the bug). The composer card gets a height cap with internal scrolling. The detail sheet gets one shared section-header component and one content-inset constant. The stroke rule lands in DESIGN.md and the four audited offenders.

**Tech Stack:** SwiftUI (iOS 17), XCUITest, release pipeline.

**Spec:** Will's 2026-09-04 notes (verbatim in Global Constraints) + `DESIGN.md` + the plan-9 outcome's open question (composer height — now answered: 2/3).

## Global Constraints

- **Will's notes (verbatim intent, 2026-09-04):** (1) gradient "showing up as an animated white box" behind login + Add tab — investigate; (2) "reduce the [composer] card size to 2/3 the height of the screen… people will be using the sharing intent to add things the majority of the time anyhow, but let's not make things challenging"; (3) "continue to refine the overall visual appeal… margins, padding, font sizing, line spacing (especially on the detail sheet) are still not quite right… margins being inconsistent on the detail sheet… heading underlines being inconsistently implemented"; (4) "never use a 2px stroke around a button or element. 1px stroke only."
- **Stroke rule:** all strokes = 1pt. Audited offenders: `ios/Stash/Auth/SignInView.swift:329` (focused 2), `ios/Stash/Detail/ItemDetailView.swift:242,259` (2), `ios/Stash/Design/StashDesign.swift:157` (composer ring stroke 1.5). The violet annotation BAR (2pt left bar) is a bar, not a stroke — unchanged. DESIGN.md gains the rule (dated) + amends the composer-ring bullet (stroke layer 1px; halo/shadow layers unchanged) + flags web's 1.5px ring stroke to follow.
- **Gradient bug hypothesis (verify empirically first):** plan-8's `.drawingGroup()` after `.blur(40)` in `AnimatedGradient` rasterizes per-environment; on some simulators/OS builds the rasterized layer renders empty → a white rectangle sliding with the offset animation. Our sims rendered fine (sweep screenshots), Will's did not — environment-dependent. FIX DIRECTION (regardless of exact root cause): render the blurred 2× gradient ONCE into a `UIImage` (UIGraphicsImageRenderer drawing the LinearGradient, then CI gaussian blur OR draw pre-blurred stops), display via `Image.resizable()`, optionally slow-pan with the existing reduced-motion-aware offset animation. Deterministic on every GPU. Palette unchanged (`StashColor.gradientStops`).
- **Composer card 2/3:** the card's height ≤ ⌊2/3 × container height⌋; editor content scrolls inside when it exceeds; gradient visible below the card; attachments row + bottom bar stay inside the card; keyboard avoidance unchanged; the ring/lift behavior unchanged. Decision recorded: capture-by-share-sheet is the primary flow, the in-app composer is secondary.
- **Detail sheet consistency:** ONE horizontal content inset for every section (use 20pt — the sheet's current dominant inset; audit and normalize); ONE `SectionHeader` component (micro-label text + hairline rule BELOW it, identical spacing above/below) used by NOTES & SUMMARY, DETAILS, SHARING — no ad-hoc `Divider()`s; line spacing per DESIGN.md body (≈1.5–1.55 via the existing MarkdownBlocksView defaults; plain-text blocks get the same `.lineSpacing` as markdown paragraphs); font-size audit: description `StashType.body()` muted, micro-labels 11 caps +0.11em faint everywhere (no stray sizes).
- **Stale-project note (docs):** `ios/Stash.xcodeproj` is generated and gitignored — after every pull, run `cd ios && xcodegen generate` before building in Xcode ("Cannot find 'StashType'"-style errors in the extension = stale project). Goes in `docs/RELEASING.md` + a new 5-line `ios/README.md`.
- Tokens only; no emoji. Identifier contracts: all existing `detail.*`, `capture.*` identifiers keep working; tests appended at END of `ios/StashUITests/StashUITests.swift`; single writer per file per round.
- Worktree `.claude/worktrees/ios-plan-10` (branch `worktree-ios-plan-10`, base = main `d3640a5`): commit there, never push; audit `origin/main` before merge. Sims `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` (primary) / `46D4EA93-94D5-451E-AC61-A5485AFB211F` / `E188DE28-5253-4BC5-8117-0EE87DF1B783` (+ **one NEWER-OS simulator if available** — `xcrun simctl list runtimes` — for the gradient repro) with distinct `-derivedDataPath` per parallel task; StashKit floor **341**; UI suite 22 with the standing 3 gate-blocked adjudications; builds warning-free.
- Deploy at wrap: `CURRENT_PROJECT_VERSION` → **4**; TestFlight has builds 1/2/3 (3 = plan-9 content, attached 2026-09-04); session auth; STOP if the Xcode session expired.

## File Structure

- `ios/Stash/Design/StashDesign.swift` (`AnimatedGradient` rebuilt on a pre-rendered image; ring stroke 1px), `DESIGN.md` (stroke rule; ring amendment; gradient impl note).
- `ios/Stash/Capture/ComposerCard.swift` + `CaptureComposerView.swift` (2/3 height cap + internal scroll).
- `ios/Stash/Detail/SectionHeader.swift` (NEW) + `ItemDetailView.swift`, `ItemDetailContent.swift`, `DetailsDrawer.swift`, `SharingSection.swift`, `NotesEditor.swift` (inset + header + spacing normalization; 1px strokes).
- `ios/Stash/Auth/SignInView.swift` (1px stroke).
- `ios/StashUITests/StashUITests.swift`; `docs/RELEASING.md`, `ios/README.md` (NEW), `docs/ui-changes.md`, this plan (outcome).

---

### Task 1: Gradient — reproduce, root-cause, and make rendering deterministic

**Files:**
- Modify: `ios/Stash/Design/StashDesign.swift` (`AnimatedGradient`), `DESIGN.md` (one-line iOS impl note under the page-wash bullet)

- [ ] **Step 1: Reproduce.** Build current main-equivalent and screenshot the sign-in + Add tab on ALL available simulator runtimes (`xcrun simctl list runtimes`; boot one sim per runtime incl. the newest). READ each screenshot: does any show the white box? Record which environments reproduce. Also try Release configuration on one sim (rasterization paths differ). If NO environment reproduces, note that honestly — the fix below ships anyway (deterministic > conditional).
- [ ] **Step 2: Root-cause probe (time-boxed).** On a reproducing environment (if found): remove `.drawingGroup()` only → rerender; remove `.blur` only → rerender. Record which change eliminates the box.
- [ ] **Step 3: Fix.** Rebuild `AnimatedGradient`: at layout time (`onAppear`/size change), render the 2×-canvas gradient + 40pt gaussian blur ONCE into a `UIImage` off the main render loop (`UIGraphicsImageRenderer` + `CGGradient`, then `CIGaussianBlur`, at ~1x scale — it's a blur, resolution is irrelevant); display via `Image(uiImage:).resizable().interpolation(.high)`; keep the slow offset drift (reduced-motion-aware) translating the IMAGE (cheap — no per-frame effects); `.clipped()`. No `.drawingGroup()`, no live `.blur`. Cache per size.
- [ ] **Step 4: Verify.** Screenshots of sign-in + Add on ≥3 runtimes (incl. the newest) → `task-1-gradient-<runtime>.png`; READ all: smooth purple-blue-pink wash, no white box, no banding. `testVisualSweepScreenshots` ×1 (light) still green. DESIGN.md page-wash bullet gains: "iOS renders the blurred sweep to a static image once per size (deterministic across GPUs); only the pan animates."
- [ ] **Step 5: Commit.** `fix(ios): gradient renders via a pre-blurred static image — kills the environment-dependent white-box rasterization bug`

---

### Task 2: Composer card capped at 2/3 screen height

**Files:**
- Modify: `ios/Stash/Capture/ComposerCard.swift`, `ios/Stash/Capture/CaptureComposerView.swift`

- [ ] **Step 1:** Card: `.frame(maxHeight: floor(geo.size.height * 2/3))` (GeometryReader at the tab level; exclude the keyboard-adjusted safe area from the calculation so the cap is stable), aligned top under the wordmark header; the editor becomes the flexible, internally-scrolling region (attachments + bottom bar pinned inside the card bottom); gradient visible below.
- [ ] **Step 2:** Screenshots: empty, long-draft (editor scrolls inside the card), keyboard-up, attachment present → `task-2-composer-*.png`; READ them (card ≈2/3, gradient below, ring intact, × un-clipped). Record the decision line in the outcome ("share sheet is the primary capture path — Will 2026-09-04").
- [ ] **Step 3:** Smokes: `testComposerKeyboardAccessory`, `testLibraryTypeChipAndComposerCard` (composer-card assertions), `testCaptureSmoke` pre-gate ×1. Commit: `feat(ios): composer card caps at 2/3 screen height; editor scrolls within`

---

### Task 3: Detail sheet — one inset, one header treatment, rhythm audit

**Files:**
- Create: `ios/Stash/Detail/SectionHeader.swift` (micro-label + hairline rule, fixed vertical rhythm: 24 above / 10 label-to-rule / 14 below — one place to tune)
- Modify: `ios/Stash/Detail/{ItemDetailView,ItemDetailContent,DetailsDrawer,SharingSection,NotesEditor}.swift`
- `xcodegen generate` (new file)

- [ ] **Step 1: Audit first, then normalize.** Grep every `.padding(.horizontal` in the five files; list the values found (expect a mix); normalize ALL section content to ONE inset constant (`DetailLayout.inset = 20`) applied at the scroll-content level, removing per-section horizontal paddings. Replace every section heading (NOTES & SUMMARY / NOTES & TRANSCRIPT, DETAILS, SHARING) + any ad-hoc `Divider()` with `SectionHeader(title:)`. The hairline rule spans the full content width — identically for all three.
- [ ] **Step 2: Rhythm.** Plain-text tab content gets the same `.lineSpacing` as MarkdownBlocksView paragraphs; description = `StashType.body()` + `.muted` + `lineSpacing` per DESIGN.md; verify title/description/URL-bar/tabs vertical gaps form a consistent scale (8/14/24 — pick from the existing dominant values, record in a `DetailLayout` enum). 1px strokes at `ItemDetailView.swift:242,259` (fold from the stroke rule).
- [ ] **Step 3:** Screenshots: link fixture + audio fixture sheets → `task-3-detail-*.png`; READ them against Will's complaint (aligned left edges everywhere; identical heading treatment ×3). Smokes: `testDetailSheetAnatomy`, `testEditSmoke`, `testPublicSmoke` ×1. Commit: `fix(ios): detail sheet — single content inset, shared SectionHeader with hairline, unified rhythm, 1px focus strokes`

---

### Task 4: 1px stroke rule — DESIGN.md + remaining offenders

**Files:**
- Modify: `DESIGN.md` (§Space/elevation: "Strokes are 1px, always — buttons, inputs, rings, tiles. Emphasis comes from color, not weight." dated; composer-ring bullet: stroke layer 1px, halo/shadow unchanged; note web's 1.5px ring stroke + 2px input focus rings should follow), `ios/Stash/Design/StashDesign.swift:157` (1.5 → 1), `ios/Stash/Auth/SignInView.swift:329` (2 → 1)
- (ItemDetailView's two are Task 3's.)

- [ ] **Step 1:** Apply; re-grep `lineWidth|border(.*width` across ios/ — assert zero values >1 remain (annotation bar exempt: it's a fill, verify it uses a Rectangle fill not a stroke). Screenshot sign-in focused input + composer active ring → `task-4-strokes.png` (READ: thin ring still clearly visible).
- [ ] **Step 2:** `testSignUpTabRenders` + `testDesignSystemFontsLoad` ×1. Commit: `fix(design): 1px stroke rule — DESIGN.md + composer ring + sign-in focus ring`

---

### Task 5: Wrap — docs, suites ×2, TestFlight build 4

- [ ] **Step 1:** `git fetch origin` + audit/merge; re-run suites after.
- [ ] **Step 2:** `swift test` (≥341); builds warning-free; `npm test`; UI suite ×2 (expect exactly the standing 3 gate-blocked failures; 22+ tests).
- [ ] **Step 3:** Docs: `docs/ui-changes.md` entry (gradient deterministic impl; composer 2/3 + "share sheet is primary capture" decision; detail sheet inset/header rhythm; 1px stroke rule — web follows for ring + input rings); `docs/RELEASING.md` + NEW `ios/README.md` (xcodegen-after-pull note, "Cannot find StashType" symptom); this plan's Outcome. Commit docs.
- [ ] **Step 4:** `CURRENT_PROJECT_VERSION: 4` → `xcodegen generate` → verify plists → commit → `./ios/scripts/release.sh all` → entitlement check → `upload` → poll VALID → attach to `d19f78c1-7af3-4461-9af6-1566200c251b` → record. STOP with the exact message if the session expired.

---

## Self-review notes
- **Coverage:** note 1→T1; 2→T2; 3→T3; 4→T4 (+T3's two); Xcode stale-project answer→T5 docs; build 4→T5.
- **Placeholders:** none; offender lines pre-audited; inset/rhythm values named with an audit-first instruction.
- **Type consistency:** `DetailLayout.inset`, `SectionHeader(title:)` defined in T3 and used only there; no cross-task interfaces beyond existing tokens.
- **Risks accepted:** the gradient bug may not reproduce on our runtimes (fix ships regardless — deterministic rendering is strictly safer); the 2/3 cap interacts with keyboard avoidance (screenshot-verified); heading-rhythm values chosen from the dominant existing scale, tunable in one file.
