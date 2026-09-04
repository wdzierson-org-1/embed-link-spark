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

---

## Outcome (2026-09-04)

**Commit range:** `d3640a5..HEAD` (base = `main` at plan authoring time; `origin/main` audited at
wrap — empty diff, nothing to merge).

| Commit | Task | Message |
|---|---|---|
| `7dbfd07` | — | docs(ios): plan 10 — feedback round 2 (gradient bug, composer 2/3, detail polish, 1px strokes) |
| `01af881` | T2 | feat(ios): composer card caps at 2/3 screen height; editor scrolls within |
| `4dacafa` | T3 | fix(ios): detail sheet — single content inset, shared SectionHeader with hairline, unified rhythm, 1px focus strokes |
| `9d6048a` | T1 | fix(ios): gradient renders via a pre-blurred static image — kills the environment-dependent white-box rasterization bug |
| `d8ab50c` | T4 | fix(design): 1px stroke rule — DESIGN.md + composer ring + sign-in focus ring |
| `b938afc` | T1 fix round 1 | fix(ios): remove accidental debug NSLog from AnimatedGradient render |
| `963a489` | T1 fix round 1 | fix(ios): gradient first frame renders unblurred synchronously; blur lands async with a crossfade — no first-launch hitch |
| `72320bc` | final wave (T5) | fix(ios): plan-10 final wave — detail field alignment, gradient swap hardening, composer backdrop fills the tab |
| *(this commit)* | T5 | docs(ios): plan-10 outcome; ui-changes entry; xcodegen-after-pull note; build 4 |

### Verification

- **StashKit:** `swift test` → **341/341 passing, 0 failures** (unchanged floor — this plan added
  no new StashKit-layer logic, only SwiftUI view/token/rendering work in the app target).
