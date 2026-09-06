# Stash iOS Plan 13: Three-Panel Share Tutorial (carousel v2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single-panel "How to easily stash" screen (plan 12, v1) with the three-panel swipe carousel Will approved from the HTML prototype, then ship TestFlight build 9.

**Architecture:** One SwiftUI view rewrite (`HowToStashView`) — a paged `TabView` with custom dots, Next → "Got it", Skip — plus two natively drawn panels (share glyph; mock share sheet with a glowing Stash tile) and one image panel (the ungated step-3 capture). Presentation/flags from plan 12 (`OnboardingState`) are unchanged. One UI test updated. Wrap = docs + build 9.

**Tech Stack:** SwiftUI iOS 17, XcodeGen, XCUITest, `ios/scripts/release.sh`, `ios/scripts/asc-api.sh`.

**Spec:** `docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe.html` (the HTML comment block at the top is the per-panel copy + glow values) + Will's 2026-09-07 notes (verbatim): "panel 1: we can just use the share button as the example 'Look for the share button' (and then show the share icon)"; "panel 2: let's show the share sheet with the Stash icon in place — maybe a glowing outline around it? add some text: if you dont see the Stash icon, click on the 'More' button and make it a favorite"; "panel 3: remove the 'subscribe to add items' panel". Design rules: DESIGN.md (tokens only, 1px strokes, no emoji, flat brand).

## Global Constraints

- Panel copy (final, from the prototype): persistent title "How to easily stash" + lead "Save from any app: tap Share, then Stash."; kicker `STEP N` (`StashType.microLabel`, violet600). P1 "Look for the share button" / caption "In Safari, Photos, or any app, tap Share." / art = `square.and.arrow.up` in iOS system blue (`Color(uiColor: .systemBlue)` — deliberately NOT a Stash token: it is the OS glyph the user is looking for) on a 160pt white tile, radius 28, `stashCardShadow()`. P2 "Pick Stash" / caption "Choose Stash in the share sheet." / hint (`StashType.meta`, faint) "Don't see Stash? Tap More, then add Stash to your favorites." / art = native mock share sheet: wash sheet with grabber, app row [Reminders stand-in (checklist glyph) | Stash (real icon via a new `onboarding.stashTile` imageset copied from AppIcon 1024, 60pt, radius 13) | More (three dots)] with labels, then three white rows "Copy Photo / Add to Album / AirPlay" with trailing SF glyphs; the Stash tile gets a 1px violet600 ring + violet glow (shadow color violet300 @0.45, radius pulsing 6→14pt, 1.6s autoreverse; honors `accessibilityReduceMotion` → static). P3 "Add a note, save" / caption "Add an optional note, then Save. Stash does the rest." / art = `onboarding.step3` (already re-captured ungated in f3c4d94).
- Carousel: `TabView(selection:)` `.tabViewStyle(.page(indexDisplayMode: .never))`, custom dots (active = 24×6 violet600 capsule, inactive = 6pt faint circles), primary button "Next" → "Got it" on panel 3 (violet600, full width, 52pt, `StashRadius.input`), "Skip" text link (muted). **Semantics:** Got it AND Skip both mark `onboarding.howToStash.seen` (Skip is not "later"; the screen stays reachable from Settings → "How to stash"). "Show me later"/deferred path from plan 12 stays in code (Settings/relaunch logic) but the button is gone. Swipe + Next both animate `withAnimation(.easeInOut(duration: 0.25))`.
- Identifiers: keep `onboarding.gotIt` for the primary button in every state (label changes), add `onboarding.skip`, `onboarding.panel.1/2/3` on the panel roots, `onboarding.dots`. Update `testOnboardingPanelShowsOnceAfterSignIn` to tap Next twice then Got it (and assert the label flips), plus a Skip branch that asserts the panel does not return on a no-arg relaunch. Settings re-entry test path unchanged.
- Delete `onboarding.step1` and `onboarding.step2` imagesets (no longer used) — grep for references first.
- Sim `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`; `-derivedDataPath DerivedData`; EXPORTED TEST_RUNNER_* from ios/.env.test.local; builds warning-free; StashKit floor 344; UI suite 24 with the standing 3 gate-blocked failures.

