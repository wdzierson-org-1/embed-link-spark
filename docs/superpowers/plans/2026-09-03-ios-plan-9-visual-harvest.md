# Stash iOS Plan 9: Visual Harvest (composer card, Editorial titles, type tints, light lock) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harvest the still-missing product ideas from the never-merged `worktree-ios-plan6-visual` branch — re-derived from the current `DESIGN.md`, not ported — and ship TestFlight build 3: the Add tab composer as a floating card with a focus ring, PP Editorial New card titles, DESIGN.md's type-spectrum tints on cards, tokenized subscription-gate strips, a light-mode lock, and a visual-sweep screenshot test.

**Architecture:** One small tokens task first (DESIGN.md + `StashDesign.swift` gain the composer radius, gate-strip tokens, type-spectrum tints, and the light-only rule), then three file-disjoint tasks in parallel (library card, composer card + gate strips, light lock + sweep test), then wrap + build 3. Nothing from the old branch's `Theme.swift`/`StashBackground.swift`/`TypeChipRow`/`make-appicon` is resurrected (all obsolete per the harvest survey); the branch itself is deleted only with Will's okay.

**Tech Stack:** SwiftUI (iOS 17), StashKit, fontTools venv (`/Users/will/.stash-fonttools`), XCUITest, release pipeline.

**Spec:** `DESIGN.md` (§Typography card title = PP Editorial New 400 · 20/tight; §Color "Type spectrum" table; §Space radius/gap/shadow; page-wash gradient block), web `src/components/UnifiedInputPanel.tsx:914-926` (composer card chrome + focus ring), the harvest survey (recorded in `.superpowers/sdd/…/harvest-survey.md`), and the old branch's ideas: `git show worktree-ios-plan6-visual:ios/Stash/Capture/ComposerCard.swift`, `…:ios/StashUITests/StashUITests.swift` (`testVisualSweepScreenshots`).

## Global Constraints