- **App + extension build:** `xcodegen generate` → `xcodebuild build` for both the `Stash` and
  `StashShareExtension` schemes (sim `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, dedicated
  `-derivedDataPath`) → **BUILD SUCCEEDED** on both, zero compiler warnings (the only `warning:`
  line in either log is the pre-existing, benign `appintentsmetadataprocessor` "Metadata
  extraction skipped — No AppIntents.framework dependency" notice, not from any Swift source).
- **Web:** `npm install` + `npm test` → **33 test files, 202 tests, all passed.**
- **UI suite ×2:** full `StashUITests` (22 tests) run twice against production with
  `TEST_RUNNER_STASH_TEST_EMAIL`/`TEST_RUNNER_STASH_TEST_PASSWORD` sourced from
  `ios/.env.test.local` (never printed). Both runs: exactly the standing 3 gate-blocked failures
  (`testAskSmoke`, `testCaptureSmoke`, `testLocationPinSmoke` — Stripe comp decision still
  pending, unchanged since plan 4) and every other test green.
  - **Investigated:** the first full-suite attempt also failed `testDeleteSmoke` —
    `STASH_DELETE_MARKER` wasn't seeded before that run (the test's own documented precondition
    guard firing deliberately, not a crash — same shape as plan 9's own investigated finding for
    the same test). Reseeded a disposable item via REST (`POST /add-note`), re-ran
    `testDeleteSmoke` alone with the marker set, and it passed cleanly (deletes the seeded item,
    asserts it's gone from the grid). Both of the two counted full-suite runs seeded a fresh
    marker up front and needed no follow-up; testDeleteSmoke passed both times. Not a product bug.
  - **Environmental note (new this plan):** the first attempt at the first full-suite run also
    came back `BUILD INTERRUPTED` with no test results — traced to a second, unrelated
    `xcodebuild test` invocation (a one-off screenshot capture) launched concurrently against the
    *same* simulator and the *same* `-derivedDataPath` while the full-suite run was still using
    it; killing that second process took the first down with it. Re-run in isolation (nothing else
    touching that sim until it finished) succeeded cleanly both times after. This is the plan-10
    feedback-round-2 ledger's "cap concurrent xcodebuild agents at 2" lesson recurring in a new
    shape — even two *sequential-in-intent* invocations collide if their windows overlap on the
    same sim + derived-data path; worth internalizing as "one xcodebuild test per sim at a time,
    full stop," not just "cap the agent count."
- **Wave verification (final-wave commit only):** `testDetailSheetAnatomy`, `testEditSmoke`,
  `testComposerKeyboardAccessory`, `testVisualSweepScreenshots` ×1 each, all green, before the
  two full-suite runs above. Screenshots read: `task-5-detail-alignment.png` (title/description
  text flush with the eyebrow/URL bar's left edge — the 6pt hit-padding compensation lands
  correctly), `task-5-firstframe-{17.0,17.4}.png` (the old gradient-bug repro runtimes — smooth
  full-tab wash top to bottom, correct palette, no white box, composer ring/idle shadow read
  clearly against the wash).

### Decisions of record

1. **Composer card ≤ 2/3 of the tab's height; the share sheet is the primary capture path.**
   Answers plan 9's open question: "people will be using the sharing intent to add things the
   majority of the time anyhow, but let's not make things challenging" (Will, 2026-09-04) — the
   in-app Add-tab composer is deliberately secondary. The full-tab gradient wash extension (final
   wave) is downstream of this: once the card no longer fills the screen, the space behind/below
   it needed the same page-level ambience the rest of the app's tabs already carry, not flat white.
2. **The gradient "animated white box" bug's root cause was environment-dependent
   `.drawingGroup()` rasterization, not a logic bug** — `.drawingGroup()` sizes its offscreen
   buffer from pre-effect layout bounds, and `.blur`'s bleed exceeds those bounds; some simulator
   GPU/driver paths (iOS 17.0, 17.4 — not 17.2/17.5/18.5/26.5) don't grow the buffer to cover it.
   Fixed by removing both `.drawingGroup()` and live `.blur` from the pipeline entirely in favor of
   a pre-rendered `UIImage`, which is deterministic on every GPU by construction. **Web is
   unaffected** — nothing about the gradient's CSS/palette/direction changed.
3. **Fade-over, not crossfade, for the two-tier gradient's blur hand-off.** The hitch-fix's
   original crossfade (plain tier 1→0 while blurred tier 0→1, simultaneously) had a visible
   mid-fade lightening dip — two partially-transparent layers over the background don't sum back
   to full opacity. Final wave fixed it by keeping the plain tier at a constant opacity 1
   throughout and only fading the blurred tier in on top via `.transition(.opacity)`.
4. **1px-stroke rule is now enforced on iOS; web carries two follow-up items.** Per Will's "never
   use a 2px stroke... 1px stroke only," every iOS stroke is 1px (grep-audited, zero exceptions;
   the annotation bar is a fill, correctly exempt). Web's `UnifiedInputPanel` composer-ring stroke
   (1.5px) and input focus rings (2px) both still violate the rule and should be brought to 1px in
   a follow-up — flagged in `DESIGN.md` and `docs/ui-changes.md`, not fixed here (web is out of
   scope for this iOS-only plan).

### Carried items

1. **Gradient caches (`AnimatedGradient.plainCache`/`.blurredCache`) are unbounded and grow with
   distinct view sizes.** In practice this app only ever renders the gradient at a handful of
   fixed sizes per device (sign-in, composer, library, splash, share-sheet compose), so the
   realistic ceiling is small — measured ~10.7MB total across both tiers at one device's full set
   of call-site sizes — but nothing currently evicts an entry if that assumption ever stops
   holding (e.g. a future call site sized off a user-resizable container). Not addressed this
   plan; flagged for whoever next touches `StashDesign.swift`'s gradient code.
2. **`NotesEditor`'s `TextEditor` padding (6pt) and its placeholder `Text`'s padding (11pt) are
   intentionally different values**, not a residual inconsistency — `TextEditor` wraps a
   `UITextView` that carries its own ~5pt `textContainer.lineFragmentPadding` on top of whatever
   SwiftUI padding is declared, so `6 + ~5 ≈ 11` lands the two flush. Documented inline at the
   call site; noted here so a future audit doesn't "fix" it back to matching literals.
3. **Web stroke/ring follow-ups (composer ring 1.5px → 1px, input focus rings 2px → 1px)** — see
   Decision 4 above. Not iOS work; carried for whoever picks up the web side of `DESIGN.md`'s
   1px-stroke rule.
4. **The T3-era environmental-flake lesson, restated after this plan's own recurrence:** don't run
   more than one `xcodebuild test` against the same simulator + `-derivedDataPath` combination at
   a time, even briefly and even when one of the two is "just a quick screenshot capture" — the
   collision can silently interrupt the other, longer-running invocation. Cap concurrent
   `xcodebuild` agents at 2 *and* never let their windows overlap on the same sim.
5. **All plan-9 carried items are still carried, unchanged by this plan** (see that plan's own
   Outcome section: `MetaChip.mono` unused; share-extension gate-strip negative-padding
   workaround; `.orange`/`.green` have no `DESIGN.md` token; Apple 5.1.1(v) in-app
   account-deletion requirement still pending; inline citation link styling divergence from web;
   `MarkdownBlocksView` over-styling non-citation links; `Debouncer.cancel()` can't stop an
   already-started action; the rare dropped-`SaveGeneration` duplicate-paragraph window).

### Build 4

`CURRENT_PROJECT_VERSION: 3 -> 4` (`ios/project.yml`) -> `xcodegen generate` -> entitlement
check on the exported `.ipa` (BOTH binaries: `com.apple.security.application-groups:
[group.it.gostash.stash]` + keychain group `3CH3K9NTT2.it.gostash.stash.shared`; app + appex
`CFBundleShortVersionString`/`CFBundleVersion` both `0.1.0`/`4`, verified via `codesign -d
--entitlements -` and `PlistBuddy` on the unzipped `.ipa` before upload) -> `./scripts/release.sh
all` (archive + export, session auth) -> `./scripts/release.sh upload` -> polled
`/v1/builds?filter[app]=6806459949&sort=-uploadedDate&limit=1` (8 polls, ~3 minutes) until
`processingState: VALID` -> attached to the Internal beta group
(`d19f78c1-7af3-4461-9af6-1566200c251b`) via `POST .../relationships/builds` (HTTP 204) ->
confirmed via `GET /v1/betaGroups/<id>/builds`, which lists build 4 alongside builds 1-3, all
`VALID`.

**Build id:** `d49b4ea2-c24b-42c0-9c88-346578308cd0` (version 4, `0.1.0`), attached and VALID.

**Environmental note:** the first UI-suite full-suite attempt during this wrap's own verification
came back `BUILD INTERRUPTED` — see the Verification section above; unrelated to the release
pipeline itself, which ran clean end to end with nothing else touching the same simulator
concurrently.
