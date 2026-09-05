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

- [x] **Step 1:** Implement per Global Constraints. Live-verify via a real Safari share on the sim (the T5/T7 recipe in the old task reports; the account is gate-blocked so ALSO verify the gate branch renders with the new save button disabled-but-visible).
- [x] **Step 2:** Screenshots: compose card (URL variant + image variant with the big hero), the pinned save button with keyboard up, gate state, and the outcome view in BOTH states (seed or briefly force each; the will-sync state is reachable by sharing while offline — `xcrun simctl status_bar`… simpler: temporarily hit the queued path by sharing a >8MB file) → task-1-share-*.png; READ them (no strokes on cards/X; "Optional note…"; full-width bottom save; big preview; violet clock / green check).
- [x] **Step 3:** `testShareExtensionURLSmoke` ×1 green (update in-task only if a text assertion broke — disclose); `swift test` 341; both targets build warning-free. Commit: `feat(ios): share sheet round 2 — strokeless cards, full-width pinned Save, larger preview, Optional note copy, violet/green outcome icons, success token`

### Task 2: Review (fresh reviewer: verify all six notes against screenshots + code; token/scope/identifier audit; memory rule on the bigger hero — no whole-file decodes)

### Task 3: Wrap — suites (StashKit, npm, UI ×2), ui-changes entry (share sheet round 2 + success token, web should adopt), outcome, version 5, upload, attach BOTH groups, submit Beta App Review, record state.

---

## Outcome (2026-09-05)

**Commit range:** `2b112b5..HEAD` (base = `main` at plan authoring time). `origin/main` audited at
wrap — `fa6cd91` (chore(extension): rebuild hosted zip with current icons, unrelated to iOS)
merged clean via `aa21440`.

| Commit | Task | Message |
|---|---|---|
| `220fb21` | — | docs(ios): plan 11 — share-sheet polish + build 5 to beta review |
| `f214dc7` | T1 | feat(ios): share sheet round 2 — strokeless cards, full-width pinned Save, larger preview, Optional note copy, violet/green outcome icons, success token |
| `aa21440` | — | Merge remote-tracking branch 'origin/main' into worktree-ios-plan-11 |
| *(this commit)* | T3 | docs(ios): plan-11 outcome; ui-changes entry; build 5 |

### Six notes → shipped

All six of Will's 2026-09-04 notes shipped in `f214dc7`, reviewed and approved in Task 2:

1. Gray stroke removed from cards (`hairlineCard()` now fill + shadow only).
2. Gray stroke removed from the X/close button (`CircleIcon(..., bordered: false)`).
3. "Add a note…" → "Optional note…" placeholder copy.
4. Save button is full-width, 52pt, pinned to the bottom via `.safeAreaInset(edge: .bottom)`.
5. Save preview enlarged — full-content-width aspect-fit hero for images (max ~45% sheet
   height), larger favicon + title/domain stack for URLs.
6. Outcome icon colors swapped: "Saved to Stash" → new `success` green; "will sync" → `violet-600`.

Plus the new `success` DESIGN.md token (web should adopt) and the ChatBubble "Saved to your
stash" green-literal migration to that token.

### Carried item (wrap fold)

- **`CaptureComposerView.swift:~543` bare `.orange`/`.green` literals** (pre-dating plan 11,
  ledgered as a low finding in Task 2 review): the `.green` half was trivial to fold — migrated to
  `StashColor.success` (the exact "fully clean save" confirmation case the new token exists for).
  The `.orange` half is carried, not folded: it's used for three distinct states (dropped
  attachment, queued/offline, rejected) and DESIGN.md has no warn/amber token yet — inventing one
  under a low-priority wrap fold risked picking the wrong semantic before a real warn-token need
  presents itself elsewhere. Left as a bare literal with an updated comment disclosing why.

### Verification