- **DESIGN.md is the source of truth**; new tokens introduced here (composer card radius 6, gate strip, light-only rule) are written into it in Task 0 in the same branch, with values copied verbatim below.
- **Type spectrum tints (DESIGN.md §Color, verbatim):** voice note field `rgba(84,88,178,.11)` accent `#544eba` text `#45408c`; recording/audio `rgba(126,74,158,.10)` accent `#8b4a9e` text `#703c77`; document `rgba(150,70,190,.10)` text `#7d3f9e`; screenshot `rgba(52,132,201,.10)` text `#22689c`; repo plate `#0d1117` mono `#e6edf3` owner `#8b7bd8`; social `rgba(70,100,180,.07)`. Photos/videos/link covers: real imagery, no tint.
- **Space (§Space):** cards radius 16, inputs 12–14, pills 999, sheet 20; `card-gap` 18 (hero → body); card body side padding 24; no-hero top padding 22; card shadow `0 1 2 rgba(20,22,30,.05), 0 8 24 rgba(30,33,44,.08)` (= `stashCardShadow()`).
- **Composer card (from web `UnifiedInputPanel.tsx:914-926`):** radius **6**, `white @ 90%` + blur, idle shadow neutral; active ring `0 0 0 1.5 violet600@.5, 0 0 0 6 violet600@.08, 0 24 48 violet600@.35`, lift −2pt + scale 1.006, spring. Becomes DESIGN.md tokens in Task 0.
- **Gate strip (new tokens, Task 0):** bg `#fff7e6`, border `#f3d9a4`, text `#7a4b00` (amber family; DESIGN.md has no gate token — record it). Used by the composer's subscription gate and the share sheet's gate.
- **Light-only (new rule, Task 0):** product surfaces are light-only until a dark palette exists; iOS locks `.preferredColorScheme(.light)` at the root (web has no dark theme).
- **Fonts:** PP Editorial New Regular (`src/assets/fonts/PPEditorialNew-Regular.woff2` → TTF via `/Users/will/.stash-fonttools/bin/python`, same pipeline as plan 7) bundled in the **app target only** (the share sheet renders no cards); `StashType.editorialTitle()` = 20pt, tight line height, SF `.serif` design fallback only on load failure. Italic not bundled (no product role).
- **Do NOT re-add:** type filter chips (Will's plan-8 decision), the composer lock toggle (plan 8), old theme/gradient files, the gradient icon script.
- Tokens only; no emoji; SF Symbols. Identifier contracts: `card.*` identifiers used by `testCardAnatomySmoke`/`testLibrarySmoke` keep working; `capture.editor`/`capture.dismissKeyboard`/gate identifiers keep working; new tests appended at END of `ios/StashUITests/StashUITests.swift`; **single writer per file per round**.
- Worktree `.claude/worktrees/ios-plan-9` (branch `worktree-ios-plan-9`, base `edc4f56`): commit there, never push; audit `origin/main` before the final merge. Sims `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` (primary) / `46D4EA93-94D5-451E-AC61-A5485AFB211F` / `E188DE28-5253-4BC5-8117-0EE87DF1B783` with distinct `-derivedDataPath DerivedData-<task>` for parallel tasks; StashKit floor **341**; UI suite 21 with the standing 3 gate-blocked adjudications; builds warning-free; `xcodegen generate` only for new/deleted files.
- Deploy at wrap: `CURRENT_PROJECT_VERSION` → **3**; `./ios/scripts/release.sh all && upload` (session auth); attach to group `d19f78c1-7af3-4461-9af6-1566200c251b`; if the Xcode session is expired, STOP and report.

## File Structure

- `DESIGN.md` (tokens + light-only rule), `ios/Stash/Design/StashDesign.swift` (`StashColor.TypeTint`, `StashColor.gate*`, `StashRadius.composer`, `stashComposerRing(active:)`), `ios/Stash/Design/StashType.swift` (`editorialTitle()`), `ios/Stash/Design/Fonts/PPEditorialNew-Regular.ttf`, `ios/project.yml` (UIAppFonts app target).
- `ios/Stash/Library/ItemCardView.swift`, `CardChips.swift` (+ type-tinted chip), `CardPlates.swift` (tints for voice/document/screenshot plates where applicable).
- `ios/Stash/Capture/ComposerCard.swift` (NEW, re-derived), `CaptureComposerView.swift` (wrap + gate strip), `ios/StashShareExtension/ShareComposeView.swift` (gate strip).
- `ios/Stash/StashApp.swift` (light lock), `ios/StashUITests/StashUITests.swift` (`testVisualSweepScreenshots`).
- `docs/ui-changes.md`, this plan (outcome).

---

### Task 0: Tokens — DESIGN.md + StashDesign for everything the harvest needs

**Files:**
- Modify: `DESIGN.md` (§Space: add "Composer card: radius 6, white@90 + blur, focus ring …"; §Color: add "Gate strip" tokens; a new one-line §"Color scheme: light-only" rule, dated), `ios/Stash/Design/StashDesign.swift`, `ios/Stash/Design/StashType.swift`, `ios/Stash/Design/Fonts/PPEditorialNew-Regular.ttf` (NEW), `ios/project.yml` (app target `UIAppFonts` += the TTF; NOT the extension)

**Interfaces (exact names later tasks use):**
```swift
extension StashColor {
    enum TypeTint { case voice, audio, document, screenshot, repo, social }
    static func typeField(_ t: TypeTint) -> Color     // the rgba field tint at its DESIGN.md alpha
    static func typeText(_ t: TypeTint) -> Color      // text color per row; repo → #e6edf3
    static func typeAccent(_ t: TypeTint) -> Color    // accent where the table has one (voice/audio), else typeText
    static let repoPlate = Color(hex: 0x0D1117), repoOwner = Color(hex: 0x8B7BD8)
    static let gateBackground = Color(hex: 0xFFF7E6), gateBorder = Color(hex: 0xF3D9A4), gateText = Color(hex: 0x7A4B00)
}
extension StashRadius { static let composer: CGFloat = 6 }
extension View { func stashComposerRing(active: Bool) -> some View }   // idle neutral shadow vs the three-layer violet ring + lift/scale, spring-animated
extension StashType { static func editorialTitle() -> Font }           // "PPEditorialNew-Regular" 20pt, fallback .system(size: 20, design: .serif)
```
- [ ] **Step 1:** Convert the font: `/Users/will/.stash-fonttools/bin/python -c "from fontTools.ttLib import TTFont; f=TTFont('src/assets/fonts/PPEditorialNew-Regular.woff2'); f.flavor=None; f.save('ios/Stash/Design/Fonts/PPEditorialNew-Regular.ttf')"`; record the PostScript name (name ID 6) and use it in `editorialTitle()`.
- [ ] **Step 2:** DESIGN.md edits (verbatim values from Global Constraints), dated "2026-09-03 (plan 9)".
- [ ] **Step 3:** Tokens + `editorialTitle()` + `stashComposerRing` implemented; `project.yml` `UIAppFonts` (app) += `PPEditorialNew-Regular.ttf`; `xcodegen generate`; build warning-free; extend the DEBUG `design.fontStatus` label to also report `editorial:loaded|fallback` and extend `testDesignSystemFontsLoad` to assert `editorial:loaded`.
- [ ] **Step 4:** Commit: `git add DESIGN.md ios/Stash/Design ios/project.yml ios/Stash/Info.plist ios/StashUITests/StashUITests.swift && git commit -m "feat(design): plan-9 tokens — type spectrum tints, gate strip, composer card radius/ring, Editorial title face, light-only rule"`

---

### Task 1: Library card — Editorial titles, token shell, type-tinted chips

**Files:**
- Modify: `ios/Stash/Library/ItemCardView.swift` (title → `StashType.editorialTitle()` 2-line clamp; radius → `StashRadius.card`; shadow → `.stashCardShadow()`; body side padding 24, hero→body gap 18, no-hero top 22), `ios/Stash/Library/CardChips.swift` (leading **type chip**: tinted field bg + typeText label, `StashType.chip()`, pill radius, for voice/audio/document/screenshot/social; links/images/videos: no type chip — real imagery), `ios/Stash/Library/CardPlates.swift` (voice/document/screenshot plates use `typeField` tints where a flat plate exists; repo plate `repoPlate`/`repoOwner` mono)

**Interfaces:** consumes Task 0 only. Keep `card.*` identifiers and `testCardAnatomySmoke` expectations (read it first; update in-task if a chip label changes).

- [ ] **Step 1: RED** — extend `testCardAnatomySmoke` (edit in place; you're the only test writer besides Task 3's append): assert the audio fixture's card shows a type chip labelled "VOICE NOTE"/"AUDIO" (match DESIGN.md's chip copy — read web `src/components/cards/*` for the exact labels) and the link fixture shows none.
- [ ] **Step 2:** Implement; screenshots of link/image/audio/document fixture cards → `task-1-cards.png`; READ them (serif title visible, chips tinted, shadow two-layer).
- [ ] **Step 3: GREEN** — `testCardAnatomySmoke` + `testLibrarySmoke` ×1; `swift test` untouched (341). Commit: `feat(ios): library cards — Editorial titles, DESIGN.md shell tokens, type-spectrum chips and plates`.

