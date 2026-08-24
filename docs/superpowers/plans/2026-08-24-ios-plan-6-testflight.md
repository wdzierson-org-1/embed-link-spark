# Stash iOS Plan 6: TestFlight Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the Stash iOS app (with its share extension) onto Will's physical iPhone and into TestFlight internal testing, with a repeatable scripted release pipeline.

**Architecture:** Cloud-managed signing end to end: an App Store Connect API key lets `xcodebuild -allowProvisioningUpdates` create/refresh the distribution certificate, register both bundle IDs, attach the App Group + Keychain Sharing capabilities, and mint profiles server-side — no manual portal clicking and no local cert management beyond what exists. A single release script drives xcodegen → archive → export → upload. The app icon is a derived brand placeholder (single-size 1024 asset catalog, modern Xcode style); real icon design is deferred to the visual-parity plan.

**Tech Stack:** XcodeGen, xcodebuild cloud signing (`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`), App Store Connect API (beta groups/testers), asset catalogs (single-size app icon), TestFlight.

**Spec:** `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` (approved v1 scope named "TestFlight-first") + the plan-5 outcome section's plan-6 handoff (real-device provisioning requirements, un-entitled black-hole rationale). Product approval: Will, 2026-08-24 ("let's move on with implementing testflight").

## Global Constraints