- **StashKit:** `swift test` → **341/341 passing, 0 failures** (unchanged floor).
- **App + extension build:** `xcodegen generate` → `xcodebuild build` for the `Stash` scheme
  (embeds `StashShareExtension`), sim `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, dedicated
  `-derivedDataPath` → **BUILD SUCCEEDED**, zero compiler warnings (only the pre-existing, benign
  `appintentsmetadataprocessor` "Metadata extraction skipped — No AppIntents.framework
  dependency" notice in either log, not from Swift source). Re-verified after the version-5
  `xcodegen generate` regeneration.
- **Web:** `npm test` → **33 test files, 202 tests, all passed.**
- **UI suite ×2:** full `StashUITests` (22 tests) run twice against production, seeding a fresh
  `STASH_DELETE_MARKER` item via `POST /functions/v1/add-note` before each run (env-var
  passthrough note below).
  - **Run 1:** 19 passed, 3 failed — exactly the standing gate-blocked trio
    (`testAskSmoke`, `testCaptureSmoke`, `testLocationPinSmoke`; Stripe comp decision still
    pending). `testDeleteSmoke` passed (marker seeded up front).
  - **Run 2:** 18 passed, 4 failed — the standing trio plus `testComposerKeyboardAccessory`.
    **Investigated:** every UI interaction in that run's log was 5–10× slower than normal
    (`uptime` showed load averages 10/84/116 at the time — heavy contention from other concurrent
    sessions on the shared machine, 4 simulators booted). Re-ran `testComposerKeyboardAccessory`
    alone immediately after (load already dropping) — **passed in 25s** with normal sub-second
    step timings. Environmental flake under host load, not a product regression.
  - **Tooling note (new this plan):** `TEST_RUNNER_STASH_TEST_EMAIL`/`TEST_RUNNER_..._PASSWORD`
    passed as trailing `xcodebuild test` command-line arguments (the form prior plans' outcome
    docs describe) did **not** reach the test process's `ProcessInfo.environment` on this Xcode
    26.6 setup — confirmed via a build-settings dump showing the override recognized but the
    runner still reporting the credentials unset. Exporting them as real shell environment
    variables before invoking `xcodebuild test` (rather than passing `KEY=value` as extra
    arguments) worked reliably every time after. Worth carrying forward as the working recipe.
- **Version bump:** `CURRENT_PROJECT_VERSION: 4 → 5` in `ios/project.yml` → `xcodegen generate` →
  rebuilt → `PlistBuddy` confirmed `CFBundleShortVersionString`/`CFBundleVersion` = `0.1.0`/`5` on
  **both** `Stash.app/Info.plist` and `Stash.app/PlugIns/StashShareExtension.appex/Info.plist`.

### Fix round 1 (2026-09-05): disabled Save legibility

Will caught a real bug from a screenshot before submission: the pinned Save button's disabled
(gate-blocked) state used a whole-button `.opacity(0.4)`, which dimmed the violet fill AND the
white label together into a washed lavender pill with an illegible "Save". Fixed in `5a7afeb` by
swapping fill + label color for the disabled state instead of dimming opacity —
`StashColor.wash` fill + `StashColor.muted` text, no opacity modifier — same 52pt/full-width/
pinned geometry, `share.save` identifier unchanged. Screenshot-verified live against the
gate-blocked account (`testShareExtensionURLSmoke`'s own `share-gate-closed` checkpoint):
"Save" is clearly legible on the wash pill. `testShareExtensionURLSmoke` re-verified green;
both targets rebuilt warning-free.

**Build 5 is superseded, not submitted.** It finished uploading (VALID-eligible) before the fix
landed, but per Will's instruction was never attached to either TestFlight group and never
submitted for Beta App Review — build 6 (below) carries the fix and is what actually goes to
review.

### Build 6: upload, attach, Beta App Review submission

- **Entitlement check** on the exported `.ipa` (unzipped, both binaries): app binary and
  `StashShareExtension.appex` binary both carry `com.apple.security.application-groups:
  [group.it.gostash.stash]` and `keychain-access-groups: [3CH3K9NTT2.it.gostash.stash.shared]`;
  both `Info.plist`s report `CFBundleShortVersionString`/`CFBundleVersion` = `0.1.0`/`6`.
- `./scripts/release.sh all` (archive + export, session auth) → **ARCHIVE SUCCEEDED** /
  **EXPORT SUCCEEDED** → `./scripts/release.sh upload` → **Upload succeeded**.
- Polled `/v1/builds?filter[app]=6806459949&sort=-uploadedDate&limit=1` (bounded loop, 60s ×
  ≤30) — build `b56fb7a3-de9e-42b0-a7c3-642c07e8798f` (version `6`) reached `processingState:
  VALID` on the 3rd poll (~2 minutes).
- Attached to **both** TestFlight groups via `POST .../relationships/builds` (HTTP 204 each):
  Internal (`d19f78c1-7af3-4461-9af6-1566200c251b`) and Trusted Testers
  (`d0d24fce-73d1-4f0c-864d-a8cfd029461e`). Verified via `GET .../builds` on each group — both
  list build `6` alongside prior builds.
- Submitted for Beta App Review: `POST /v1/betaAppReviewSubmissions` with
  `relationships.build.id = b56fb7a3-de9e-42b0-a7c3-642c07e8798f` → HTTP 201,
  **`betaReviewState: WAITING_FOR_REVIEW`**. Re-`GET` confirms the state persists with
  `submittedDate: 2026-09-05T09:57:22-07:00`. The betaAppReviewDetail (contact phone, demo
  account, review notes) was already complete from plan-11's setup — no changes needed here.
  Public link `https://testflight.apple.com/join/7xCGKxCT` goes live once Apple approves.
- **Build 5** (`a796ea19-1678-40d7-bce1-a94399687bfb`) remains uploaded/VALID but was
  deliberately left unattached to either group and never submitted for review, per Will's
  instruction — build 6 supersedes it entirely.