---

### Task 2: Composer card + gate strips (Add tab and share sheet)

**Files:**
- Create: `ios/Stash/Capture/ComposerCard.swift` (re-derived: `StashColor.paper.opacity(0.9)` + `.background(.ultraThinMaterial)`-equivalent blur, `StashRadius.composer`, `.stashComposerRing(active:)` bound to editor focus OR non-empty draft — mirror web's `isPanelActive`)
- Modify: `ios/Stash/Capture/CaptureComposerView.swift` (wrap the editor + attachments + bottom bar in `ComposerCard`; keep the wordmark header and `GradientBackdrop` behind; gate message → a padded strip: `gateBackground` fill, 1pt `gateBorder`, `gateText`, radius 12, `lock.fill` glyph, identifier unchanged), `ios/StashShareExtension/ShareComposeView.swift` (same gate strip treatment for its gate message; identifier unchanged)
- `xcodegen generate` (new file).

**Interfaces:** consumes Task 0. Web reference `UnifiedInputPanel.tsx:900-930`. Old-branch idea reference (do NOT port literals): `git show worktree-ios-plan6-visual:ios/Stash/Capture/ComposerCard.swift`.

- [ ] **Step 1: RED** — append `testComposerCardFocusRing`: on the Add tab, assert `capture.card` exists; tap the editor → assert `capture.card` a11y value reads "active" (expose `.accessibilityValue(active ? "active" : "idle")`); tap `capture.dismissKeyboard` with an empty draft → "idle".
- [ ] **Step 2:** Implement; screenshots idle + active (keyboard up) → `task-2-composer-{idle,active}.png`; READ them (ring visible, lift subtle, no clipping of the attachment ×; gate strip screenshot on the lapsed account → `task-2-gate.png`). Share sheet gate strip: run `testShareExtensionURLSmoke` (its gate branch renders the strip) and screenshot.
- [ ] **Step 3: GREEN** — new test + `testCaptureSmoke` pre-gate + `testComposerKeyboardAccessory` + `testShareExtensionURLSmoke` ×1. Commit: `feat(ios): composer as a floating card with focus ring; tokenized gate strips on Add tab + share sheet`.

---

### Task 3: Light-mode lock + visual sweep test

**Files:**
- Modify: `ios/Stash/StashApp.swift` (`.preferredColorScheme(.light)` on the root scene content, comment citing DESIGN.md's light-only rule), `ios/StashUITests/StashUITests.swift` (append `testVisualSweepScreenshots`: launch signed-in, visit Add/Ask/View/Settings, `XCTAttachment` screenshot per tab with `.keepAlways`, gate-agnostic — no save actions; also set the sim to Dark appearance (`xcrun simctl ui <udid> appearance dark`) before one run and assert the app still renders light: read a known paper-backed element's… (XCUITest can't read colors) → instead attach the dark-appearance screenshots and READ them in the report; restore appearance to light after).

- [ ] **Step 1:** Implement; run `testVisualSweepScreenshots` twice (light + dark appearance) on sim `E188DE28…`; export the attachments (`xcresulttool`) → `task-3-sweep-{add,ask,view,settings}-{light,dark}.png`; READ them: identical light rendering under dark appearance.
- [ ] **Step 2:** Commit: `feat(ios): light-only color scheme lock; visual sweep screenshot test`.

---

### Task 4: Wrap — docs, suites ×2, TestFlight build 3, stale-branch decision

- [ ] **Step 1:** `git fetch origin` + audit/merge `origin/main`; resolve; re-run.
- [ ] **Step 2:** `swift test` (≥341), builds warning-free (both targets), `npm test`, UI suite ×2 (standing 3 only).
- [ ] **Step 3:** `docs/ui-changes.md` top entry "2026-09-03 · iOS visual harvest (plan 9)": composer card + ring (web parity), Editorial card titles now on iOS, type-spectrum chips/plates, gate-strip tokens (new — web should adopt), light-only rule, sweep test; this plan's Outcome (commits, counts, decisions, carried: old-branch items marked OBSOLETE with reasons; the `worktree-ios-plan6-visual` worktree/branch deletion = **Will's decision** — list the exact commands). Commit `docs(ios): plan-9 outcome; ui-changes entry; build 3`.
- [ ] **Step 4:** `CURRENT_PROJECT_VERSION: 3` → `xcodegen generate` → commit → `./ios/scripts/release.sh all` → verify .ipa entitlements (both binaries) → `upload` → poll VALID → attach to the Internal group → record build id. If the Xcode session is expired → STOP and report.

---

## Self-review notes
- **Coverage:** harvest items 3 (composer card) → T2; 6 (Editorial titles) → T0+T1; 9 (light lock) → T3; 10 (gate strip) → T2; 11 (sweep test) → T3; wiring bugs (radius/shadow/padding) → T1; type-tint chips (DESIGN.md gap) → T1; obsolete items explicitly excluded.
- **Placeholders:** none; token values verbatim from DESIGN.md/web; identifiers named.
- **Type consistency:** `StashColor.TypeTint`/`typeField`/`typeText`/`gate*`, `StashRadius.composer`, `stashComposerRing`, `StashType.editorialTitle` defined in T0 and consumed by name in T1/T2.
- **Risks accepted:** XCUITest can't assert colors (dark-appearance proof is screenshot-read); the composer ring's "active" definition mirrors web (`focused || !draft.isEmpty`); Editorial font license — DESIGN.md already mandates the face on iOS (same standing as Neue Montreal).

---

## Outcome (2026-09-03)

**Commit range:** `edc4f56..HEAD` (base = `main` at plan authoring time; `origin/main` audited at
wrap — empty diff, nothing to merge).

| Commit | Task | Message |
|---|---|---|
| `8b70552` | — | docs(ios): plan 9 — visual harvest (composer card, Editorial titles, type tints, light lock) |
| `da920e5` | T0 | feat(design): plan-9 tokens — type spectrum tints, gate strip, composer card radius/ring, Editorial title face, light-only rule |
| `6ade435` | T1 | feat(ios): library cards — Editorial titles, DESIGN.md shell tokens, type-spectrum chips and plates |
| `c70d40e` | T0 fix round 1 | fix(design): plan-9 composer ring — tempered idle shadow, name violet-600 token in DESIGN.md |
| `89b38fc` | T2 | feat(ios): composer as a floating card with focus ring; tokenized gate strips on Add tab + share sheet |
| `048b601` | T3 | feat(ios): light-only color scheme lock; visual sweep screenshot test; card type-chip + composer-card assertions |
| `6f1c8d7` | T2 fix round 1 | fix(ios): composer active-state parity with attachments; gate-strip invariant comment |
| `0bc19ab` | final wave | fix(ios): plan-9 final wave — share extension light lock + token surfaces, neutral type chips replace footer badge, filename chip dropped, chips wrap, DESIGN.md title/idle-shadow clauses |

### Verification

- **StashKit:** `swift test` → **341/341 passing, 0 failures** (unchanged from plan 8's floor —
  this plan added no new StashKit-layer logic, only SwiftUI view/token work in the app target).
- **App + extension build:** `xcodegen generate` → `xcodebuild build` (sim
  `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, dedicated `-derivedDataPath`) → **BUILD SUCCEEDED**, zero
  compiler warnings (the only `warning:` lines in the log are the pre-existing, benign
  `appintentsmetadataprocessor` "Metadata extraction skipped — No AppIntents.framework dependency"
  notices already disclosed in T3's own report; not compiler warnings, not from any Swift source).
- **Web:** `npm install` + `npm test` (worktree root) → **33 test files, 202 tests, all passed.**
- **UI suite ×2:** full `StashUITests` (22 tests — the plan-8 21 plus `testVisualSweepScreenshots`
  and `testLibraryTypeChipAndComposerCard`, both new in T3, net +1 after `testComposerKeyboardAccessory`
  was already counted in plan 8's 21) run twice against production with
  `TEST_RUNNER_STASH_TEST_EMAIL`/`TEST_RUNNER_STASH_TEST_PASSWORD` sourced from
  `ios/.env.test.local` (never printed). Both runs: exactly the standing 3 gate-blocked failures
  (`testAskSmoke`, `testCaptureSmoke`, `testLocationPinSmoke` — Stripe comp decision still pending,
  unchanged since plan 4) and every other test green, including `testVisualSweepScreenshots`,
  `testLibraryTypeChipAndComposerCard`, and `testDesignSystemFontsLoad` (asserts
  `editorial:loaded`, confirming the bundled PP Editorial New face resolves on-device, not the
  `.serif` fallback).
  - **Investigated:** run 1's first pass also failed `testDeleteSmoke` — its own doc comment
    requires a `STASH_DELETE_MARKER` env var seeded from a disposable REST-created item before
    the run, which this task's own runner didn't set the first time (`STASH_DELETE_MARKER was
    not set` — a precondition guard the test raises deliberately, not a crash). Not a product or
    test bug: reseeded a fresh disposable item via `POST /add-note`, re-ran `testDeleteSmoke`
    alone with the marker set, and it passed cleanly (deletes the seeded item, asserts it's gone
    from the grid). Run 2 seeded the marker before starting and needed no follow-up. No other
    unexpected failure either run.

### Decisions of record

1. **The composer focus ring reads as `violet-600`, not web's literal.** Web's shipped
   `UnifiedInputPanel.tsx` ring recipe still hard-codes `rgba(139,92,246,…)` (Tailwind violet-500),
   a legacy pre-token literal that predates DESIGN.md's `violet-600` (`#6d5bd0`) token pass.
   Orchestrator adjudication at T0 review: the token wins (DESIGN.md rule 3 — tokens are the source
   of truth — plus "interactive = violet-600" already governing every other interactive surface).
   DESIGN.md's composer-card bullet now names `violet-600` explicitly and flags web's literal for a
   follow-up retokenization; iOS ships the token value. **Web should adopt this in a follow-up.**
2. **The Add-tab wordmark is kept** — unchanged and un-revisited by this plan; still the plan-8
   assumption pending Will's confirmation (see plan 8's own decisions of record).
3. **`typeAccent`/`.social` tokens are intentionally ahead of use.** `StashColor.typeAccent(_:)`
   and the `.social` case of `TypeTint` were built in T0 per DESIGN.md's full type-spectrum table,
   but no card in this plan's scope currently renders a social-post type chip with an accent (the
   chip grammar only calls `typeField`/`typeText`) — a deliberate token/consumer gap, not dead
   code: the table is DESIGN.md's complete spec and future social-card work reads from tokens that
   already exist rather than re-deriving them.
4. **Composer full-bleed height — OPEN QUESTION for Will.** The composer card's editor content
   claims all available height inside its own card chrome, so in practice the card's rounded edge/
   shadow reads as a thin frame around a nearly full-screen editor rather than a visually distinct
   "card" the way web's fixed-height panel does. Not fixed this plan (no product call to cap it
   was in scope) — Will's call on whether the card should cap its height to something closer to
   web's proportions, or whether full-bleed-inside-a-card is the intended iOS-native adaptation.