---

### Task 1: Carousel view + assets + test

**Files:** Modify `ios/Stash/Onboarding/HowToStashView.swift`; Create `ios/Stash/Assets.xcassets/onboarding.stashTile.imageset/`; Delete `onboarding.step1.imageset`, `onboarding.step2.imageset`; Modify `ios/StashUITests/StashUITests.swift` (only the onboarding test).

- [ ] Rewrite `HowToStashView` per Global Constraints (panels as private subviews: `SharePanel`, `PickStashPanel`, `SavePanel`; `MockShareSheet` for P2).
- [ ] Add the `onboarding.stashTile` imageset (1024 → 180/270 px @2x/@3x, ≤60KB) and delete the two unused imagesets.
- [ ] Build warning-free; screenshot all three panels on the sim (`.superpowers/sdd/plan-13/panel-{1,2,3}.png`) and READ them against the prototype PNGs (`docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe-panel{1,2,3}.png`).
- [ ] Update the UI test; run it ×2 green; run `testSettingsSmoke` (or the settings re-entry path) once.
- [ ] Commit `feat(ios): plan-13 — three-panel share tutorial carousel (v2 of How to easily stash)`.

### Task 2: Wrap + build 9

- [ ] `docs/ui-changes.md` top entry "2026-09-07 · iOS share tutorial carousel (plan 13)" (copy, semantics: Skip = seen; deferred path retained for Settings/relaunch logic; system-blue exception documented), plan Outcome section.
- [ ] `ios/project.yml` `CURRENT_PROJECT_VERSION: 9` → `xcodegen generate`; suites: StashKit, `npm test`, UI ×2.
- [ ] `./scripts/release.sh all` → upload → poll VALID → attach both groups → beta review submit ONLY if no build is in review (build 8 was WAITING_FOR_REVIEW at plan start; expect blocked → record).

## Outcome (2026-09-07)

Commits on `worktree-ios-plan-13` (base `89898ee`): `f3c4d94` (prototype v2
— Will's panel revisions: share glyph P1, glowing Stash tile + More hint P2,
ungated step-3 recapture), `7d4938b` (T1: carousel rewrite, `onboarding.
stashTile` asset, deleted `onboarding.step1`/`step2`, updated onboarding
UI test), then this wrap's docs/build-9 commits below. `git fetch origin` +
`git log --oneline HEAD..origin/main` found zero new commits — nothing to
merge.

**Review verdict:** APPROVE (subagent-driven-development branch review after
T1), with one nit — the onboarding UI test's root-cause comment said
`panelHeight` 470 while the view ships 490 — folded into this wrap (comment
now reads 490, matching the view).

**Home-indicator gesture-zone finding** (T1, worth carrying to any bottom-
anchored control on a Face-ID iPhone): the first working carousel used a
taller card (`panelHeight` 508pt), which put `onboarding.skip` at `y≈819` on
an 852pt-tall iPhone 15 Pro — inside the strip iOS reserves for the home-
indicator swipe gesture. XCUITest still reported the button `hittable`, and
the tap even *looked* like it dismissed the panel (the tab bar underneath a
`.fullScreenCover` stays in the accessibility tree while covered), but the
OS silently ate the touch before SwiftUI's `Button` action ever ran, so
`OnboardingState.markHowToStashSeen()` never fired and the panel silently
reappeared on the next relaunch. Fixed by shrinking the card to 490pt
(~93pt clear of the edge), not by moving the button. Recorded in-code
(`StashUITests.swift`) for the next height change.

**SE-scroll note:** on a 375×667 iPhone SE the card's content runs to
roughly 700pt tall — taller than the screen — but the card lives inside a
`ScrollView`, so it scrolls cleanly rather than clipping; no layout change
was needed for that screen size.

Suites and build-9 TestFlight outcome (upload id, processing state,
beta-group attachment, beta-review submission result) are recorded in a
follow-up amendment to this section once the pipeline finishes — see
`.superpowers/sdd/plan-13/task-2-report.md` for the full transcript.
