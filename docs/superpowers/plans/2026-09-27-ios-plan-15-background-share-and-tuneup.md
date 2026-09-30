# Stash iOS Plan 15: Background Share, Instant Library, and Functional Tune-up

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sharing into Stash feel instant (tap Save → confirmation → the upload finishes in the background, idempotently, with resized images), make the View tab load instantly with correct whole-card taps, and fix every parked functional bug found — without changing the look and feel.

**Architecture:** A new idempotent `capture` edge function (backed by a `capture_receipts` table) becomes the single capture entry point for iOS; every capture is persisted to the Outbox first and its entry id doubles as the server-side idempotency key, so any retry — foreground, background, or a later drain — can never create a duplicate. The share extension hands its captures to a shared background `URLSession` and quits; completion is handled by whichever process the system wakes (Apple's short-lived-extension pattern). The View tab's `ItemStore` moves to app scope with a disk-cached first page, incremental realtime updates, server search, and a caching/downsampling image loader.

**Tech Stack:** SwiftUI (iOS 17 floor), StashKit (SPM), background `URLSession` with an App Group shared container, ImageIO, Supabase Edge Functions (Deno), Postgres + RLS, XCUITest, vitest.

**Spec:** Will's 2026-09-27 request (verbatim below) + Apple DTS "Networking in a Short-Lived Extension" (developer.apple.com/forums/thread/76659) + `docs/PLATFORM_API.md` + `DESIGN.md` + `docs/ETHOS.md`.

## Global Constraints

- **Will's request (verbatim, authorized):** "let's continue to refine the app -- functionally, let's leave the look and feel alone for now. i'm having issues submitting stashed items from the sharing intent in particular. firstly, the interaction takes too long -- is there a way we can queue the interaction so that whatever the user is stashing can be done in the background? it's awkward to be somewhere and looking to stash something while waiting for it to complete. the user should click the save button, see a confirmation, and then the stash should happen in the background seamlessly. i'm also not sure we need to be stashing the full sized original image, so resizing and then sending maay reduce overall stash time. anything we can do to optimize this interaction in the share sheet would be ideal. also, currently, the share sheet looks a little strange with the logo cut off slightly. if you could look at this that would be great. let's also ditch the gradiennt background. submitting on wifi is basically instantaneous, on cellular it's sigifnicantly slower." / "when using the 'view' screen, the tap targets are off for some reason. when tapping the bottom of the first item in the list, it often chooses the second item by mistake ... We should just make the entirety of the cards tappable, and when someone taps on any area of the card, it opens the detailed view. We don't need multiple tap targets in the card on the mobile app for right now if somebody wants to add a note or edit a detail of the card, they can just open the detailed view rather than doing it in place. Let's also make the screen load as quickly as possible potentially cashing the first few items and only polling for new items when the view i in place or when the user opens the app by default or foregrounds the app. The view should be ready to go by the time the user taps the tab ... Do an overall tuneup of the functionality of the app to be sure that it is feeling first rate, snappy, highly functional, and well-made. If there are any bugs that have been parked for later, let's resolve them now."
- **Look and feel stays.** No palette/type/layout redesigns. The only visual changes allowed: (a) the share sheet loses its gradient backdrop (plain `StashColor.paper`) and its header gets enough top/leading inset that the wordmark is never clipped by the sheet's rounded corners on iOS 26; (b) removing in-card interactive affordances (see "Whole-card tap"). DESIGN.md tokens only; 1px strokes; no emoji; light-only lock.
- **Server state (production) — DO NOT redeploy `add-note`, `add-url`, `add-file`, or `transcribe-audio`.** Production is drifted from `main`: `add-note` v52 came from the unmerged paywall branch (it is the only function that returns `403 {"error":"subscription_required"}` for lapsed accounts), `add-url` v68 / `add-file` v15 came from `main`. Redeploying any of them from this branch would silently change production behavior. The main checkout also holds another session's uncommitted edits to `supabase/config.toml`, `supabase/functions/add-url/index.ts`, `supabase/functions/_shared/{linkFlavor,summarize}.ts`, `extract-office-text`, `extract-pdf-text`, `generate-embeddings`, `retry-pending-scrapes`, `scrape-page-content`, `src/utils/linkFlavor.ts`, `.gitignore`, `docs/superpowers/prototypes/README.md` — this branch must NOT modify any of those files (the final merge would collide with that WIP).
- **`capture` endpoint contract (new, Task 1):** `POST /functions/v1/capture`, headers `Authorization: Bearer <user JWT>` + `apikey: <anon key>`. Body is either `application/json` (the meta object) or `multipart/form-data` with a `meta` part (the JSON string) and a `file` part (bytes). Meta: `{ capture_id: uuid (required, client-generated, lowercase), kind: "note"|"url"|"file", content?: string, title?: string, url?: string, is_public?: bool (default false), attributes?: object (forwarded verbatim), remind_at?: string (forwarded verbatim), mime_type?: string (required for file), file_name?: string, file_size?: int, file_path?: string (file kind without a multipart part — an already-uploaded object that MUST start with "<uid>/") }`. Behavior: authenticate (401), reject agent tokens (403, `_shared/agentToken.ts`), validate (400); reserve an idempotency receipt; for a multipart file upload the bytes to `stash-media/<uid>/<capture_id>.<ext>` with `upsert: true` (ext from `file_name`, else a mime map, else `bin`); forward to the existing `add-note`/`add-url`/`add-file` endpoint with the caller's own `Authorization` + `apikey` and that endpoint's existing body shape; normalize the downstream item (`body.item ?? body.note ?? null`). Responses: `200 { item: <row>|null, duplicate: bool }`; downstream non-2xx is returned verbatim (status + body — `403 subscription_required` passes through); `409 { error: "capture_in_progress" }` when another attempt with the same id is in flight; `413 { error: "file_too_large" }` for a multipart body over 45 MiB (the client then uses `file_path` mode). Receipt rules: `done` receipt → return its item (fresh `select` of the row; `null` if the user deleted it) with `duplicate: true` and NO new item; `pending` receipt younger than 120 s → 409; `pending` older → take over (bump `updated_at`) and proceed; downstream failure → delete the receipt so a retry can proceed. Never modify `add-*`.
- **`capture_receipts` table (new, Task 1):** `(user_id uuid not null references auth.users(id) on delete cascade, capture_id uuid not null, item_id uuid references public.items(id) on delete set null, status text not null default 'pending' check (status in ('pending','done')), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), primary key (user_id, capture_id))`; RLS enabled; owner-only select/insert/update/delete policies (`auth.uid() = user_id`). The function uses the caller's JWT (RLS applies) — no service role. Migration file `supabase/migrations/20260927120000_capture_receipts.sql`, applied to production via the Management API and recorded in `supabase_migrations.schema_migrations` (see `/Users/will/.claude/projects/-Users-will-Appdev-embed-link-spark/memory/deploy-process.md`).
- **Idempotency key = Outbox entry id.** Every iOS capture (composer, voice note, share extension) is written to the Outbox FIRST and sent with `capture_id = entry.id.uuidString.lowercased()`. A retry of the same entry, from any process, at any time, can never create a second item. Existing on-disk entries from older builds already carry UUID ids and need no migration.
- **Outbox states:** `pending`, `parked` (unchanged — 403 subscription_required), and NEW `transferring` (a background transfer owns it) with `transferStartedAt: Date?` (decode-if-present; older JSON decodes unchanged). `drain` sends `pending` entries and `transferring` entries whose `transferStartedAt` is nil or older than `Outbox.staleTransferInterval = 600` s (the server dedupes if the transfer actually landed); it never sends `parked`. On `409 capture_in_progress` the entry stays `pending` with `attempts` unchanged.
- **One-shot vs two-step files:** a `.file` entry with `local_file_path` ≤ `CaptureAPI.oneShotFileLimit = 45 * 1024 * 1024` bytes is sent as ONE multipart request to `capture` (the multipart body is written to a scratch file by streaming the source in chunks — never a whole-file `Data` load); larger files upload to storage first at the deterministic path `<uid>/<entryId>.<ext>` with header `x-upsert: true`, the entry is checkpointed with `file_path` (existing checkpoint semantics), then a JSON `capture` call registers it.
- **Image preparation (all iOS image captures — composer photos, camera, share extension):** StashKit `ImagePreparation` (ImageIO only, no UIKit). Longest edge ≤ 2560 px, JPEG quality 0.82, EXIF orientation applied, all other metadata (GPS, device) dropped, alpha composited onto white. Keep the original bytes untouched for GIF (animation) and for a JPEG that is already ≤ 2560 px AND ≤ 2 MiB. Output mime `image/jpeg`, extension `jpg`. The original `file_name` is kept in `attributes.media.file_name` (extension swapped to `.jpg` when re-encoded).
- **Background transfers (share extension, Task 4):** one shared background session id `it.gostash.stash.capture-transfers` used by BOTH app and extension, `sharedContainerIdentifier = AppGroup.identifier`, `isDiscretionary = false`, `sessionSendsLaunchEvents = true`, `timeoutIntervalForResource = 3600`. Request body files live in the App Group under `StashTransfers/`. `taskDescription = "<userId-lowercased>|<entryId-lowercased>|<phase>"` with phase `capture` or `storage`. The extension starts tasks and quits (`completeRequest`) — it never waits for completion. Completion handling code lives in StashKit and runs in whichever process gets the events: 2xx `capture` → delete entry + staged file + body file and (in-app) post `.stashItemCaptured`; 2xx `storage` → checkpoint `file_path` then immediately start a `capture` task (JSON, file_path mode) in the same session; `403 subscription_required` → park; `409` → `pending`; anything else → `pending`, `attempts += 1`. The app implements `application(_:handleEventsForBackgroundURLSession:completionHandler:)` via `@UIApplicationDelegateAdaptor`: store the handler, connect the session, process events, and on `urlSessionDidFinishEvents` call the handler and `finishTasksAndInvalidate()` so the app never stays connected (only one process may connect at a time). The app does NOT connect to the session at ordinary launches — stale `transferring` entries are resent idempotently by `drain` instead.
- **Share sheet flow (Task 4):** image downscaling happens while the card is showing (at stage time in `ProviderLoader`), not after Save. Save → persist entries as `transferring` → start background tasks → show the existing done state ("Saved to Stash", success checkmark) → `completeRequest` ~0.8 s later. If the access token expires within 5 minutes it is refreshed before tasks start, bounded to 2.5 s total; on timeout the entries flip to `pending` for the app. If the background session is unavailable (`NSURLErrorBackgroundSessionInUseByAnotherProcess` or any creation failure) the entries flip to `pending` and a bounded (≤ 6 s) foreground send runs before dismissal. The user always sees a confirmation, never an error, never a spinner longer than the confirmation window. Any file type is accepted (generic `public.data` staging — `add-file` already routes documents).
- **Whole-card tap (Task 3):** on iOS a card is ONE tap target that opens the detail sheet. Remove `CardNoteView`'s tap handling and the "Add a note" affordance, delete `CardNoteEditorSheet.swift`, and remove the kicker's external-link icon (the detail sheet's URL bar already opens links). Keep the note's existing static rendering (violet rule, 5-line clamp). Hit testing must match what's drawn: `.contentShape(RoundedRectangle(cornerRadius: StashRadius.card))` on the card button label and `.allowsHitTesting(false)` on hero imagery overlays (fill-scaled images and the 1.25× blurred backdrop currently overflow their clipped frames and steal taps from the card above — the reported bug). Web keeps its in-card note editor; record the iOS difference in `docs/ui-changes.md` and DESIGN.md's card-note section.
- **Instant library (Task 3):** `ItemStore` is created once per signed-in session at app scope (not inside `LibraryView`), hydrated synchronously from a per-user disk cache of the first page (`Caches/StashItemCache/<uid>.json`), refreshed at sign-in, on foreground (if the last refresh is older than 30 s), and on View-tab appear (same 30 s rule), and kept live by an app-scope realtime observer that applies changes incrementally (insert/update → re-fetch just those ids with `Item.listColumns`; delete → remove) instead of re-fetching page 1 and dropping loaded pages. `refresh()` merges page 1 into the loaded list (never truncates older pages). The cache file is deleted on sign-out and account deletion. Captures posted via `.stashItemCaptured` are prepended immediately.
- **Images (Task 3):** one app-wide loader with an in-memory decoded-image cache and a disk-backed `URLCache`, decoding with ImageIO downsampling to the display size (never a full-resolution `UIImage(data:)` of an original photo), used by every card hero and the detail hero; the first 10 hero images are prefetched after each first-page load.
- **Search (Task 3):** the View tab uses the `search-items` edge function (web parity, `src/hooks/useServerSearch.ts`: 300 ms debounce, ≥ 2 chars, limit 50, relevance order), fetching result rows by id with `Item.listColumns`; the instant local filter shows while the server request is in flight or if it fails.
- **Title fallback (Task 3):** when an item's title is a UUID object name or a storage timestamp name (port `isUuidObjectName`/`isStorageTimestampName` from `src/utils/titlePolicy.ts`), cards show a type label instead ("Voice note" for audio, "Photo" for image, "Video", "File"). Display-only; never written back.
- **Attributes must round-trip loss-lessly at every level (Task 5):** `location`, `link`, and `media` keep unknown nested keys (the server writes e.g. `media.kind`, `media.transcript`) so an iOS whole-blob attributes write can never delete them.
- **Process:** file ownership per task is listed in each task; never edit a file owned by another concurrently-running task. Distinct simulators and derived-data paths per concurrent builder; max 2 concurrent `xcodebuild` users. `swift test` must use a private scratch path (`swift test --package-path ios/StashKit --scratch-path /tmp/sk-<task>`) so concurrent runs don't contend for `.build`. New StashKit files need no `xcodegen`; a new app/extension file does (`cd ios && xcodegen generate`, then build). UI-test env: EXPORTED `TEST_RUNNER_*` from `ios/.env.test.local` (never print secrets). Standing gate-blocked UI failures on the lapsed `will+uitest` account: `testCaptureSmoke`, `testLocationPinSmoke`, `testAskSmoke`, `testDeleteSmoke`, `testLocationEditSmoke` (confirm each fails on the gate, not elsewhere). `UITEST-FIXTURE` rows are permanent; throwaway rows must be deleted in teardown. Commit trailer: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Never push; never print credentials.

---

### Task 1: `capture` edge function + `capture_receipts` (server)

**Files:** Create `supabase/migrations/20260927120000_capture_receipts.sql`, `supabase/functions/capture/index.ts`, `supabase/functions/_shared/capture.ts` (pure logic: meta validation, extension mapping, receipt decision), `supabase/functions/_shared/capture.test.ts` (vitest, `// @vitest-environment node`). Modify `docs/PLATFORM_API.md` (new `capture` section). Nothing else.

- [ ] Pure helpers + vitest tests: `parseCaptureMeta(raw)` (every required/optional field, uuid check, kind check, file_path prefix check), `fileExtensionFor(fileName, mimeType)`, `decideReceipt(existing, now)` → `proceed | duplicate(itemId) | inProgress | takeOver`, `downstreamPathFor(kind)`, `downstreamBodyFor(meta, storedPath)`.
- [ ] Migration SQL (idempotent: `create table if not exists`, `drop policy if exists` before each `create policy`); apply to production via the Management API; record the version.
- [ ] `index.ts`: CORS/OPTIONS, POST only, auth, agent-token reject, content-length guard (413), JSON or multipart parse, receipt reserve (`insert … ` with unique-violation → 409), storage upload (multipart), forward, normalize, receipt finalize/delete, verbatim error passthrough. Uses only unmodified `_shared` files.
- [ ] Deploy: `supabase functions deploy capture --project-ref uqqsgmwkvslaomzxptnp` from this worktree (default `verify_jwt = true`; do NOT touch `supabase/config.toml`). Verify with `supabase functions list`.
- [ ] E2E smoke against production with the `will+uitest` account (script in /tmp, creds from `ios/.env.test.local`, never echoed): url capture → 200 new item; same capture_id again → 200 `duplicate: true` with the same item id and no second row; note capture → 403 subscription_required passthrough (lapsed account) and no leftover receipt; multipart PNG → image item with `file_path = <uid>/<capture_id>.png`; repeat → duplicate; file_path mode → 200; missing capture_id → 400. Delete every row/object the smoke created. Record transcripts (status codes, ids) in the report.
- [ ] `docs/PLATFORM_API.md`: document the endpoint, idempotency, error table, one-shot limit.
- [ ] Commit `feat(platform): idempotent capture endpoint + capture_receipts (iOS background share groundwork)`.

### Task 2: StashKit capture core — outbox-first, idempotent, resized

**Files:** Modify `ios/StashKit/Sources/StashKit/{CaptureAPI,Outbox,CaptureViewModel,ShareIntake,StagedFileStore}.swift`; create `ios/StashKit/Sources/StashKit/{ImagePreparation,CaptureTransport}.swift` (+ tests under `ios/StashKit/Tests/StashKitTests/`); modify `ios/Stash/Capture/CaptureComposerView.swift` (drop the app-side `downscaleImageData`, wire the new view-model init) and `ios/StashShareExtension/ProviderLoader.swift` (stage every image through `ImagePreparation`; accept any file type via `public.data`). Do NOT edit `StashApp.swift`, `MainTabView.swift`, anything in `Library/`, `ItemStore.swift`, `StashUITests.swift`.

- [ ] `ImagePreparation` (Data-based for the composer, file-based `StagedFileStore.stagePreparedImage(from:)` for the extension) with tests (orientation, >2560 downscale, small JPEG passthrough, GIF passthrough, alpha → white, metadata stripped).
- [ ] `CaptureTransport`: builds the JSON or streamed-multipart request for an Outbox entry (body written to a scratch file), and the storage request for two-step files (deterministic path, `x-upsert: true`); an injectable `CaptureTransporting` protocol so tests stub the network.
- [ ] `CaptureAPI.submit(entry:userId:accessToken:)` → `CaptureResult { item: Item?, duplicate: Bool }`; error mapping: 403 subscription_required → `.subscriptionRequired`, 409 → new `.inProgress`, other → `.badStatus`. Keep the legacy `addNote/addURL/addFile` methods untouched (the Ask tab's chat-as-capture still uses them).
- [ ] `Outbox`: `transferring` status + `transferStartedAt`, `staleTransferInterval`, `enqueue` returns the entry (`@discardableResult`), `sendNow(id:api:userId:accessToken:upload:)` for a single claimed send, `drain` routed through `api.submit` with the one-shot/two-step split (keep the existing `drain(api:accessToken:userId:upload:)` signature source-compatible — `upload` becomes the two-step storage lane), and helpers the Task 4 delegate needs: `markTransferring(ids:)`, `markPending(id:incrementAttempts:)`, `park(id:)`, `complete(id:)` (deletes entry + claim + local file). Tests for every transition incl. back-compat decode of old entries.
- [ ] `CaptureViewModel`: outbox-first (`stage` attachment bytes to disk via `StagedFileStore`, photos through `ImagePreparation`, enqueue, `sendNow`); on success post `Notification.Name.stashItemCaptured` (declare it in StashKit, `userInfo["item"]`); network failures now queue instead of dropping (only size-limit/staging failures are `.rejected`). Voice notes enqueue their recording file then `sendNow`. Tests updated/added.
- [ ] `ShareIntake`: same outbox-first path (foreground `sendNow`, fall back to queued) so the extension keeps working before Task 4; expose `enqueueForTransfer(_:note:location:) -> [OutboxEntry]` (status `transferring`) for Task 4.
- [ ] `ProviderLoader`: every image staged via `stagePreparedImage`; any other file type staged generically (`public.data`, keep the specific image/movie/audio/pdf branches first) with mime from `StagedFileStore.mimeType(forFileExtension:)`.
- [ ] Verify: `swift test --package-path ios/StashKit --scratch-path /tmp/sk-t2`; app + extension build warning-free; live composer capture of a link and a photo on sim `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` (derived data `DerivedData-t2`) produces exactly one item each (REST check), the photo row's stored object is a ≤ 2560 px JPEG; delete throwaway rows. Report any EXISTING UI test your change breaks (do not edit `StashUITests.swift`).
- [ ] Commit `feat(ios): outbox-first idempotent captures via capture endpoint; resized image uploads`.

### Task 3: Instant, correctly-tappable View tab

**Files:** Modify `ios/Stash/Library/*`, `ios/Stash/MainTabView.swift`, `ios/Stash/StashApp.swift`, `ios/Stash/Auth/SessionStore.swift` (cache purge only), `ios/Stash/Detail/ItemDetailView.swift` (hero image loader swap only), `ios/StashKit/Sources/StashKit/{ItemStore,RealtimeObserver}.swift`, `ios/StashUITests/StashUITests.swift`, `DESIGN.md` (card-note iOS note); create `ios/StashKit/Sources/StashKit/{ItemCache,ItemDisplay,SearchAPI}.swift` (+ tests), `ios/Stash/Design/CachedImage.swift` (loader + view). Delete `ios/Stash/Library/CardNoteEditorSheet.swift`. Do NOT edit capture/Outbox/extension files.

- [ ] Hit-testing fix + whole-card tap (see Global Constraints) with a UI test that taps the bottom 10 pt of card 0 and asserts card 0's detail opened (repeat for card 1), plus removal of the card-note editing test.
- [ ] `ItemCache` (per-user JSON, encode/decode round trip with `Item.decoder`-compatible dates, atomic write, delete) + tests; `ItemStore` app-scope lifecycle, synchronous hydrate, merge-refresh, staleness rule, incremental apply API (`upsert(_:)`, `remove(ids:)`), `.stashItemCaptured` observer, and tests (merge keeps older pages; stale results dropped via the generation token; deletes applied).
- [ ] `RealtimeObserver`: decode `AnyAction` (insert/update/delete), coalesce ids for 400 ms, re-fetch only those ids; runs at app scope for the signed-in user.
- [ ] `CachedImage` loader (memory NSCache of downsampled images + `URLCache` 50 MB/300 MB in Caches, ImageIO downsampling to target pixel size, cancellation-safe, prefetch API) replacing `AsyncImage`/raw `URLSession.shared.data` in card heroes and the detail hero; prefetch first 10 heroes after first-page loads.
- [ ] `SearchAPI` (`search-items`, ids → rows by id, relevance order preserved) + tests; `LibraryView` wiring with the local filter as instant fallback.
- [ ] `ItemDisplay.displayTitle` title fallback + tests; cards use it.
- [ ] Verify: `swift test --package-path ios/StashKit --scratch-path /tmp/sk-t3`; builds warning-free; on sim `46D4EA93-94D5-451E-AC61-A5485AFB211F` (`DerivedData-t3`): cold launch with a warm cache shows cards with no spinner (screenshot), tab switch is instant, tapping the bottom edge of each of the first 5 cards opens that card (UI test), search for a term only present in an older item's page_body returns it (fixture-based if possible), library smokes green (`testLibrarySmoke`, `testCardAnatomySmoke`, `testDetailSheets`, `testEditSmoke`, `testPublicSmoke`).
- [ ] Commit `feat(ios): instant View tab — app-scope cached store, incremental realtime, server search, image cache, whole-card taps`.

### Task 5: Loss-less nested attributes (StashKit models)

**Files:** Modify `ios/StashKit/Sources/StashKit/Models/ItemAttributes.swift` and its tests only.

- [ ] `CapturedLocation`, `LinkAttributes`, `MediaAttributes` each preserve unknown keys (an `extra: [String: JSONValue]` captured on decode and written back on encode); fix the doc comment that claims nested loss is impossible; tests: round trip with `media.kind`, `media.transcript {status, …}`, unknown link/location keys; a location edit (replace `location`) keeps every `media`/`link` key byte-identical.
- [ ] `swift test --package-path ios/StashKit --scratch-path /tmp/sk-t5`. Commit `fix(ios): attributes round-trip nested keys loss-lessly (media.transcript, media.kind no longer dropped on edit)`.

### Task 4: Background share transfers + share-sheet polish

**Files:** Create `ios/StashKit/Sources/StashKit/BackgroundCaptureTransfers.swift` (+ tests for the pure completion-decision logic); modify `ios/StashShareExtension/{ShareComposeView,ShareViewController,ProviderLoader,Info.plist}.swift/plist`, `ios/StashKit/Sources/StashKit/ShareIntake.swift`, `ios/Stash/StashApp.swift` (app delegate adaptor only), `ios/StashUITests/StashUITests.swift` (share smoke only). Depends on Tasks 1–3.

- [ ] Session + delegate per Global Constraints; `start(entries:userId:accessToken:)`; completion decision function unit-tested (2xx capture/storage, 403, 409, 5xx, transport error, unknown entry id → no-op).
- [ ] App delegate adaptor handling `handleEventsForBackgroundURLSession`.
- [ ] Extension Save flow (instant confirmation, background start, token refresh bound, in-use fallback), gradient removed, header inset fixed (verify on the iOS 26.5 sim `503F19C5-0145-4210-B524-6B5EA5D16E50`, screenshot), activation rule accepts any file type (keep counts: images ≤ 10, movies ≤ 3, files ≤ 5).
- [ ] Verify on device-like conditions: share a link and a large photo from Safari/Photos on the sim with Network Link Conditioner-style throttling if available (else just timing) — confirmation appears in < 1 s after tapping Save; the item lands server-side exactly once (REST check) even when the extension is dismissed immediately; kill the app, share, relaunch — no duplicate. Screenshots of the compose card and the confirmation on iOS 26.5.
- [ ] Commit `feat(ios): share sheet saves in the background — instant confirmation, resized uploads, no gradient, header inset`.

### Task 6: Audit fix wave

Source: `/tmp/stash-ios-audit-2026-09-27.md` (copied to `.superpowers/sdd/plan-15/audit.md`). Four file-disjoint groups, scheduled around Tasks 2–4:

- **6A — Ask** (starts during round 1; owns `ios/Stash/Ask/*`, `ios/StashKit/Sources/StashKit/Chat/*`, `MessageRouting.swift`, their tests, `ios/Stash/Design/StashType.swift`): H4 (stream bound to its conversation; cancel/guard session switches mid-stream), M11 (remove chat-as-capture — the 2026-08-27 all-platform decision in `docs/ui-changes.md` "Mole is retrieval-only"; placeholder "Ask your stash…"; this also retires M4), M1 (coalesce deltas ~10 Hz, equatable bubbles, memoized markdown blocks), M2 (auto-scroll only when near bottom or on send), M3 (read-aloud strips markdown/citations like web `stripForSpeech`; `.playback`/`.spokenAudio` session), L1 (no-`done` stream finalizes; keep partial text + retry per the iOS spec), L2 (banners clear/dismiss), L3 (early-send race), L10 (`.scrollDismissesKeyboard(.interactively)`), snappiness: surface server `status` SSE events as "Searching your stash…" in the placeholder bubble, `StashType.isNeueMontrealAvailable` as a `static let`, conversation-search cancellation (M6's Conversations half).
- **6B — Detail** (after Task 3; owns `ios/Stash/Detail/*`, `ItemEditor.swift`, `EmbeddingRefresher.swift`, `TranscriptionService.swift`, new `PendingEdits.swift`): H5 (dismiss immediately; unsaved/failed edits go to a durable per-user pending-edits queue drained on foreground/launch, latest-wins per field), M5 (no spinner over an existing summary; skip redundant detail fetches), M8 (failed location edit surfaces + queues), M9 (long timeout for "Transcribe with speakers"), M10 (drop the client delete-before-regenerate after verifying the deployed `generate-embeddings` replaces rows itself), L4, L5, L6, L9.
- **6C — Session, subscription, Settings, auth** (after Tasks 3 and 4 — shares `StashApp.swift`/`SessionStore.swift`): H1 (sign in from the stored session; offline launch never shows the sign-in screen), H2 (`statusKnown` fail-open, web parity; cache written only on a definitive answer), M6 (Settings cancellation errors), L7, L8 (`.newPassword` + Return chain; no associated-domains change), snappiness: per-session profile cache and a foreground subscription-check throttle.
- **6D — Composer UI** (after Tasks 2 and 4 — shares `CaptureComposerView.swift` and `project.yml`): H3 (idle timer off while recording + `UIBackgroundModes: audio`; interruption notice), M7 (attachment loads off the main thread, one photo transfer, downsampled chip thumbnails, pending chip + failure feedback).

### Task 7: Wrap

- [ ] Merge `origin/main` (audit foreign commits first); `docs/ui-changes.md` top entry "2026-09-27 · iOS background share, instant library, tune-up (plan 15)" (contracts-first: capture endpoint + idempotency, whole-card tap on iOS vs web's inline editor, image preparation policy, search parity, title fallback); plan Outcome; DESIGN.md note.
- [ ] Suites: `swift test`, `npm test`, both targets warning-free, UI suite ×2 (only the standing gate-blocked set may fail).
- [ ] `CURRENT_PROJECT_VERSION` stays 10 (build 10 was archived but never uploaded); `release.sh all` → upload → VALID → attach both TestFlight groups → attach to App Store version `c5b26d42-dcd6-466f-abd4-d91d37cf6d59`. STOP with the exact message if the Xcode session expired.

## Outcome

**Commits (branch `worktree-ios-plan-15`, base `cd6cb6cf` = `origin/main`, not pushed):**

- `e493e44b`, `a5862dca` — the plan, then the audit's fix-wave groups (6A–6D).
- `f182e244` — T5: `location`/`link`/`media` keep unknown nested keys, so iOS edits no longer
  delete `media.kind`/`media.transcript`.
- `66879312` + fix `66265a3b` — T1: `capture` edge function (deployed, v5) + `capture_receipts`
  (migrations `20260927120000`/`20260927130000` applied to production and recorded). Fix:
  `attempt_id` fencing with a compensating delete of a superseded attempt's duplicate, release
  retries, 1 MiB meta cap (`413 meta_too_large`), multipart drain on parse failure.
- `361fe12f` + fixes `f93f26c9`, `7cc02312` — T2: outbox-first idempotent captures
  (`capture_id` = Outbox entry id), `ImagePreparation`, composer failures queue, 10 MiB
  one-shot / two-step. Fixes: the whole batch on disk before any send, file-before-entry
  deletion, dead-pid claims reclaimed, RAW-safe resize, GPS stripped from passthrough JPEGs,
  413 → two-step; then subsampled decode for big sources (extension memory).
- `61306900` + follow-up `ec596b63` — T3: instant View tab (app-scope per-user store + disk
  cache, incremental realtime, `search-items`, one downsampling image loader, whole-card taps,
  title fallback). Follow-up: literal-first ranking on displayed plain text; cache-hit path.
- `f7c008b2` + fix `e8c8f83c` — 6A Ask: answers bound to their conversation, retrieval-only,
  ~10 Hz coalesced streaming, follow-scroll, clean read-aloud, partial answer + Retry.
- `948ac939` + fix `81a7b7ca` — 6B Detail: durable per-user PendingEdits, instant summary,
  honest load failures, Generate summary, location failure surfaced + queued.
- `eecf4c4d` + fix `835ac164` — T4: background share transfers, instant confirmation, no
  gradient, header inset. Fix: 401 → fresh token + one restart, no extension retention, 3900 s
  stale bound for storage uploads, confirm-first Save with a late pin.
- `8388bdbe` — 6D composer: recordings survive auto-lock (`UIBackgroundModes: audio`), off-main
  attachment loading, one-pass thumbnails.
- `4fda7d3d` — 6C session/settings: stored-session launch, no anonymous requests while signed
  in, gates fail open until known, honest delete timeout, `.newPassword` sign-up.
- `61aa91e0` + follow-up `b30ca2e9` — final wave A: accurate privacy manifests, 30-min staging
  sweep grace (copied files stamped `mtime = now`), enqueue-first composer, owner-token drains,
  one bounded token fetch per background wake, recorder finalized on terminate.
- `1ec68d19` — final wave B: `ContinuousClock` instead of `systemUptime` (no boot-time API) +
  `BootTimeAPIUsageTests`, location read-merge, transcription as the server job, chat 403 gate
  copy, the "Modifying state during view update" warning fixed (7 → 0).
- `8f323eb5` — T7: a transcription job that ended `failed` says so ("No speech was detected in
  this recording." / "Couldn't transcribe this recording.") instead of "Transcription in
  progress…" forever; unit test + `DetailUITests.testAFailedTranscriptionSaysSoInsteadOfInProgress`
  (fails on the old copy).
- (this commit) — docs: this Outcome, the `docs/ui-changes.md` entry, DESIGN.md share-sheet
  wash note, PLATFORM_API paywall note, App Review background-audio sentence.

**Merge:** `origin/main` has not moved since the base (`cd6cb6cf`, 2026-09-18), so nothing was
merged. Will's local `main` carries 30 unpushed commits (the 2026-09-29 merge wave: long-audio
transcription, reminders email, Ask notes-in-search, logo refresh, enrichment quality loop, and
`9ee0a4af` relabelling "Transcribe with speakers" to "Transcribe again" on web + iOS). A trial
`git merge-tree` of this branch with that `main` conflicts in `docs/PLATFORM_API.md` and
`ios/StashKit/Sources/StashKit/TranscriptionService.swift`. The build uploaded from this branch
has none of those commits (old app icon and wordmark, "Transcribe with speakers").

**Reviews:** every unit had an opus review. T5 APPROVE. T1 NEEDS FIX (no fencing) → APPROVE.
T2 NEEDS FIX → APPROVE (after the memory follow-up). T3 APPROVE (+ small follow-up). 6A NEEDS
FIX (follow-scroll) → APPROVE. 6B NEEDS FIX (anon-fallback PATCH, citation overlay) → APPROVE.
T4 APPROVE with pre-release fixes → APPROVE. 6D APPROVE. 6C APPROVE. Whole-branch review
(contracts checked against the 15 deployed functions): READY FOR FINAL FIX WAVE → FW-A NEEDS
FIX (ship gate + mtime) → APPROVE; FW-B APPROVE (its one LOW carried into T7).

**Key decisions:**

- `capture` wraps `add-*` and never modifies them (production drifted from `main`); only iOS
  uses it. The Outbox entry id is the `capture_id`, so every retry path can resend blindly.
- iOS one-shot limit 10 MiB (the gateway buffers the whole body and caps requests at 150 s);
  the server accepts 45 MiB. Larger files go two-step to a deterministic storage path.
- Image policy: ≤ 2560 px, JPEG 0.82, orientation applied, all metadata incl. GPS stripped;
  sources above 2560 px decode subsampled (factor 2/4/8, target ≥ 1600 px) to stay under the
  extension's ~120 MB ceiling.
- Share sheet: confirmation first; the pin, token refresh and upload never hold it. Gradient
  removed (Will, 2026-09-27). `isModalInPresentation` removed (didn't block swipe-down; entries
  persist before the confirmation, so a swipe is harmless).
- View tab: one tap target per card (web keeps its inline note editor). Search is literal-first
  on displayed plain text, then server relevance: an intentional divergence from web.
- Ask is retrieval-only on iOS (the 2026-08-27 all-platform decision).
- Subscription gates fail open until the server gives a definite answer; only open answers
  are cached (180 s).
- Transcription runs as the server's job (`{itemId, rebuild: true}`); the client never writes
  `page_body`/`description`, so the new `protect_enrichment_edits` trigger stays accurate.
- No boot-time API (`ContinuousClock`), so the manifests declare only UserDefaults (app CA92.1
  + 1C8F.1; extension 1C8F.1) and file timestamps (C617.1).

**Measured:**

- Share Save → confirmation ~50 ms in the extension (26–76 ms across iOS 17.5/26.5 runs; UI
  test observed 0.47–0.92 s end to end); the sheet closes ~0.8 s later. Background proof: app
  terminated + extension force-exited 150 ms after hand-off → the system launched the app in
  the background, the item landed once, the Outbox emptied.
- Mis-taps: bottom-edge taps opened the card below 5/5 before, the right card 5/5 after.
- Tab tap → first card 0.21 s → 0.04 s; cold launch → first card 0.74 s → 0.33 s (disk cache).
- 12 MP photo upload 6.2 MB → ~1.5 MB (T2's live check stored 1.48 MB; after the subsampled
  decode a 12 MP photo stores at 2016×1512).
- Image-prep decode peaks after subsampling: 12 MP JPEG 90 → 30 MB, 12 MP HEIC 117 → 50 MB,
  48 MP JPEG 102 → 30 MB, 48 MP HEIC 109 → 47 MB. Extension process peaks: 12 MP JPEG from
  Photos 49 MB, 12 MP HEIC from Photos 48 MB, a HEIC original from Files 85.5 MB (in a process
  reused for two earlier shares).
- Transcription job (live smoke): 202 in 0.56 s, done in ~10 s, no protected fields written.
- "Modifying state during view update": 7 per UI run → 0.

**Server follow-ups for Will:**

- `transcribe-audio` v28 (MED, data loss): a rebuild that hears no speech writes
  `page_body = null` before failing `no_speech`, so the old transcript is lost. It also has no
  guard against a second concurrent rebuild (iOS never starts one).
- Web "Transcribe with speakers" (`TranscriptContent.tsx` on `origin/main`) still uses preview
  mode + a user-token PATCH, so the trigger marks `page_body`/`description` as user edits.
  Move it to the job (`{itemId, rebuild: true}`) like iOS.
- `add-note` answered its paywall 403 before reading the body (v52), so bodies over ~0.5 MiB
  got a gateway 504 after ~160 s. Re-check on the redeployed v53.
- Location edits: iOS read-merges `location` onto the current attributes, but a server write
  between that read and the PATCH can still be lost. A server-side jsonb merge would close it.
- `capture_receipts` is never pruned (one small row per iOS capture). Add a periodic delete of
  old `done` receipts.
- Web: `stripForSpeech` reads bare citation ids aloud; chat `status` frames ("Searching your
  stash…") and the status-aware empty Transcript copy are worth adopting.
- Production runs ~21 functions redeployed 2026-09-29 05:50–05:57Z from code not on
  `origin/main`. Reviewing and pushing the local `main` merge wave would realign them.
- Comp `will+uitest` (every capture/Ask smoke is gate-blocked) and make sure the App Review
  demo account `will+review` is entitled before submitting.

**Device checks still owed (simulator can't prove these):**

- Voice memo: record → lock ~1 min → unlock → still recording (the simulator passed even
  without the background-audio key).
- Voice memo: record → swipe the app away → relaunch → the recording lands and plays.
- Share on cellular: confirmation timing, and swipe-down during the hand-off.
- iOS 26 device: the share-sheet wordmark and X clear the sheet corners (inset sized for
  ≤ 60 pt corners).
- One 48 MP HEIC share (simulator HEIC decode is software, so the device peak is unmeasured).

**Carried / accepted LOWs:**

- T1: if the compensating delete fails 3× after a takeover, one duplicate item remains (logged).
- T2: two in-app drains can both reclaim a dead claim → a concurrent double send (the server
  dedupes). A 2561–3199 px source still peaks ~82 MB in the extension (factor-1 decode). RAW
  preview minimum 1024 px (nit).
- T3: deletes from another device appear on the next refresh (realtime can't filter DELETE by
  user). Portrait heroes render cropped vs DESIGN.md's "contained" (pre-existing).
- 6B/FW-B: location read-merge gap vs a concurrent server write (above). A user-started
  transcription keeps polling up to 30 min after its sheet closes (bounded).
- 6C: a user whose refresh fails for a non-cleanup reason (e.g. banned) stays signed in.
  UI-test launches use `.password` because the strong-password UI swallows typed text
  (`.newPassword` proven in Release by screenshot). Keychain unreadable at launch (narrow).
- 6D: large attachments still load as `Data` in memory (needs a StashKit file-reference
  attachment). ComposerUITests' "Save waits" assertions skip under the gate.
- T4: if a drain overlaps the late-location window, the pin can be dropped (rare).
- FW-A: microsecond gap between `copyItem` and the mtime stamp; a straggler completion can
  repopulate the token cache (≤ 60 s TTL).
- T7: a stale `pending`/`processing` status (> 20 min) and legacy rows with no status still
  read "Transcription in progress…" (the server's sweep resumes them). While the v28 no-speech
  wipe exists, an open sheet keeps showing the old transcript until reopened, because the merge
  keeps a local `page_body` when a row arrives without one.