### Carried items

1. **`MetaChip`'s `mono` parameter is now unused.** The final wave dropped the raw-filename chip
   from cards entirely (moved to the Details drawer), which was `mono`'s only call site. The
   parameter itself wasn't removed this round — flagged, not a functional issue (dead code, not a
   behavior bug).
2. **Share-extension gate-strip negative-padding workaround** (`ShareComposeView.gateMessage`) —
   the strip's vertical padding is applied to its `.background`/`.overlay` shapes via a negative
   `.padding(.vertical, -8)` rather than to the containing `HStack` directly, because giving the
   HStack real vertical padding pushed `share.note` down enough to break
   `testShareExtensionURLSmoke`'s keyboard-focus step (reproduced 4/4 with real padding, passed
   3/3 with the negative-padding sidestep across 7 bisection runs). Root cause not fully isolated
   (ruled out keyboard-avoidance). Invariant documented inline: the −8pt overflow must stay smaller
   than `composeBody`'s own `VStack spacing: 14`, so it only fills existing breathing room and
   never visually overlaps a sibling. Not re-attempted this plan.
3. **The following plan-8 carried items are still carried, unchanged by this plan:**
   `MarkdownBlocks.looksLikeMarkdown` doesn't trigger on "N)" numbered lists (intentional web
   parity, not an iOS-only gap); `.orange`/`.green` still have no DESIGN.md token; Apple 5.1.1(v)
   in-app account-deletion requirement is still pending (must ship before the app leaves TestFlight
   for the public App Store); inline citation links render violet/no-underline on iOS vs. web's
   underline; `MarkdownBlocksView` styles every markdown link it renders, not just citation links;
   `Debouncer.cancel()` can't stop an already-started action; a dropped `SaveGeneration` response
   can still duplicate a rich-note's appended paragraph in a narrow window.

