# Stash iOS — Plan 5: Share extension

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Share anything to Stash from any app — links, text, screenshots/photos, videos, audio, PDFs — through a compact compose card that saves in ~1s (or durably queues), honoring the ethos: one gesture in, enrichment does the rest.

**Architecture:** A `StashShareExtension` target sharing session (keychain access group) and durable state (App Group container) with the app. The extension maps `NSItemProvider`s to capture units, tries a direct send (small payloads), and falls back to the cross-process Outbox — which gains file-claim semantics so extension and app can never double-drain. Files stream through disk (never whole-file `Data` loads — the extension's ~120 MB ceiling is a named requirement), generalizing plan 3's durable-recording pattern into a `StagedFileStore` with an orphan sweep. Adopted decisions (proposed at the plan-3 milestone, confirmed by continuation): save-and-dismiss UX (no open-app affordance); big files stream-copy into staging and upload on next app open.

**Tech Stack:** Swift 5.10 / SwiftUI, `UIHostingController`-based share extension, App Group + keychain sharing groups, supabase-swift custom `AuthLocalStorage`, ImageIO downscaling, URLSession file-based uploads.

**Spec:** `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` (Share extension section + auth note) + `docs/ETHOS.md` (single-object, lowest-friction, enrichment-behind-the-API) + the plan-4 outcome's plan-5 handoff (named requirements). Read all three.

## Global Constraints

- Everything standing still binds: min iOS 17, worktree-branch commits (no push), warning-free builds, exact-path `git add`, no credentials, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`, `swift test` from `ios/StashKit`, sim UDID 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB + `-derivedDataPath DerivedData`, EXPORTED `TEST_RUNNER_*` vars, `--uitest-reset-auth`, restore-first fixtures (12 permanent rows), SourceKit single-file noise, endpoint deploys via `supabase functions deploy` + `list` verify.
- **Identifiers:** extension bundle id `it.gostash.stash.share`; App Group `group.it.gostash.stash`; keychain access group `$(AppIdentifierPrefix)it.gostash.stash.shared`. Entitlements land on BOTH targets via `project.yml` (the XcodeGen declarative bet — no pbxproj surgery).
- **Session sharing:** supabase-swift auth storage moves to a shared-keychain-backed `AuthLocalStorage`. This costs every dev install ONE re-sign-in (documented; `--uitest-reset-auth` keeps tests self-healing). Extension NEVER initiates a token refresh race it can't win: use the stored access token; on 401/expired → Outbox, never block the share sheet (spec's auth note; zombie-session lesson: missing session = signed-out UI state, not an error).
- **Memory budget:** the extension never loads a shared file into memory whole. `NSItemProvider.loadFileRepresentation` → `FileManager.copyItem` into staging → file-based upload or Outbox reference. Images needing downscale (>20 MB) go through ImageIO `CGImageSourceCreateThumbnailAtIndex` (bounded decode) to a staged file.
- **Direct-vs-queue rule:** URLs/text → direct `add-url`/`add-note` (fallback Outbox). Files ≤ 8 MB → direct upload + `add-file` from the extension. Files > 8 MB → stage + Outbox entry with `local_file_path` (main app uploads on next open). Any failure anywhere → Outbox; the user ALWAYS sees success ("Saved to Stash" / "Saved — will sync"), then auto-dismiss (~0.8s). No open-app affordance (adopted decision).
- **Multi-item shares** (OS hands us N objects — not a user grouping decision): N units, note on the FIRST, batch notice copy reused from the composer. Activation rule accepts: 1 URL, 1 text, ≤10 images, ≤3 movies, ≤3 audio, ≤5 file-urls/PDFs.
- **Cross-process Outbox:** per-user directory moves into the App Group container (scoping preserved — plan-4 doc comment says this migration MUST keep it); drain entries are claimed via atomic sidecar files before sending (per-instance `isDraining` stays as the in-process fast path but is no longer the correctness guarantee); stale claims (> 10 min) are reclaimable. `pendingRecordings()` finally gets its caller: a startup `sweepOrphans()` reconciles staged/recorded files that never got Outbox entries.
- **Gate:** the extension reads a cached subscription-gate boolean from App Group `UserDefaults` (the app writes it on every `SubscriptionStore.refresh` resolve); missing cache = fail-open (plan-1 spec). KNOWN CONTEXT: the test account's lapsed trial means gate-dependent smoke steps stay adjudicated exactly like the existing capture smokes until Will's Stripe decision; structure smokes so the pre-gate flow asserts unconditionally.
- **Location:** optional pin toggle on the compose card reusing `LocationCapture`/`LocationBuild` (CoreLocation is available to extensions with when-in-use auth; the app's grant covers the extension's bundle? NO — extensions prompt separately; treat `.notDetermined` in-extension as pin-hidden v1 if the prompt proves hostile in the share-sheet context — implement, verify live, and disclose the observed behavior; the pin must never block or delay a save).
- Do NOT build: widgets/App Intents (plan 6), visual redesign (plan 7), Android/mac. Carried-but-out-of-scope ledger items stay carried unless named in a task.

---

### Task 1: Platform prep one-liners (carried ledger debt)

**Files:**
- Modify: `supabase/functions/add-url/index.ts` (~:319), `supabase/functions/add-note/index.ts` (~:57), `supabase/functions/add-url/index.ts` (~:228 logging)

- [ ] **Step 1:** add-url's nested link sanitize: the `providedLink` check gains `&& !Array.isArray(providedLink)` (plan-4 final-review Minor 3 — an array link silently dropped the flavor guarantee).
- [ ] **Step 2:** Log redaction (Minor 4): in add-note and add-url, replace the full-body `console.log`s with a redacted form — log the keys and scalar sizes, never `attributes` contents: `console.log('add-url called', { hasAttributes: !!attributes, url })` / `console.log('add-note called', { hasAttributes: !!attributes, contentLength: (content ?? '').length })`. Location coordinates must no longer reach edge-function logs.
- [ ] **Step 3:** Deploy both + `supabase functions list` verify. E2E re-checks (env/JWT pattern): add-url with `{"attributes":{"link":["x"]}}` → row has `attributes.link.flavor` present (object, classified — array replaced); add-note with a location blob → item saves AND the function logs (if inspectable via `supabase functions logs` — best-effort, else assert only behavior) contain no coordinates. Clean up rows.
- [ ] **Step 4:** Commit — `git add supabase/functions && git commit -m "fix: sanitize array link attributes; redact capture-endpoint logs"`

---

### Task 2: App Group + shared keychain session

**Files:**
- Create: `ios/StashKit/Sources/StashKit/SharedKeychainStorage.swift`, `ios/StashKit/Sources/StashKit/AppGroup.swift`
- Modify: `ios/project.yml` (entitlements both targets — extension target arrives in T5; add the app's now), `ios/StashKit/Sources/StashKit/StashClient.swift`, `ios/StashKit/Sources/StashKit/Outbox.swift` (+ `RecordingStore.swift`) default directories
- Test: `ios/StashKit/Tests/StashKitTests/SharedKeychainStorageTests.swift`, `OutboxTests.swift` (directory-resolution cases)

**Interfaces:**
- Produces:

```swift
public enum AppGroup {
    public static let identifier = "group.it.gostash.stash"
    /// The shared container when entitled; Application Support fallback otherwise
    /// (unit tests + un-entitled contexts). Callers never care which.
    public static func containerURL() -> URL
    public static func userScopedURL(_ component: String, userId: UUID) -> URL  // <container>/<component>/<uid-lowercased>
}
public struct SharedKeychainStorage: AuthLocalStorage {   // exact protocol name/signature: VERIFY against the v2.54.1 checkout Sources/Auth (store/retrieve/remove shapes) and adapt with disclosure
    public init(accessGroup: String?, service: String = "it.gostash.stash.session")
}
```

`StashClient` constructs its `SupabaseClient` with `auth.storage = SharedKeychainStorage(accessGroup: …)` — access group passed only when the entitlement exists (probe: attempt a keychain write with the group; fallback nil for tests/un-entitled). `Outbox.defaultDirectory(userId:)` and `RecordingStore`'s default become `AppGroup.userScopedURL("StashOutbox"/"StashRecordings", userId:)` — per-user scoping PRESERVED (the plan-4 doc comment binds this).
- [ ] **Step 1:** project.yml: app target gains entitlements (`com.apple.security.application-groups: [group.it.gostash.stash]`, `keychain-access-groups: [$(AppIdentifierPrefix)it.gostash.stash.shared]`) via a checked-in `ios/Stash/Stash.entitlements` referenced from project.yml. TRIPWIRE: regenerate, verify the entitlements file is referenced in the built settings (grep the build log for CODE_SIGN_ENTITLEMENTS).
- [ ] **Step 2:** TDD SharedKeychainStorage (round-trip store/retrieve/remove against the LOCAL keychain in tests — accessGroup nil path; the group path is live-verified in T5 when two targets exist) + AppGroup.containerURL fallback logic (entitled probe fails in `swift test` → Application Support fallback asserted) + Outbox/RecordingStore resolution tests updated.
- [ ] **Step 3:** Wire StashClient; the ONE-TIME re-sign-in: on first launch with the new storage the old default-keychain session is invisible → SessionStore lands signed-out → sign in again (document in the report; `--uitest-reset-auth` makes suites immune). Migrate nothing (dev-stage, zero real users — decision of record).
- [ ] **Step 4:** Suite green (expect ~210 with new tests); app builds warning-free; run testSettingsSmoke ×1 (sign-in works with the new storage — the reset hook exercises sign-out too).
- [ ] **Step 5:** Commit — `git add ios && git commit -m "feat(ios): App Group container + shared keychain session storage"`

---

### Task 3: Cross-process Outbox claims

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/Outbox.swift`
- Test: `ios/StashKit/Tests/StashKitTests/OutboxTests.swift`

**Interfaces:**
- Produces: claim-before-send semantics — for each pending entry, drain atomically creates `<entryId>.claim` (a sidecar JSON `{owner, claimedAt}`) with `Data.write(options: [.withoutOverwriting])`; creation failure = another process owns it → skip. Claims older than `staleClaimInterval` (600s) are deleted and the entry re-eligible. Claim removed with the entry on success; on failure the claim is removed so retry is possible (attempts still increment on the entry). `isDraining` stays (in-process reentrancy fast path). `drain` signature unchanged.

- [ ] **Step 1: Failing tests** — (a) `testClaimedEntryIsSkippedByASecondOutbox`: enqueue in dir; Outbox A claims manually (write the sidecar via the internal API — expose `claimEntry(id:) -> Bool` internal-for-testing); Outbox B (same dir) `drain` → 0 sent, entry + claim intact; (b) `testStaleClaimIsReclaimed`: write a sidecar with `claimedAt` 700s ago (inject a `now` closure — add `now: @Sendable () -> Date = Date.init` to `Outbox.init` for testability); drain → entry sends, sidecar replaced then removed; (c) `testFailedSendReleasesClaim`: failing poster → after drain, attempts=1 and NO `.claim` file remains; (d) existing 16 Outbox tests stay green (claims are transparent to single-instance use).
- [ ] **Step 2: RED**, **Step 3: Implement** (`.withoutOverwriting` gives O_EXCL atomicity on APFS; document that the App Group container is local-only — no iCloud/network-FS caveats), **Step 4: GREEN** (~214). **Step 5:** Commit — `git commit -am "feat(ios): cross-process Outbox drain claims with stale recovery"`

---

### Task 4: StagedFileStore + streaming uploads + orphan sweep

**Files:**
- Create: `ios/StashKit/Sources/StashKit/StagedFileStore.swift`
- Modify: `ios/StashKit/Sources/StashKit/CaptureAPI.swift` (file-based upload), `ios/StashKit/Sources/StashKit/Outbox.swift` (drain uploads from file, not Data), `ios/StashKit/Sources/StashKit/RecordingStore.swift` (sweep integration)
- Test: `ios/StashKit/Tests/StashKitTests/StagedFileStoreTests.swift` (+ Outbox drain-from-file case)

**Interfaces:**
- Produces:

```swift
public struct StagedFileStore: Sendable {
    public init(userId: UUID, directory: URL? = nil)   // default AppGroup.userScopedURL("StashStaging", userId:)
    public func stage(from source: URL, fileExtension: String) throws -> URL      // FileManager.copyItem — never loads Data
    public func stageDownscaledImage(from source: URL, maxDimension: CGFloat, quality: CGFloat) throws -> URL
    // ImageIO CGImageSourceCreateThumbnailAtIndex (kCGImageSourceThumbnailMaxPixelSize) → JPEG at quality → staged file. Bounded memory.
    public func pendingStaged() -> [URL]
    public func discard(_ url: URL)
    public func fileSize(of url: URL) -> Int?           // attributes, no read
}
public func uploadToStorageFromFile(fileURL: URL, path: String, contentType: String, accessToken: String) async throws
// URLSession uploadTask(with:fromFile:) against <supabase>/storage/v1/object/stash-media/<path>
// with Authorization+apikey headers — streams from disk; non-2xx → CaptureError.badStatus.
public func sweepOrphans(userId: UUID, outbox: Outbox, recordings: RecordingStore, staging: StagedFileStore) async -> Int
// Any file in recordings/staging with NO outbox entry referencing it (match on local_file_path)
// gains a .file entry (mime from extension via a small map; m4a→audio/mp4, jpg/png/heic, mp4/mov→video/*, pdf).
// Returns entries created. Files younger than 60s are skipped (may be mid-flight).
```

Outbox's `local_file_path` drain switches from `Data(contentsOf:)+upload` to `uploadToStorageFromFile` (same crash-safe order: upload → persist transition → delete local → send).
- [ ] **Step 1: Failing tests** — staging copy leaves source intact + staged file byte-equal; downscale: generate a large image in-test (`UIGraphicsImageRenderer` is app-side — use CoreGraphics `CGContext` bitmap, StashKit-safe) → staged output's pixel dimensions ≤ maxDimension and file smaller; sweep: recording file with no entry → entry created with right mime + local_file_path, second sweep creates nothing (idempotent), file younger than 60s skipped (inject `now`); drain-from-file: existing SnapshotPoster-style test extended to assert the upload closure receives a FILE URL path (adapt the injectable `upload` closure signature to `(URL, String, String) async throws -> Void` — update all call sites/tests mechanically).
- [ ] **Step 2: RED**, **Step 3: Implement**, **Step 4: GREEN** (~222). **Step 5:** Commit — `git commit -am "feat(ios): streaming file staging, file-based uploads, orphan sweep"`

---

### Task 5: Extension target scaffold

**Files:**
- Create: `ios/StashShareExtension/ShareViewController.swift`, `ios/StashShareExtension/Info.plist` (via project.yml `info.properties`), `ios/StashShareExtension/StashShareExtension.entitlements`
- Modify: `ios/project.yml`

**Interfaces:**
- Produces: `StashShareExtension` target (type `app-extension`, bundle id `it.gostash.stash.share`, depends on StashKit, entitlements = same App Group + keychain group), `NSExtension` dict: `NSExtensionPointIdentifier: com.apple.share-services`, `NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController`, `NSExtensionActivationRule` dict (`NSExtensionActivationSupportsWebURLWithMaxCount: 1`, `…Text: true`, `…ImageWithMaxCount: 10`, `…MovieWithMaxCount: 3`, `…FileWithMaxCount: 5`). `ShareViewController: UIViewController` hosting a placeholder SwiftUI view ("Stash" + Cancel) via `UIHostingController`; Cancel calls `extensionContext.completeRequest`.
- [ ] **Step 1:** project.yml target + entitlements file + `xcodegen generate`; TRIPWIRE on both Info.plists.
- [ ] **Step 2:** Build the app scheme (extension embeds automatically as a dependency — add it to the app target's `dependencies` with `embed: true`); BUILD SUCCEEDED warning-free.
- [ ] **Step 3:** Live check: install on the sim, open Safari → share sheet → **Stash appears**; tap it → placeholder card renders; Cancel returns. Screenshot the share sheet + the card. (Driving: `xcrun simctl launch` Safari + XCUITest springboard automation is T8's job — here a manual-style scripted UI test or `simctl` + coordinate taps is acceptable; disclose the method.)
- [ ] **Step 4:** Commit — `git add ios && git commit -m "feat(ios): share extension target — appears in the system share sheet"`

---

### Task 6: Share intake — provider mapping + send orchestration (StashKit)

**Files:**
- Create: `ios/StashKit/Sources/StashKit/ShareIntake.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ShareIntakeTests.swift`

**Interfaces:**
- Produces:

```swift
public enum SharedObject: Equatable, Sendable {
    case url(String)
    case text(String)
    case file(stagedURL: URL, mimeType: String, fileName: String?, durationS: Double?)
}
public struct ShareIntakeResult: Equatable, Sendable {
    public var saved: Int; public var queued: Int; public var failed: Int
}
public struct ShareIntake: Sendable {
    public init(userId: UUID, capture: CaptureAPI = CaptureAPI(), outbox: Outbox? = nil,
                staging: StagedFileStore? = nil, directSendLimit: Int = 8 * 1024 * 1024,
                accessToken: @escaping @Sendable () async throws -> String,
                upload: @escaping @Sendable (URL, String, String) async throws -> Void = uploadToStorageFromFile persisted-shape)
    public func submit(_ objects: [SharedObject], note: String?, location: CapturedLocation?) async -> ShareIntakeResult
}
```

`submit` semantics (ethos + composer parity): note attaches to the FIRST object only; every unit carries `attributes` (location + per-file media) via the existing builders; url → `addURL` (note as content), text → `addNote`, file ≤ limit → upload-from-file + `addFile`, file > limit → Outbox `.file` entry with `local_file_path` (STAGED file retained — the durable pattern); ANY thrown error on a unit → Outbox fallback for that unit (`queued`+1); Outbox enqueue failure → `failed`+1 (never silent). Provider mapping lives in the EXTENSION (T7) because `NSItemProvider` loading is callback/main-actor-ish — `ShareIntake` takes already-materialized `SharedObject`s, keeping this layer `swift test`-able.
- [ ] **Step 1: Failing tests** (StubPoster + tmp dirs + recording upload closure): url+note → addURL first with note; url+2 staged files + note → note on the URL unit, files noteless; small file → upload called with the STAGED url + addFile with content nil; big file (write >limit bytes) → NO upload, outbox entry with local_file_path == staged path, `.queued`; poster-throws on url → outbox `.url` entry, `queued`; location threads to every unit's attributes; enqueue-failure (unwritable outbox dir) → `failed` counted.
- [ ] **Step 2: RED**, **Step 3: Implement**, **Step 4: GREEN** (~230). **Step 5:** Commit — `git commit -am "feat(ios): ShareIntake — direct-send-with-durable-fallback orchestration (tested)"`

---

### Task 7: Extension UI + app-side wiring

**Files:**
- Create: `ios/StashShareExtension/ShareComposeView.swift`, `ios/StashShareExtension/ProviderLoader.swift`
- Modify: `ios/StashShareExtension/ShareViewController.swift`, `ios/Stash/StashApp.swift` (startup sweep + gate-cache write), `ios/StashKit/Sources/StashKit/SubscriptionStore.swift` (gate-cache write hook)

**Interfaces:**
- Consumes: `ShareIntake` (T6), `StagedFileStore`, `LocationCapture`/`buildCapturedLocation`, `AppGroup`.
- Produces:
  - `ProviderLoader`: `NSExtensionContext` → `[SharedObject]` via `loadFileRepresentation`/`loadItem` for public.url/public.plain-text/public.image/public.movie/public.audio/com.adobe.pdf; every file rep is staged immediately (`StagedFileStore.stage`) inside the callback (the temp URL dies with the callback — copy synchronously); images > 20 MB staged via `stageDownscaledImage(maxDimension: 4096, quality: 0.85)`; duration probed via `AVAsset(url:)` on the staged file for movie/audio.
  - `ShareComposeView` (prose; compact card): type-appropriate preview (favicon+URL line / text excerpt / image thumb(s) with +N / file name+icon), optional note `TextField` ("Add a note…"), location pin button (reuses the pin state machine; hidden when auth `.notDetermined` produces a hostile in-sheet prompt — verify live, disclose), Save button → progress → outcome line ("Saved to Stash" / "Saved — will sync") → `completeRequest` after 0.8s; Cancel discards staged files (`StagedFileStore.discard` each). Gate: cached-bool from `UserDefaults(suiteName: AppGroup.identifier)` key `subscription.canAddContent` — false → inline "Subscribe on gostash.it to add items" + Save disabled; missing → fail-open.
  - App side: `SubscriptionStore` gains an injectable `gateCacheWrite: (Bool) -> Void` (default writes that UserDefaults key on every resolve incl. reset) + `StashApp` startup runs `sweepOrphans` then `drainOutbox` (existing composer drain covers foreground; startup sweep is new — put it alongside).
- [ ] **Step 1:** Implement; StashKit tests for the gate-cache hook (store writes on resolve/reset — extend SubscriptionStoreTests, +2). Suite ~232.
- [ ] **Step 2:** Live extension run: share a URL from Safari → compose card preview correct → Save → item lands (REST-verify; gate: fail-open only if the cache is absent — with the lapsed account the app has CACHED false → Save disabled → verify THE GATE UI renders, REST-verify no item, and adjudicate the save-path assertion exactly like the other gate-blocked smokes). Screenshots: compose card (url + image variants), gate state. Read + describe.
- [ ] **Step 3:** Commit — `git add ios && git commit -m "feat(ios): share compose card + provider staging; startup orphan sweep + gate cache"`

---

### Task 8: Share-flow smoke (XCUITest) + drain round-trip

**Files:**
- Modify: `ios/StashUITests/StashUITests.swift`

- [ ] **Step 1:** `testShareExtensionURLSmoke`: XCUITest launches Safari (`XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")`), loads example.com, taps share, selects Stash in the activity view (springboard query — this is the finicky part; budget waits generously; if the activity-sheet automation proves unreliable after honest attempts, FALL BACK to: launch the extension host directly is impossible — so document the manual-verification protocol from T7 Step 2 as the standing evidence and mark this smoke `XCTSkip` with the reason string; disclose which outcome), types a note, asserts the gate UI OR taps Save per the account state, REST-verifies accordingly, cleans up.
- [ ] **Step 2:** `testStagedDrainRoundTrip` (no share sheet needed — pure app): write a staged file + big-file outbox entry via REST-less setup (the app's own StashKit in a launch-argument-triggered debug hook? NO — simpler: this is unit-covered in T4/T6; the UI-level version only matters post-comp. SKIP as a UI test; instead assert via unit suite + note). Replace with: extend `testCaptureSmoke`'s adjudication comment to cover the share smoke's gate state.
- [ ] **Step 3:** Full suite ×2 (expect the standing adjudicated failures; the new smoke per its disclosed outcome). Screenshots. Commit — `git add ios && git commit -m "test(ios): share-extension smoke with honest automation-fallback protocol"`

---

### Task 9: Wrap

**Files:**
- Modify: `docs/ui-changes.md`, `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md`, this plan (outcome)

- [ ] **Step 1:** StashKit full suite green (~232) warning-free; app + extension build clean; `npm test` green; UI suite ×2 per adjudications.
- [ ] **Step 2:** ui-changes.md entry: iOS share extension exists (activation types/counts, direct-vs-queue rule, note-on-first for OS-multi-shares, gate behavior, App Group/keychain sharing — written for the web/mac agents; note the mac app could adopt the same Outbox container convention someday).
- [ ] **Step 3:** Spec: phase 5 ✅; capture-surface list updated.
- [ ] **Step 4:** Outcome: date, commits, suite counts, adopted decisions of record (save-and-dismiss; 8 MB direct-send line; stream-copy big files), the extension-location-prompt observed behavior, carried items → plan-6 handoff (widgets/App Intents ride the SAME App Group + ShareIntake + gate-cache groundwork; Siri background save = App Intent calling ShareIntake; Stripe decision still pending and now gates three+share smokes; remaining carried minors). Commit.

---

## Self-review notes (done at authoring time)

- **Spec coverage:** share extension accepts URLs/text/images/PDFs/videos/audio ✓ (T5 activation + T7 loader); ~1s save w/ async enrichment ✓ (direct send, T6); Outbox fallback + "Saved — will sync" ✓; App Group + keychain sharing + one re-sign-in ✓ (T2); extension memory ceiling ✓ (T4 streaming, named requirement); camera/attachment recoverability generalization + orphan sweep (pendingRecordings caller) ✓ (T4/T7); cross-process drain claim ✓ (T3); multi-item = N items note-on-first ✓ (T6, ethos); share-time location ✓ (T7, with the honest prompt-behavior caveat); adopted decisions recorded ✓ (header + T9).
- **Type consistency:** `SharedObject`/`ShareIntake` (T6) consumed by T7; `StagedFileStore`/`uploadToStorageFromFile` (T4) consumed by T6/T7; upload-closure signature change (Data→URL) called out with mechanical call-site sweep in T4; `AppGroup` (T2) consumed everywhere; gate-cache key string identical in T7's two sites.
- **Known risks, accepted:** AuthLocalStorage protocol shape verified at execution (T2); share-sheet XCUITest automation is genuinely flaky territory — T8 carries an explicit honest-fallback protocol instead of pretending; extension location-permission UX verified live with a disclosed outcome; the lapsed-account gate keeps save-path assertions adjudicated (Stripe decision pending).
- **Ethos check:** nothing here adds a capture-time decision beyond the optional note and optional pin; failures never surface as friction (always saved-or-queued); enrichment stays entirely behind the endpoints.