- Team ID: `3CH3K9NTT2` (paid membership confirmed via existing Developer ID cert). Bundle IDs fixed: `it.gostash.stash` (app), `it.gostash.stash.share` (extension).
- **App Store validation rule: the appex's `CFBundleShortVersionString` MUST equal the app's.** Versions become single-source: project-level `MARKETING_VERSION: 0.1.0` / `CURRENT_PROJECT_VERSION: 1`; both Info.plists reference `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`. The extension's current literal `1.0`/`1` is a latent upload-rejection bug — Task 2 fixes it.
- Secrets discipline: the ASC API key lives at `ios/.asc/` (gitignored in Task 3 before the key ever arrives). NEVER commit or print the `.p8` contents, key ID, or issuer ID into committed files or reports — scripts read them from `ios/.asc/config.env`.
- WILL-CHECKPOINTS (only Will can do these; the loop pauses if not done when reached): (W1) create an ASC API key (role **App Manager**) and drop it in `ios/.asc/` per Task 3's README stub; (W2) create the App Store Connect app record for `it.gostash.stash` (after Task 4 registers the bundle IDs); (W3) accept the TestFlight invite on his iPhone and run the device sanity list.
- Worktree `.claude/worktrees/ios-plan-6` (branch `worktree-ios-plan-6`): commit there, NEVER push. Sim UDID `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, `derivedDataPath=DerivedData`, `xcodegen generate` after any project.yml edit; CODE_SIGN_ENTITLEMENTS tripwire (grep build log, both targets) stands.
- StashKit suite stays 283 green (`cd ios/StashKit && swift test`); UI suite untouched this plan (no behavior changes intended); app + extension builds warning-free.
- Icon is a PLACEHOLDER derived from the existing brand mark (180px `apple-touch-icon.png` in the `stash-media/icons/` public bucket + `src/components/StashWordmark.tsx`); do not invent a new visual identity. Polish deferred to the visual-parity plan.
- The share extension's behavior is frozen this plan — configuration/signing changes only. Any file under `ios/StashShareExtension/` or `ios/StashKit/Sources/` changing beyond version/signing settings is out of scope.

## File Structure

- `ios/Stash/Assets.xcassets/AppIcon.appiconset/{Contents.json, AppIcon1024.png}` — NEW: single-size universal icon (app target).
- `ios/StashShareExtension/Assets.xcassets/AppIcon.appiconset/…` — NEW: same icon for the appex (share-sheet display + validation).
- `ios/project.yml` — versions to project-level settings; `DEVELOPMENT_TEAM`; `ASSETCATALOG_COMPILER_APPICON_NAME`; asset-catalog sources.
- `ios/StashShareExtension/Info.plist` (via project.yml `info.properties`) — version literals → build-setting variables.
- `ios/scripts/release.sh` — NEW: xcodegen → archive → export/upload, key-driven; `ios/scripts/ExportOptions-{export,upload}.plist` — NEW.
- `ios/.asc/README.md` — NEW (committed): what Will drops here; `.gitignore` — add `ios/.asc/*` except the README.
- `docs/RELEASING.md` — NEW: the whole release story for humans and agents.
- `.superpowers/sdd/2026-08-24-ios-plan-6-testflight/` — ledger + briefs + reports (uncommitted).

---

### Task 1: App icon — derived brand placeholder, single-size asset catalogs

**Files:**
- Create: `ios/Stash/Assets.xcassets/Contents.json`, `ios/Stash/Assets.xcassets/AppIcon.appiconset/Contents.json`, `ios/Stash/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png`
- Create: `ios/StashShareExtension/Assets.xcassets/` (same structure, same PNG)
- Modify: `ios/project.yml` (both targets: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`; ensure the catalogs are in each target's sources)

**Interfaces:**
- Produces: `AppIcon` asset both targets compile; Task 4's exported .ipa passes the icon validation; the sim springboard shows the icon.

- [ ] **Step 1: Fetch and inspect the existing brand mark.**

```bash
cd /Users/will/Appdev/embed-link-spark/.claude/worktrees/ios-plan-6
curl -so /tmp/stash-touch-icon.png "https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/icons/apple-touch-icon.png"
sips -g pixelWidth -g pixelHeight -g hasAlpha /tmp/stash-touch-icon.png
```

Read `src/components/StashWordmark.tsx` and `public/favicon.ico` (it's really a 73×74 PNG) to understand the mark: colors, shape, whether it's vector-recreatable.

- [ ] **Step 2: Produce the 1024×1024 master.** Two sanctioned routes — pick based on what Step 1 revealed, disclose which:
  - **(a) Vector re-render (preferred if the mark is simple/flat):** write a one-page HTML file reproducing the mark centered on its brand background at 1024×1024 (inline the SVG paths or wordmark styling from `StashWordmark.tsx`; background color from the mark's own palette — sample the touch icon with `sips`/screenshot eyedropper, don't guess), then screenshot it: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --screenshot=/tmp/AppIcon1024.png --window-size=1024,1024 --force-device-scale-factor=1 file:///tmp/icon.html`. **App Store icons must be opaque** — no alpha (`sips -g hasAlpha` must say no; flatten if needed: `sips -s format jpeg … && sips -s format png …` or render on an opaque body background).
  - **(b) Upscale fallback (only if the mark is too complex to re-render):** `sips -z 1024 1024 /tmp/stash-touch-icon.png --out /tmp/AppIcon1024.png` — a 180→1024 upscale of flat artwork is acceptable for a TestFlight placeholder; disclose the softness honestly.

- [ ] **Step 3: Build both asset catalogs (single-size).**

`ios/Stash/Assets.xcassets/Contents.json`:
```json
{ "info": { "author": "xcode", "version": 1 } }
```

`ios/Stash/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images": [
    { "filename": "AppIcon1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

Copy `AppIcon1024.png` in; mirror the identical structure under `ios/StashShareExtension/Assets.xcassets/`.

- [ ] **Step 4: Wire project.yml.** App target: add `Stash/Assets.xcassets` to sources if XcodeGen doesn't already glob it (it does when the folder is under the `sources:` dir — verify in the generated pbxproj that both catalogs appear in the right targets' resources phases); add to `settings.base` of BOTH targets: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. `xcodegen generate`.

- [ ] **Step 5: Verify.** `xcodebuild build` (scheme Stash, sim destination) warning-free; then install on the sim and screenshot the springboard showing the real icon (not the grid placeholder): `xcrun simctl install <UDID> <app>` + `xcrun simctl io <UDID> screenshot`. Also `swift test` (283, untouched — proves no collateral).

- [ ] **Step 6: Commit.**

```bash
git add ios/Stash/Assets.xcassets ios/StashShareExtension/Assets.xcassets ios/project.yml
git commit -m "feat(ios): app icon placeholder from brand mark — single-size catalogs, both targets"
```

---

### Task 2: Version single-sourcing + release signing settings

**Files:**
- Modify: `ios/project.yml` (project-level settings: `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `DEVELOPMENT_TEAM`; extension info.properties version literals → variables)

**Interfaces:**
- Produces: both built Info.plists carry identical `CFBundleShortVersionString` (`0.1.0`) and `CFBundleVersion` (`1`); `DEVELOPMENT_TEAM = 3CH3K9NTT2` in the build settings of both targets; Task 4's validation depends on this equality.

- [ ] **Step 1: Move versions up.** In `ios/project.yml`: delete `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from the Stash target's `settings.base`; add a top-level `settings: { base: { MARKETING_VERSION: "0.1.0", CURRENT_PROJECT_VERSION: 1, DEVELOPMENT_TEAM: 3CH3K9NTT2 } }` block so every target inherits all three.

- [ ] **Step 2: Fix the extension's literals.** In the StashShareExtension target's `info.properties`, set `CFBundleShortVersionString: "$(MARKETING_VERSION)"` and `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"` (XcodeGen writes literal `1.0`/`1` by default — the checked-in `ios/StashShareExtension/Info.plist` currently has exactly that latent mismatch). Do the same for the app's Info.plist if it also carries literals.

- [ ] **Step 3: Regenerate and prove equality.** `xcodegen generate`; build both; then read the BUILT products' plists and assert equality:

```bash
APP=DerivedData/Build/Products/Debug-iphonesimulator/Stash.app
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/PlugIns/StashShareExtension.appex/Info.plist"
# both MUST print 0.1.0; repeat for CFBundleVersion (both 1)
```

Grep the build log for `DEVELOPMENT_TEAM = 3CH3K9NTT2` on both targets; CODE_SIGN_ENTITLEMENTS tripwire both targets while in there.

- [ ] **Step 4: Suite + commit.** `swift test` 283 green.

```bash
git add ios/project.yml ios/StashShareExtension/Info.plist ios/Stash/Info.plist
git commit -m "fix(ios): single-source versions across app+appex; set team for release signing"
```

---

### Task 3: Release pipeline script + key drop-box (runnable up to the signing boundary)

**Files:**
- Create: `ios/scripts/release.sh`, `ios/scripts/ExportOptions-export.plist`, `ios/scripts/ExportOptions-upload.plist`, `ios/.asc/README.md`
- Modify: `.gitignore` (add `ios/.asc/*`, `!ios/.asc/README.md`, `ios/build/`)

**Interfaces:**
- Consumes: Task 2's team/version settings.
- Produces: `./ios/scripts/release.sh archive|export|upload|all` — Task 4 runs `archive`+`export`, Task 5 runs `upload`. Key discovery contract: `ios/.asc/config.env` defines `ASC_KEY_ID`, `ASC_ISSUER_ID`; the `.p8` sits at `ios/.asc/AuthKey_${ASC_KEY_ID}.p8`.

- [ ] **Step 1: `ios/.asc/README.md` (the Will-checkpoint W1 instructions, committed):** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **Generate API Key**, role **App Manager**; download the `.p8` (single chance); place it here as `AuthKey_<KEYID>.p8`; create `config.env` beside it with `ASC_KEY_ID=<KEYID>` and `ASC_ISSUER_ID=<issuer UUID from the same page>`. Everything in this folder except this README is gitignored.

- [ ] **Step 2: `.gitignore`** — append the three lines above; `git check-ignore ios/.asc/config.env` must succeed (test with a dummy file, then delete it).

- [ ] **Step 3: ExportOptions.** `ExportOptions-export.plist`: `method: app-store-connect`, `destination: export`, `signingStyle: automatic`, `teamID: 3CH3K9NTT2`, `manageAppVersionAndBuildNumber: false`. `ExportOptions-upload.plist`: identical but `destination: upload`.

- [ ] **Step 4: `release.sh`.** Bash, `set -euo pipefail`, subcommands:
  - `generate` → `xcodegen generate` (cd ios)
  - `archive` → sources `ios/.asc/config.env` (hard error with the README path if missing); `xcodebuild archive -project Stash.xcodeproj -scheme Stash -destination 'generic/platform=iOS' -archivePath build/Stash.xcarchive -allowProvisioningUpdates -authenticationKeyPath "$(pwd)/.asc/AuthKey_${ASC_KEY_ID}.p8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"`
  - `export` → `xcodebuild -exportArchive -archivePath build/Stash.xcarchive -exportOptionsPlist scripts/ExportOptions-export.plist -exportPath build/export` + the same three auth flags
  - `upload` → same with `ExportOptions-upload.plist`
  - `all` → generate, archive, export
  Never echo the key contents; `config.env` is sourced, not printed.

- [ ] **Step 5: Verify what's verifiable WITHOUT the key** (the signing boundary): `bash -n` both scripts; `plutil -lint` both plists; run `./ios/scripts/release.sh archive` and confirm it fails with the intended, actionable "drop your key per ios/.asc/README.md" message (not a bash error); prove the Release configuration compiles: `xcodebuild build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED (this catches Release-only compile errors now rather than in Task 4).

- [ ] **Step 6: Commit.**

```bash
git add ios/scripts ios/.asc/README.md .gitignore
git commit -m "feat(ios): scripted release pipeline (archive/export/upload) + ASC key drop-box"
```

---

### Task 4: Signed archive + exported .ipa with verified entitlements  ⟨requires W1: key present⟩

**Files:**
- No source changes expected. Artifacts: `ios/build/Stash.xcarchive`, `ios/build/export/Stash.ipa` (both under gitignored `ios/build/`).

**Interfaces:**
- Consumes: Task 3's script + Will's key.
- Produces: a validated .ipa; bundle IDs + capabilities registered on the developer portal (cloud signing side effect) — the precondition for W2 (Will can only create the ASC app record once `it.gostash.stash` exists as an identifier).

- [ ] **Step 1:** If `ios/.asc/config.env` is absent, STOP and report "blocked on W1" — do not fake it.
- [ ] **Step 2:** `./ios/scripts/release.sh all`. Cloud signing should auto-register both bundle IDs, attach App Groups + Keychain Sharing, create an Apple Distribution cert, and mint App Store profiles. If it fails on a capability, fix via the ASC API (bundleIdCapabilities endpoint, JWT-signed with the same key) — disclose exactly what needed manual help.
- [ ] **Step 3: Verify the .ipa's entitlements** (the plan-5 "black-hole" insurance — a mis-provisioned build would strand extension captures): unzip the .ipa; `codesign -d --entitlements - Payload/Stash.app` and the same for `PlugIns/StashShareExtension.appex` — BOTH must show `com.apple.security.application-groups: [group.it.gostash.stash]` and the `3CH3K9NTT2.it.gostash.stash.shared` keychain group; app + appex `CFBundleShortVersionString` equal.
- [ ] **Step 4:** Report the registered-identifier state (query the ASC API bundleIds endpoint, or cite the archive log) so the coordinator can hand W2 to Will with certainty. Commit nothing (artifacts are gitignored); ledger the evidence.

---

### Task 5: Upload + TestFlight internal group  ⟨requires W2: ASC app record exists⟩

**Files:**
- Create: `docs/RELEASING.md`
- Modify: plan doc (outcome), `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` (TestFlight milestone ✓)

**Interfaces:**
- Consumes: Task 4's archive; the ASC app record.
- Produces: a build in TestFlight, Will invited; `docs/RELEASING.md` documents the whole path.

- [ ] **Step 1:** `./ios/scripts/release.sh upload` (re-archive first if the archive is stale). Upload completes without validation errors — the icon (T1) and version-match (T2) requirements were designed for exactly this gate.
- [ ] **Step 2:** Poll processing via the ASC API (`builds` endpoint, JWT with the same key; ~5–15 min typical). `ITSAppUsesNonExemptEncryption=false` already in both plists → no export-compliance prompt should appear.
- [ ] **Step 3:** Via ASC API: ensure an internal beta group ("Internal") exists with the build attached, and Will's Apple ID email is a tester. If the API surface refuses something (internal groups are tied to ASC team users), document the exact two clicks Will needs instead — honest fallback, not silent skip.
- [ ] **Step 4:** `docs/RELEASING.md`: prerequisites (key drop-box), one-command release, version/build bump rule (bump `CURRENT_PROJECT_VERSION` every upload, `MARKETING_VERSION` per release), processing/beta-review expectations (internal = no review; external = ~1-day beta review), and the W-checkpoint list for future releases (none — after this plan, releases are agent-runnable end to end).
- [ ] **Step 5:** Wrap: plan outcome section (date, commits, what W-steps remain open), spec milestone ✓, ledger. Commit docs: `git add docs/RELEASING.md docs/superpowers/... && git commit -m "docs(ios): TestFlight release pipeline + plan-6 outcome"`.

---

### Task 6: Device verification (Will) + closure  ⟨requires W3: invite accepted⟩

No files — a checklist handed to Will, results recorded in the ledger/outcome:

- [ ] Install from TestFlight on the physical iPhone; sign in.
- [ ] Share a URL from Safari → compose card → Save → item appears in the app (first REAL-DEVICE proof of the App Group + shared keychain + share flow).
- [ ] Share a photo (tests the staging/streaming path on device).
- [ ] Toggle the location pin once (real-device CoreLocation prompt behavior — the plan-5 open observation).
- [ ] Voice note + Ask tab sanity.
- [ ] Report anything broken → becomes fix-wave input; when clean, plan 6 closes and widgets/App Intents (plan 7) begins.

---

## Self-review notes (done at authoring time)

- **Spec coverage:** TestFlight-first milestone (2026-08-10 approval) ✓ T1–T5; plan-5 handoff items: portal registration of App Groups/Keychain on real App IDs ✓ T4 (cloud signing) with entitlement verification ✓ T4 Step 3; icon requirement ✓ T1; version-match validation rule ✓ T2; device-grant location observation ✓ T6.
- **Placeholder scan:** all commands concrete; the two honest fallbacks (T1 upscale route, T5 manual-clicks route) are sanctioned disclosed outcomes, not TBDs.
- **Type consistency:** script subcommand names used in T4/T5 match T3's definitions; ExportOptions filenames consistent; key-discovery contract (`config.env` names) identical in T3 Step 1/Step 4 and T4 Step 1.
- **Known risks, accepted:** cloud signing's first contact with the portal may hit team-agreement prompts only Will can accept (surfaces as a clear xcodebuild error → becomes a W-step, disclosed); ASC app-record creation is genuinely UI-only (W2 stands); internal-tester API limits → T5 Step 3's fallback; Xcode 26 flag drift for `-exportArchive upload` (if `destination: upload` misbehaves, fall back to exporting then `xcrun altool`-successor per `xcodebuild -help` on this machine — investigate, don't guess).
- **Ethos check:** no capture-time behavior changes anywhere; this plan is pure distribution plumbing.