### `worktree-ios-plan6-visual` — OBSOLETE disposition

The harvest survey (`.superpowers/sdd/2026-09-03-ios-plan-9-visual-harvest/harvest-survey.md`)
found this branch's live product ideas (composer card, Editorial titles, light lock, sweep test,
gate-strip treatment, type-spectrum chips) already re-derived into this plan against the *current*
DESIGN.md — nothing further to harvest. Its remaining pieces are superseded infrastructure, each
with a specific reason:

- **`Theme.swift`** — OBSOLETE. Superseded by `StashDesign.swift`, which is derived directly from
  DESIGN.md (plan 7's consolidation); `Theme.swift`'s tokens predate DESIGN.md and were never the
  source of truth on `main`.
- **`StashBackground.swift`** (gradient) — OBSOLETE. Plan 8 already implemented DESIGN.md's
  six-stop page-wash gradient (`StashColor.gradientStops`) as the one recipe both platforms read
  from; `StashBackground` is a different, earlier gradient implementation with no remaining role.
- **`TypeChipRow`** (type filter chips in the library toolbar) — OBSOLETE, **Will's decision**
  (plan 8): no type-filter chips on the phone form factor; `TypeFilter` was removed. Not
  reconsidered by this plan.
- **The composer "+" attachment menu and its lock/public toggle** — OBSOLETE. The lock toggle was
  removed from the composer in plan 8 (sharing is detail-sheet-only now); the "+" menu pattern was
  superseded by the current composer's inline attachment affordances (four dedicated circles —
  iOS-first, deliberate, per the harvest survey's own "Add-tab gap vs. web" section).
- **`make-appicon.swift`** (gradient icon generator script) — OBSOLETE. The flat-ink app icon
  (matching the favicon, all five glyph paths in `#22262f` on white) is the standing decision;
  no gradient icon is wanted.

**The branch/worktree deletion itself is Will's decision, not executed by this plan.** If Will
confirms, the exact commands are:

```bash
git worktree remove /Users/will/Appdev/embed-link-spark/.claude/worktrees/ios-plan6-visual --force && git branch -D worktree-ios-plan6-visual
```

### Process note

**Single-writer rule held for the whole plan.** Only T0 (tokens, `testDesignSystemFontsLoad`
extension) and T3 (light lock + `testVisualSweepScreenshots` + `testLibraryTypeChipAndComposerCard`)
touched `ios/StashUITests/StashUITests.swift` — T1 and T2 both ran in the same parallel round as
each other without touching the test file (T1 explicitly reverted its own accidental test edit to
honor the rule; T2 added no test edits at all), avoiding the exact two-writers-one-file collision
plan 8 hit and had to adjudicate as git-hygiene-only. No rewrite or attribution cleanup was needed
this plan.

### Build 3 (TestFlight)

- Version: `MARKETING_VERSION 0.1.0` / `CURRENT_PROJECT_VERSION 3` (`ios/project.yml`, bumped by
  this task from build 2's `2`) — verified in both built plists via `PlistBuddy` before archiving.
