# Stash iOS — Plan 4: Object-model parity (2026-08-16 web rework alignment)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Absorb the web's single-object/attributes/object-first-card rework into the platform API and the iOS app: `attributes` flows through the capture endpoints (with server-side link-flavor classification — fixing the web's own chat-capture gap), capture batches put the note on the first item, location is a first-class opt-in attribute, and cards follow the object-first anatomy.

**Architecture:** The web writes `attributes` via client-side inserts only; API consumers (iOS, web ChatMole) can't. This plan makes the three capture endpoints the canonical attribute path (accept `attributes`, classify `link.flavor` server-side from one shared implementation) so every client gets identical semantics. iOS decodes/round-trips the blob loss-lessly (unknown keys preserved — the web does whole-blob replaces, so dropped keys are silent data loss), captures location natively (CoreLocation + CLGeocoder; no third-party geocoder), and rebuilds cards on the shared anatomy.

**Tech Stack:** Deno edge functions (supabase-js 2.50.2 pattern), Swift 5.10 / SwiftUI, StashKit (supabase-swift 2.54.1 pinned), CoreLocation + CLGeocoder, AVFoundation (AVAsset duration probing).

**Spec:** `docs/ui-changes.md` (the parity contract, 2026-08-11→16 entry) + `docs/superpowers/specs/2026-08-16-single-object-items-design.md`. Investigation findings (endpoint gap, exact payloads, card mechanics) are embedded below with web file:line references.

**Plan sequence:** 1 foundation ✅ → 2 capture ✅ → 3 parity ✅ → **4 (this): object-model parity** → 5 share extension → 6 widgets/intents → 7 visual/design parity. (Renumbered; the wrap task updates the spec's phase list.)

## Global Constraints

- Everything from plans 1–3 still binds: min iOS 17, worktree-branch commits (no push), warning-free builds, exact-path `git add`, no credentials, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`, `swift test` from `ios/StashKit`, sim UDID 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB + `-derivedDataPath DerivedData`, EXPORTED `TEST_RUNNER_*` env vars, `--uitest-reset-auth`, restore-first fixture discipline, testAskSmoke retry + testEditSmoke watch protocols, SourceKit single-file noise, edge deploys via `supabase functions deploy <name>` + `supabase functions list` verify.
- **Data contract (ui-changes.md):** `content` = user note for ALL types (links included); `description` = the object's own text; `page_body` = source material/transcripts; `attributes` jsonb with `location`/`link`/`media` per `src/types/itemAttributes.ts` (snake_case leaf keys: `accuracy_m`, `captured_at`, `duration_s`, `file_name`, `read_time_min`). `posted_from` column DOES NOT EXIST (dropped in migration 20260811130000) — never reference it.
- **Whole-blob replace:** every `attributes` write replaces the full blob (web semantics, `contentProcessor.ts:509`, `itemOperations.ts:87-91`). iOS therefore round-trips UNKNOWN keys: decoding must preserve anything it doesn't model and re-encode it (the `extra` mechanism in Task 3). Never PATCH a partial blob.
- **Single-object model:** never send/create `type='collection'`. N objects → N items; the note goes on the FIRST item only. Multi-save notice copy (authoritative, `UnifiedInputPanel.tsx:866-873`): title `Saved as {N} items`; description with note: `Stash keeps one object per item — your note went with the first one.`; without note: `Stash keeps one object per item, so each got its own.`
- **Location:** opt-in only; `source` for iOS device fixes is `device-geolocation` (this plan widens the TS union — the type's own comment invites it); manual edits are `{label, source:'manual', captured_at}` with coords DROPPED; label rule: "City, Region" when both known and different, else the non-empty one, else country; `captured_at` = the FIX time (ISO-8601 UTC). Written to EVERY item in a batch. Preview text ("posted from …") is display-only, never stored.
- **Server-side flavor:** `add-url` classifies `attributes.link.flavor` when the caller didn't provide one, using a shared port of `src/utils/linkFlavor.ts:23-54` (verbatim rules). Caller-provided flavor wins.
- **add-file PDF gate (parity with commit 83e9809):** only `mime_type === 'application/pdf'` documents enter the quick-pdf-summary/extract-pdf-text pipeline. Other documents get `generate-description` + `summary = description` (clears the processing shimmer) + baseline embedding.
- **Cards:** exactly two hero heights — standard 160pt, tall 224pt (web `h-40`/`h-56`, CardBits.tsx:10-11); aspect threshold portrait = `height > width × 1.05` (CardHero.tsx:28); favicon-plate subtitle literal `preview limited · saved anyway`; annotation = violet left-bar treatment of `content`, ALWAYS visually distinct from description; text-type inversion (content is the body, AI description shown only when no content); duration format `m:ss` / `h:mm:ss` ≥60min; size format `1.0 MB` (0 decimals for B, 1 for KB+); date `MMM d, yyyy`. Masonry DEFERRED (grid stays 2-col; noted in outcome). PPEditorialNew serif deferred to plan 7 — use `.fontDesign(.serif)` for titles now.
- Fixture inventory grows 9 → 12 permanent rows (repo link, video link, located note — Task 9). All other fixture discipline unchanged.
- Out of scope: masonry, rich slash-command composer (plan 7 with markdown bubbles), share extension (plan 5), `extract-office-text` (web agent's in-flight work — untracked/undeployed; do not touch), venue-level geocoding and link enrichment chips (`author`/`stars`/`read_time_min` — render only if data exists, never fake).

---

### Task 1: Platform endpoints — `attributes` passthrough, server-side flavor, PDF gate

**Files:**
- Create: `supabase/functions/_shared/linkFlavor.ts`
- Modify: `supabase/functions/add-note/index.ts`, `supabase/functions/add-url/index.ts`, `supabase/functions/add-file/index.ts`, `src/types/itemAttributes.ts:14` (widen LocationSource), `docs/PLATFORM_API.md`

**Interfaces:**
- Consumes: existing endpoint bodies (add-note `{content,title,is_public}` :59; add-url `{url,title,content,message,supplemental_note,is_public}` :229; add-file `{file_path,mime_type,file_size,content,title,is_public}` :41).
- Produces: all three accept optional `attributes` (JSON object; non-object → ignored as `{}`); inserted whole-blob on the item row. add-url guarantees `attributes.link.flavor` on every saved link (server-classified when absent). add-file's document branch gates the PDF pipeline on exact mime `application/pdf`. Task 5's `CaptureAPI` and Task 9's fixtures rely on all three.

- [ ] **Step 1: Port the classifier** — `supabase/functions/_shared/linkFlavor.ts`: copy `src/utils/linkFlavor.ts:1-54` verbatim minus the TS type import (declare `type LinkFlavor = 'article'|'video'|'repo'|'book'|'social'|'generic'` locally; export both the type and `classifyLinkFlavor`). Keep every host list and rule identical.
- [ ] **Step 2: add-note** — destructure `attributes` from the body; sanitize:

```ts
const safeAttributes =
  attributes && typeof attributes === 'object' && !Array.isArray(attributes) ? attributes : {};
```

Add `attributes: safeAttributes` to the insert object (`:78-89`).
- [ ] **Step 3: add-url** — same destructure+sanitize, then guarantee flavor before insert:

```ts
import { classifyLinkFlavor } from '../_shared/linkFlavor.ts';
// … after sanitizing:
const providedLink = (safeAttributes as Record<string, unknown>).link;
const link = providedLink && typeof providedLink === 'object' ? providedLink as Record<string, unknown> : {};
if (typeof link.flavor !== 'string') link.flavor = classifyLinkFlavor(url);
(safeAttributes as Record<string, unknown>).link = link;
```

Add `attributes: safeAttributes` to the insert (`:317-330`).
- [ ] **Step 4: add-file** — destructure+sanitize, add to insert (`:61-76`). Then the PDF gate in the document enrichment branch: wrap the `quick-pdf-summary` + `extract-pdf-text` invokes in `if (mime_type === 'application/pdf') { … }`; the `else` branch (non-PDF documents) runs after the existing baseline embedding:

```ts
        } else if (OFFICE_MIMES.has(mime_type)) {
          // OOXML documents → extract-office-text (committed+deployed c4cbdd0;
          // mirrors extract-pdf-text: writes page_body + summary + description,
          // re-embeds). Contract: {fileUrl, itemId, fileName, mimeType}
          // (extract-office-text/index.ts:127).
          const { error: offErr } = await supabase.functions.invoke('extract-office-text', {
            body: { fileUrl: publicUrl, itemId: item.id, fileName, mimeType: mime_type },
          });
          if (offErr) console.error('add-file: extract-office-text failed for', item.id, offErr);
        } else {
          // Other non-PDF documents (parity with 83e9809): no PDF pipeline.
          // Give the card a description and clear the "still extracting"
          // marker (summary IS NULL drives the shimmer).
          const { data: d, error: descErr } = await supabase.functions.invoke('generate-description', {
            body: { content: fileName, type: 'document' },
          });
          if (descErr) console.error('add-file: generate-description failed for', item.id, descErr);
          const description = d?.description ?? `Document: ${fileName}`;
          await supabase.from('items').update({ description, summary: description }).eq('id', item.id);
        }
```

with `const OFFICE_MIMES = new Set(['application/vnd.openxmlformats-officedocument.presentationml.presentation','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);` near `deriveItemType`. (The document placeholder description at insert stays for PDFs and OOXML — their extractors replace it; the plain-stub branch replaces it immediately. E2E check #5's `.txt` exercises the stub branch; add check #6: upload a real `.docx` — generate via `cd /tmp && python3 -c` is unavailable-safe? Simpler: create a minimal docx with `zip` from a hand-written document.xml — the implementer builds it in /tmp with the `zip` CLI (document.xml with one `<w:t>office e2e persimmon deck</w:t>` run inside the standard docx skeleton), uploads with the DOCX mime, add-files it, polls `page_body ilike '%persimmon%'` ≤120s — proving the add-file→extract-office-text path E2E. Clean up.)
- [ ] **Step 5: Widen the TS union** — `src/types/itemAttributes.ts:14`: `export type LocationSource = 'browser-geolocation' | 'device-geolocation' | 'photo-exif' | 'manual';` (the comment above it already says "widen as collectors are added").
- [ ] **Step 6: Deploy all three + verify listed**

```bash
cd "$(git rev-parse --show-toplevel)"
supabase functions deploy add-note && supabase functions deploy add-url && supabase functions deploy add-file
supabase functions list | grep -E "add-note|add-url|add-file"
```

- [ ] **Step 7: E2E contract checks** (env/JWT pattern from `ios/.env.test.local`; clean up every row created):
  1. add-note with `{"content":"attr e2e","attributes":{"location":{"label":"Testville","source":"manual"}}}` → GET the row → `attributes.location.label == "Testville"`.
  2. add-url with `{"url":"https://github.com/supabase/supabase-swift"}` (NO attributes) → row's `attributes.link.flavor == "repo"` (server classified).
  3. add-url with explicit `{"attributes":{"link":{"flavor":"book"}}}` on the same kind of URL → flavor stays `"book"` (caller wins).
  4. add-note with `"attributes": []` (array) → row `attributes == {}` (sanitized, no 500).
  5. add-file with a small uploaded `.txt` (mime `text/plain` routes to document): poll → `summary` non-null AND equals `description`, `page_body` null (no PDF pipeline ran).
- [ ] **Step 8: PLATFORM_API.md** — document `attributes` on all three capture endpoints (one shared paragraph: optional object, whole-blob, shapes in `src/types/itemAttributes.ts`; add-url fills `link.flavor` server-side).
- [ ] **Step 9: Commit** — `git add supabase/functions src/types/itemAttributes.ts docs/PLATFORM_API.md && git commit -m "feat: attributes passthrough + server-side link flavor in capture endpoints; add-file PDF gate"`

---

### Task 2: Parked residuals — SubscriptionStore generation token + cancellation-shape widening

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/SubscriptionStore.swift`
- Test: `ios/StashKit/Tests/StashKitTests/SubscriptionStoreTests.swift`

**Interfaces:**
- Consumes: existing store (reset(), one-shot isLoading, GatedChecker test pattern).
- Produces: a refresh that started before `reset()` (or before a newer refresh) can never write state when it resolves; transport-level cancellations (`URLError(.cancelled)`) are treated like `CancellationError`.

- [ ] **Step 1: Failing tests** — (a) `testStaleRefreshCannotClobberAfterReset`: gated checker; refresh #1 completes (trial, gates open); start refresh #2 blocked in check(); call `reset()` while it's in flight; release #2 with a *different* account's active status → assert `status == nil` still (the stale resolve was dropped; RED: current code applies it); (b) `testURLErrorCancelledTreatedAsCancellation`: checker throws `URLError(.cancelled)` → status/lastError untouched (RED: current code wipes status + sets lastError).
- [ ] **Step 2: RED**, **Step 3: Implement** — private `var refreshGeneration = 0`; `refresh()` captures `let generation = refreshGeneration` at entry and guards every state write (status/lastError and the trial re-check applications) on `generation == refreshGeneration`; `reset()` increments `refreshGeneration` (comment: ItemStore.loadGeneration pattern; a reset or newer refresh invalidates in-flight resolves). Widen the cancellation check: `if error is CancellationError || (error as? URLError)?.code == .cancelled { return }`.
- [ ] **Step 4: GREEN** (suite 88). **Step 5: Commit** — `git commit -am "fix(ios): SubscriptionStore generation token + URLError(.cancelled) — closes parked plan-3 residual"`

---

### Task 3: `ItemAttributes` — loss-less blob model + list-columns update

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Models/JSONValue.swift`, `ios/StashKit/Sources/StashKit/Models/ItemAttributes.swift`
- Modify: `ios/StashKit/Sources/StashKit/Models/Item.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemAttributesTests.swift`, `ios/StashKit/Tests/StashKitTests/ItemDecodingTests.swift` (update pinned literal + add cases)

**Interfaces:**
- Produces (Tasks 5–9 consume):

```swift
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null
    case object([String: JSONValue]), array([JSONValue])
}
public struct CapturedLocation: Codable, Equatable, Sendable {
    public var label: String
    public var latitude: Double?
    public var longitude: Double?
    public var accuracyM: Double?      // key "accuracy_m"
    public var city: String?
    public var region: String?
    public var country: String?
    public var source: String          // "device-geolocation" | "manual" | … (open string)
    public var capturedAt: String?     // key "captured_at", ISO-8601
}
public struct LinkAttributes: Codable, Equatable, Sendable {
    public var flavor: String?         // open string; cards map known values
    public var author: String?
    public var durationS: Double?      // "duration_s"
    public var stars: Int?
    public var readTimeMin: Int?       // "read_time_min"
}
public struct MediaAttributes: Codable, Equatable, Sendable {
    public var durationS: Double?      // "duration_s"
    public var fileName: String?       // "file_name"
}
public struct ItemAttributes: Codable, Equatable, Sendable {
    public var location: CapturedLocation?
    public var link: LinkAttributes?
    public var media: MediaAttributes?
    public var extra: [String: JSONValue]   // every unknown top-level key, preserved
    public var isEmpty: Bool
    public init(location: CapturedLocation? = nil, link: LinkAttributes? = nil,
                media: MediaAttributes? = nil, extra: [String: JSONValue] = [:])
    public func jsonObject() -> [String: Any]   // for request bodies (JSONSerialization-ready)
}
```

`ItemAttributes` uses a dynamic-key `CodingKeys` (`struct AnyKey: CodingKey`): decode pulls `location`/`link`/`media` typed and every OTHER key into `extra`; encode writes the three known keys plus everything in `extra` back — byte-level key preservation for the whole-blob-replace world. `Item` gains `fileSize: Int?` (key `file_size`) and `attributes: ItemAttributes` (missing/null column → empty). `Item.listColumns` becomes the web's exact new string (`src/hooks/useItems.ts:7-21`):
`id,type,title,content,url,file_path,description,summary,created_at,mime_type,file_size,is_public,supplemental_note,attributes`
(`detailColumns` = listColumns + `,page_body` unchanged in shape). Sub-structs also preserve unknown keys? NO — only the top level (web edit flows replace sub-objects wholesale too; keep leaf structs simple; document the choice).

- [ ] **Step 1: Failing tests** — round-trip preservation is the heart:

```swift
func testUnknownTopLevelKeysSurviveRoundTrip() throws {
    let raw = #"{"location":{"label":"L","source":"manual"},"weather":{"temp_c":21},"mood":"good"}"#
    let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
    XCTAssertEqual(attrs.location?.label, "L")
    XCTAssertEqual(attrs.extra["mood"], .string("good"))
    let reencoded = try JSONEncoder().encode(attrs)
    let obj = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
    XCTAssertNotNil(obj["weather"]); XCTAssertNotNil(obj["mood"]); XCTAssertNotNil(obj["location"])
}
func testSnakeCaseLeafKeys() throws {
    let raw = #"{"link":{"flavor":"video","duration_s":58},"media":{"file_name":"a.png","duration_s":2.5}}"#
    let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
    XCTAssertEqual(attrs.link?.durationS, 58)
    XCTAssertEqual(attrs.media?.fileName, "a.png")
    let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
    let media = obj["media"] as! [String: Any]
    XCTAssertNotNil(media["file_name"])
}
func testItemDecodesAttributesAndFileSize() throws { /* list-row JSON with attributes + file_size; empty/missing attributes → .isEmpty */ }
func testListColumnsMatchWebContractLiterally() {  // UPDATE the existing pinned test
    XCTAssertEqual(Item.listColumns,
        "id,type,title,content,url,file_path,description,summary,created_at,mime_type,file_size,is_public,supplemental_note,attributes")
}
```

- [ ] **Step 2: RED** (existing pinned test also goes red — expected), **Step 3: Implement**, **Step 4: GREEN** (suite ~94; every existing Item construction site in tests gains the two parameters — mechanical, exact-path). **Step 5: Commit** — `git commit -am "feat(ios): loss-less ItemAttributes blob + file_size; list columns match web rework"`

---

### Task 4: Card metadata utilities

**Files:**
- Create: `ios/StashKit/Sources/StashKit/CardMetadata.swift`
- Test: `ios/StashKit/Tests/StashKitTests/CardMetadataTests.swift`

**Interfaces:**
- Produces (Task 7 consumes): `domainOf(_ url: String?) -> String` (host minus `www.`, "" on nil/invalid — port of `linkFlavor.ts:56-63`); `repoPath(_ url: String?) -> (owner: String, repo: String)?` (first two path segments of github/gitlab URLs, else nil — port of `CardHero.tsx:134-142` incl. the non-repo-roots rejection reusing the same root set); `formatFileSizeChip(_ bytes: Int?) -> String?` (`nil`/`<=0`→nil; B `%.0f`, KB/MB/GB `%.1f` → `1.0 MB`); `formatDurationChip(_ seconds: Double?) -> String?` (nil for nil/≤0/non-finite; `m:ss`; `h:mm:ss` at ≥3600s — note web switches at ≥60 MINUTES); `mimeExtensionLabel(_ mime: String?) -> String?` (port CardBits.tsx:58-79 map incl. PPTX/DOCX/XLSX/PPT/XLS/DOC/JPG/SVG/MOV/M4A/MP3; fallback = subtype uppercased, max 5 chars); `isPortraitAspect(width: CGFloat, height: CGFloat) -> Bool` (`height > width * 1.05`).
- [ ] **Step 1: Failing tests** — table-driven per function: `domainOf("https://www.github.com/a")=="github.com"`; `repoPath("https://github.com/supabase/supabase-swift")==("supabase","supabase-swift")`; `repoPath("https://github.com/features/copilot")==nil`; `formatFileSizeChip(1_048_576)=="1.0 MB"`, `formatFileSizeChip(512)=="512 B"`; `formatDurationChip(58)=="0:58"`, `formatDurationChip(3723)=="1:02:03"`, `formatDurationChip(0)==nil`; `mimeExtensionLabel("application/vnd.openxmlformats-officedocument.wordprocessingml.document")=="DOCX"`, `mimeExtensionLabel("application/x-blorb")=="X-BLO"`; `isPortraitAspect(width:100,height:106)==true`, `(100,105)==false`.
- [ ] **Step 2: RED**, **Step 3: Implement**, **Step 4: GREEN** (~101). **Step 5: Commit** — `git commit -am "feat(ios): card metadata formatters + repo/domain parsing (tested)"`

---

### Task 5: Capture semantics — note-on-first, attributes threading, media metadata

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/CaptureAPI.swift` (attributes params), `ios/StashKit/Sources/StashKit/CaptureViewModel.swift` (routing + attributes), `ios/StashKit/Sources/StashKit/Outbox.swift` (attributes in payload), `ios/Stash/Capture/CaptureComposerView.swift` + `CaptureAttachmentsRow.swift` (fileName/duration capture at pick time), `ios/StashKit/Tests/StashKitTests/CaptureAPITests.swift` + `CaptureViewModelTests.swift` + `OutboxTests.swift`

**Interfaces:**
- Consumes: `ItemAttributes.jsonObject()` (Task 3), Task 1's endpoint contract.
- Produces: `CaptureAPI.addNote/addURL/addFile` each gain `attributes: ItemAttributes? = nil` (encoded as `body["attributes"] = attributes.jsonObject()` when non-empty); `CaptureAttachment` gains `fileName: String?` and `durationS: Double?` (composer fills: original filename from PhotosPicker/fileImporter/camera; duration via `AVAsset.load(.duration)` for picked audio/video, recorder-elapsed for voice notes); `CaptureViewModel.submit()` batch rules: note text goes as `content` on the FIRST unit ONLY (no more note-as-own-item); every unit's addFile carries `attributes` = `{location?, media:{duration_s?, file_name?}}`; addURL carries `{location?}` (flavor is server-side); addNote carries `{location?}`; `submitVoiceNote` carries `media` too. `CaptureOutcome` unchanged; the composer's toast for `saved(count>1, dropped:0)` becomes the notice copy from Global Constraints. Outbox payloads gain optional `"attributes_json"` (serialized blob string; drain decodes and forwards).
- Location plumbing arrives in Task 6 — this task threads `pendingLocation: CapturedLocation?` through the ViewModel (settable property, nil default) so Task 6 only wires the UI.

- [ ] **Step 1: Failing tests** — update/extend: `testMultiFileWithTextPutsNoteOnFirstOnly` (3 files + text → three addFile posts; FIRST body has `content`, others don't; NO addNote call — replaces the old separate-note expectation); `testURLPlusFilesNoteGoesToURLFirst` (URL text + 2 files → addURL first with content=stripped text, then 2 addFile nil-content); `testAttributesThreadToEveryUnit` (pendingLocation set + 2 files w/ fileName/duration → both bodies carry attributes.location AND their own media blob); `testVoiceNoteCarriesMediaAttributes`; CaptureAPI: `testAddFileEncodesAttributes` (body["attributes"] present only when non-empty); Outbox: `testFileEntryRoundTripsAttributesJSON` (enqueue with attributes_json → drain body carries decoded attributes).
- [ ] **Step 2: RED**, **Step 3: Implement** (routing table comment updated to cite the single-object spec; the batch toast copy switches on note-presence per Global Constraints), **Step 4: GREEN** (~109). **Step 5: App builds** (composer changes compile; camera/file pickers store fileName; AVAsset probe async at attach with graceful nil). **Step 6: Commit** — `git commit -am "feat(ios): single-object batch (note on first) + attributes threading through capture"`

---

### Task 6: Location capture — pin toggle, CoreLocation, native reverse geocode

**Files:**
- Create: `ios/StashKit/Sources/StashKit/LocationBuild.swift`, `ios/Stash/Capture/LocationCapture.swift`
- Modify: `ios/Stash/Capture/CaptureComposerView.swift` (pin button + preview + wiring), `ios/project.yml` (`NSLocationWhenInUseUsageDescription: "Stash tags saves with where you were — only when you turn the pin on."`)
- Test: `ios/StashKit/Tests/StashKitTests/LocationBuildTests.swift`, `ios/StashUITests/StashUITests.swift` (`testLocationPinSmoke`)

**Interfaces:**
- Consumes: `CapturedLocation` (Task 3), `CaptureViewModel.pendingLocation` (Task 5).
- Produces: StashKit pure logic — `buildLocationLabel(city: String?, region: String?, country: String?) -> String?` (web rule port, `useCaptureLocation.ts:37-45`: place="city", region="region"; both & different → `"City, Region"`; else place else region else country else nil) and `buildCapturedLocation(latitude:longitude:accuracy:city:region:country:fixDate:) -> CapturedLocation?` (nil when label nil; `source: "device-geolocation"`; `capturedAt` = ISO-8601 of fixDate; accuracy rounded). App-side `LocationCapture` (@Observable): `state` (.off/.resolving/.ready(CapturedLocation)/.failed), `toggle()` — off→on requests when-in-use auth if needed, one-shot `CLLocationManager` fix (desiredAccuracy `kCLLocationAccuracyHundredMeters`, 10s timeout), `CLGeocoder().reverseGeocodeLocation` → city=`placemark.locality`, region=`placemark.administrativeArea`, country=`placemark.country` → build; 5-minute cache (re-toggle within window reuses); failure → alert ("Couldn't find your location" / "Location unavailable — allow location access in Settings to tag saves with a place.") + state .off; auth denied → same alert + Settings deep-link button. `submit()` waits ≤2.5s on `.resolving` (Task 5's ViewModel exposes `awaitPendingLocation(timeout:)` — implement here) then proceeds with whatever resolved.
- Composer UI: pin button (identifier `capture.pin`) next to Save; `.resolving` spinner; `.ready` shows the preview line `posted from {label}` (identifier `capture.pin.preview`) — display-only.
- [ ] **Step 1: TDD LocationBuild** (label rule table: both→"Saratoga Springs, New York"; same-string city/region → just city; city-only; region-only; country-only; all-nil→nil; buildCapturedLocation nil-label→nil, accuracy rounding, capturedAt formatting). RED → GREEN (~114).
- [ ] **Step 2: Implement LocationCapture + composer wiring + plist key** (TRIPWIRE: diff committed Info.plist after xcodegen).
- [ ] **Step 3: `testLocationPinSmoke`** — pre-grant: `xcrun simctl privacy 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB grant location it.gostash.stash` AND set a simulated location (`xcrun simctl location 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB set 43.0831,-73.7846`). Test: Add tab → tap `capture.pin` → `capture.pin.preview` appears (≤10s, any non-empty label) → type "UITEST-LOC: pin smoke <epoch>" → Save → toast → REST-poll the row → assert `attributes.location.label` non-empty AND `attributes.location.source == "device-geolocation"` AND latitude present → REST-DELETE the disposable row. Full suite ×2 green.
- [ ] **Step 4: Screenshots** (pin resolving + preview visible) read + described. **Step 5: Commit** — `git add ios && git commit -m "feat(ios): opt-in location capture — pin toggle, CoreLocation, native geocode"`

---

### Task 6b: Web-alignment riders (2026-08-21 web commits, added mid-plan)

**Files:**
- Modify: `ios/Stash/Auth/SessionStore.swift`, `ios/StashKit/Sources/StashKit/SubscriptionStore.swift`
- Test: `ios/StashKit/Tests/StashKitTests/SubscriptionStoreTests.swift`

**Interfaces:**
- Consumes: existing SessionStore.signOut + the `--uitest-reset-auth` hook; SubscriptionStore.refresh error path.
- Produces: (1) **local-scope sign-out** (web 166b7c6): both `signOut()` call sites become `signOut(scope: .local)` — comment cites the web commit and the zombie-session history; this also closes the ledgered CI cross-invalidation concern. (2) **Fail-open subscription errors** (web 42c2e67): a non-cancellation refresh error KEEPS the last known `status` (never nils it) — "an errored check means unknown, not unsubscribed"; `lastError` still set for Settings display; a fresh-launch error with no prior status leaves gates closed (status nil from init — web equivalent). (3) Row-major grid note: iOS LazyVGrid is already row-major — record in the outcome; footer-pinning/row-height-equalization → plan 7.

- [ ] **Step 1: Failing test** — `testTransientErrorKeepsLastKnownStatus`: refresh #1 succeeds (trial, gates open); refresh #2 throws a plain error → assert `status` UNCHANGED (still trial), `canAddContent` still true, `lastError` set. (RED: current code nils status.) Keep the existing fresh-launch-error test asserting gates closed when no prior status — update its name/comment to reflect the distinction, not its assertions.
- [ ] **Step 2: Implement both changes.** **Step 3: GREEN** (suite +1); UI suite ×1 (sign-out flow unaffected functionally — verify testSettingsSmoke's sign-out still passes). **Step 4: Commit** — `git commit -am "fix(ios): local-scope sign-out + fail-open subscription errors (web 166b7c6/42c2e67 parity)"`

---

### Task 7: Object-first cards

**Files:**
- Create: `ios/Stash/Library/CardHero.swift`, `ios/Stash/Library/CardChips.swift`, `ios/Stash/Library/CollectionStrip.swift`
- Modify: `ios/Stash/Library/ItemCardView.swift` (rebuilt on the anatomy), `ios/Stash/Library/LibraryView.swift` (grid unchanged; card sizing accommodates variable heights)
- Test: existing suites stay green; anatomy asserted in Task 9's smoke

**Interfaces:**
- Consumes: `Item.attributes`, `fileSize` (Task 3); `domainOf/repoPath/formatFileSizeChip/formatDurationChip/mimeExtensionLabel/isPortraitAspect` (Task 4); `renderTipTap` (plain-texting content/description).
- Produces: the shared anatomy, top to bottom (prose-specified over tested logic — project precedent; every rule below is binding):
  1. **Object zone** — heights exactly 160 (standard) / 224 (tall). Dispatch: `link` by `attributes.link.flavor ?? "generic"`: `repo` → dark plate (bg `Color(red:0.051,green:0.067,blue:0.09)`), mono `owner/repo` from `repoPath` (fallback `domainOf`), description 2-line clamp; `video`/`book` with a cover image → tall, `scaledToFit` centered over a blurred+dimmed copy of itself, play-triangle overlay for video, domain pill bottom-leading; other flavors with image → standard `scaledToFit`-fill cover; no usable image (nil thumbnailURL or load failure) → **favicon plate**: circle letter avatar (first char of domain, uppercased), domain line, subtitle `preview limited · saved anyway`. `image` → measure on load; portrait (`isPortraitAspect`) → tall contained-on-blur; landscape → standard cover; load failure → file plate (violet/photo icon + mono `attributes.media.fileName` + facts). `video` → thumbnail zone with duration badge (`formatDurationChip(attributes.media.durationS)`) bottom-trailing. `document` → file plate (red/doc icon + mono fileName + `PDF · 1.2 MB` facts from mimeExtensionLabel+formatFileSizeChip). `text`, `audio`, legacy `collection` → NO hero.
  2. **Kicker** (links only): uppercase `domainOf(url)`, small tracking-wide caption, tappable → opens URL.
  3. **Title**: `.fontDesign(.serif)`, 2-line clamp.
  4. **Description**: muted, 3-line clamp, plain-texted — EXCEPT text items (see 5).
  5. **Annotation**: `content` plain-texted, 2-line clamp, violet 2pt leading bar + inset — rendered AFTER description, always visually distinct. **Text-type inversion**: for `type == .text`, `content` renders as the body (4-line clamp, no annotation treatment) and description appears ONLY when content is empty.
  6. **Metadata chips** row: mono `fileName` chip (image/audio/video only); `TYPE · SIZE` chip (NOT document/link — the doc plate already shows it); duration chip (audio only — video's lives on the hero).
  7. **Footer**: `MMM d, yyyy` date · location pin+`attributes.location.label` (truncate ~140pt) when present · type badge (always visible on iOS).
  Legacy `collection`: rich note (renderTipTap of content, else description) + `CollectionStrip` — fetches `item_attachments` (`item_id` eq, `created_at` asc) on appear, renders ≤4 thumbnail tiles + `+N` overflow tile; footer type badge reads `"N items"`. Read-only.
  Processing shimmer (`isProcessingDocument`) unchanged. Sticky badge unchanged.
- [ ] **Step 1: Implement** (each file ≤~120 lines; extract subviews). **Step 2: Build + run; visually verify each fixture type renders its zone** (screenshots per type family: repo/video link cards land in Task 9 after fixtures exist — this step verifies with the 9 current fixtures: image aspect handling, document plate, audio no-hero + duration chip, text inversion, link favicon-plate fallback for the metadata-poor `example.com` fixture, sticky/public, collection none present — note it). Read + describe screenshots. **Step 3: Full UI suite ×1** (card identifier changes: keep `card.<index>` stable; update any assertion that referenced removed elements — preambles only). **Step 4: Commit** — `git add ios && git commit -m "feat(ios): object-first card system — typed heroes, annotation bar, metadata chips, location footer"`

---

### Task 8: Edit sheet — location row, attributes round-trip, legacy Attachments

**Files:**
- Create: `ios/Stash/Detail/LocationRow.swift`
- Modify: `ios/StashKit/Sources/StashKit/ItemEditor.swift` (`ItemPatch` gains attributes), `ios/StashKit/Sources/StashKit/ItemRules.swift` (`mergePreservingDetail` unsaved-location deferral), `ios/Stash/Detail/ItemDetailView.swift` + `EditableFieldsSection.swift` (row placement under description), `ios/Stash/Detail/ItemDetailContent.swift` (legacy Attachments section below Notes, titled "Attachments", reusing `CollectionStrip`)
- Test: `ios/StashKit/Tests/StashKitTests/ItemEditorTests.swift` + `ItemMergeTests.swift` (add cases), `ios/StashUITests/StashUITests.swift` (`testLocationEditSmoke`)

**Interfaces:**
- Consumes: `ItemAttributes` (Task 3), `ItemEditor.save` plumbing (plan 2), `CollectionStrip` (Task 7).
- Produces: `ItemPatch.attributes: ItemAttributes?` (encodes into `restBody["attributes"]` as the FULL blob via `jsonObject()`; nil = untouched; counts as a text-field-adjacent change? NO — attributes changes do NOT schedule embedding refresh — web parity: `itemOperations.ts:100-101` gates on title/description/content/supplemental_note only); `mergePreservingDetail` gains `hasUnsavedLocation: Bool` (defers `attributes` to local when true, otherwise incoming wins — attributes IS in list columns). `LocationRow` semantics (web `EditItemLocationSection.tsx`): absent → "Add a location" ghost; present → `posted from {label}` tappable + X remove; editing → autofocused field, placeholder `e.g. Brooklyn, New York`, Enter/blur commit, Escape cancels; commit no-ops on unchanged trim; empty commit removes the `location` key; non-empty → `CapturedLocation(label: trimmed, source: "manual", capturedAt: nowISO)` — every other location field dropped; the rest of the blob (link/media/extra) preserved via the item's decoded `ItemAttributes` (read-modify-write on the freshest adopted row; comment the concurrency caveat matching web's).
- [ ] **Step 1: Failing tests** — ItemPatch attributes encoding (full-blob in restBody; no refresher scheduled when ONLY attributes change — RecordingSyncer stays empty); merge deferral case; manual-edit builder (coords dropped, source manual). RED → GREEN (~117).
- [ ] **Step 2: Implement UI** (row + legacy Attachments section). **Step 3: `testLocationEditSmoke`** — on a DISPOSABLE item (create "UITEST-LOC: edit smoke" via add-note with a device-geolocation location blob): open detail → row shows `posted from` label → edit to "Test City" → commit → REST assert `label=="Test City"`, `source=="manual"`, latitude ABSENT, link/media keys preserved (seed one in the create) → clear → REST assert `location` key removed, others intact → DELETE row. Full suite ×2 green.
- [ ] **Step 4: Commit** — `git add ios && git commit -m "feat(ios): edit-sheet location row + loss-less attributes editing; legacy Attachments section"`

---

### Task 9: Flavor fixtures + anatomy smoke

**Files:**
- Modify: `ios/StashUITests/StashUITests.swift` (`testCardAnatomySmoke`)
- Production fixtures (permanent, idempotent by title): via add-url (post-Task-1, server classifies): `https://github.com/supabase/supabase-swift` (expect flavor `repo`) titled by enrichment but content `"UITEST-FIXTURE: repo link — permanent"`; `https://www.youtube.com/watch?v=dQw4w9WgXcQ` (expect flavor `video`) content `"UITEST-FIXTURE: video link — permanent"`; via add-note: `"UITEST-FIXTURE: located note"` with a full device-geolocation location blob (fixed coords, label "Saratoga Springs, New York").
- [ ] **Step 1: Seed** (idempotency: query `content=like.UITEST-FIXTURE*` / title for the note; only create missing; poll enrichment settle; REST-verify flavors are `repo`/`video` — this E2Es Task 1's server classification in production). Record the 12-row inventory in the report.
- [ ] **Step 2: `testCardAnatomySmoke`** — View tab: assert the repo card exposes a `card.repoplate` element whose label contains `supabase/supabase-swift`; the located-note card's footer exposes `card.location` with "Saratoga Springs"; the video-link card exposes either a tall hero or favicon plate (identifier `card.hero.tall` or `card.faviconplate` — depends on whether YouTube's og image survived; assert one of the two exists and disclose which); a document fixture card shows `card.fileplate` with "PDF". Add the needed accessibility identifiers in Task 7's views if missing (disclose each). Full suite ×2 green (flake protocols stand).
- [ ] **Step 3: Screenshots**: grid with the new card variety; repo + located cards close-up. Read + describe. **Step 4: Commit** — `git add ios && git commit -m "test(ios): flavor fixtures + card-anatomy smoke"`

---

### Task 10: Wrap — verification, cross-platform log entry, spec renumber, outcome

**Files:**
- Modify: `docs/ui-changes.md` (new dated entry), `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` (phase renumber), `docs/superpowers/plans/2026-08-17-ios-plan-4-object-parity.md` (outcome)

- [ ] **Step 1:** StashKit full suite green (~117) + warning-free; app build clean; full UI suite (14 tests) ×2 green; `npm test` green (web tests must still pass — Task 1 touched `src/types/itemAttributes.ts`; run the full web suite and confirm the type widening broke nothing).
- [ ] **Step 2:** `docs/ui-changes.md` — prepend a dated entry (follow the file's conventions, newest first): capture endpoints now accept `attributes` (whole-blob, shapes unchanged); `add-url` classifies `link.flavor` server-side when absent (web ChatMole captures now get flavors/locations too — no web code change needed, the gap closes server-side); `LocationSource` gained `'device-geolocation'` (iOS device fixes); `add-file` gates the PDF pipeline on `application/pdf` (83e9809 parity). Note: written FOR the web agent — contracts first.
- [ ] **Step 3:** Spec phases: 4 = object-model parity ✅ (this), 5 = share extension, 6 = widgets/intents → TestFlight, 7 = visual/design parity.
- [ ] **Step 4:** Outcome section: date, commits, suite counts, fixture inventory (12), deviations of record, plan-5 handoff (share extension now rides attribute-capable endpoints — share-time location pin is a natural extension; carried items: camera recoverability, orphan-recording sweep, App Group migration, extension memory budget, masonry + serif font + rich composer → plan 7). Commit.

---

## Self-review notes (done at authoring time)

- **Contract coverage vs ui-changes.md:** attributes blob ✓ (T1/T3), field semantics ✓ (already aligned; add-file transcript path unchanged), no posted_from ✓ (never referenced), single-object + note-on-first + notice copy ✓ (T5), location capture rules ✓ (T6 — BigDataCloud replaced by CLGeocoder, same label rule, disclosed), card anatomy incl. per-type zones/chips/footer ✓ (T7), edit location row ✓ (T8), legacy collection strip + "Attachments" naming ✓ (T7/T8), pending-enrichment chips render-only-if-present ✓ (T7 reads optional fields), Enter-submit predicate noted-not-built (rich composer = plan 7) ✓ per scope.
- **Type consistency:** `ItemAttributes.jsonObject()` consumed by CaptureAPI (T5) and ItemPatch (T8); `CapturedLocation` field names match T3 across T6/T8; formatter names match T4→T7; `pendingLocation`/`awaitPendingLocation` split T5-declares/T6-implements is called out in both tasks.
- **Deliberate deviations (disclosed):** CLGeocoder over BigDataCloud (native, key-less, same output shape); `device-geolocation` source (TS union widened in T1); masonry/serif/rich-composer deferred to plan 7; sub-object unknown-key preservation is top-level-only (matches web's own wholesale sub-object replaces).
- **Known risks, accepted:** three endpoint deploys to production (additive params — existing clients unaffected; approved scope: "implement them"); simulator location simulation (`simctl location set`) drives the pin smoke — if the sim refuses a fix, the smoke discloses and falls to the LocationBuild unit layer + manual screenshot; YouTube og-image variability handled with an either-or assertion.

---

## Outcome (2026-08-22)

**Commit range:** `52fc80f..HEAD` — 18 commits (base `52fc80f` = this plan's own authoring commit; 17 implementation/fix-round commits across Tasks 1–9 plus this wrap's own docs commit).

| Commit | Task | Message |
|---|---|---|
| `11e790c` | T1 amendment | docs: route OOXML through extract-office-text in plan-4 T1 (c4cbdd0 landed) |
| `b9957e6` | T1 | feat: attributes passthrough + server-side link flavor in capture endpoints; add-file PDF gate |
| `2524fc1` | T2 | fix(ios): SubscriptionStore generation token + URLError(.cancelled) — closes parked plan-3 residual |
| `914aa3c` | T3 | feat(ios): loss-less ItemAttributes blob + file_size; list columns match web rework |
| `17e2028` | T3 fix round | fix(ios): ItemAttributes tolerates malformed known keys; jsonObject() returns nil on encode failure |
| `3b10883` | T4 | feat(ios): card metadata formatters + repo/domain parsing (tested) |
| `6272b5a` | T4 fix round | fix(ios): card metadata critical & important fixes |
| `555f136` | T5 | feat(ios): single-object batch (note on first) + attributes threading through capture |
| `d0930bb` | (mid-plan) | docs: add Task 6b — local signOut + fail-open subscription (web parity riders) |
| `4aa013d` | T6 | feat(ios): opt-in location capture — pin toggle, CoreLocation, native geocode |
| `50d93f2` | T6 fix round | fix(ios): close LocationCapture continuation leak on rapid toggle |
| `dc7208f` | T6b | feat(ios): plan-4 task-6b web-parity riders — local-scope sign-out + fail-open subscription errors |
| `f1eb686` | T6b fix round | test(ios): clarify subscription error handling — rename error-path test |
| `f9a4152` | T7 | feat(ios): object-first card system — typed heroes, annotation bar, metadata chips, location footer |
| `fb04bb9` | T8 | feat(ios): edit-sheet location row + loss-less attributes editing; legacy Attachments section |
| `807f1d3` | T9 | test(ios): flavor fixtures + card-anatomy smoke |
| `715d189` | T9 fix round | test(ios): widen favicon-plate wait timeout from 5s to 30s |
| *(this commit)* | T10 | docs(ios): plan-4 wrap — ui-changes log, spec renumber, outcome |

Mid-plan interruption: T6 was dispatched, interrupted by Will 2026-08-18, and reset to a clean `555f136`; main gained 3 web commits in the interim (local signOut `166b7c6`, fail-open subscription `42c2e67`, row-major grid `62a205b`), absorbed as Task 6b. T6 was re-dispatched fresh and completed 2026-08-22.

### Verification

- **StashKit:** `swift test` → **204/204 passing, 0 failures.** `swift build` → 0 warnings. (The plan's own Step-1 estimates drifted upward every task as scope/coverage grew — 204 is the actual final count, not the brief's stale "~117"; each task's own report disclosed its count mismatch at the time.)
- **App build:** `xcodebuild build` (clean rebuild, `rm -rf DerivedData`) against sim `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` → **BUILD SUCCEEDED**, 0 new warnings (only the two pre-existing environmental notices carried since plan 1: multiple-destination-match, `appintentsmetadataprocessor` AppIntents-framework skip).
- **Web:** `npm test` (`vitest run`) → **20 test files, 127 tests, all passed.** `npx tsc --noEmit` → clean. Confirms Task 1's `LocationSource` union widening (`src/types/itemAttributes.ts`) didn't regress the web suite or its types.
- **Full `StashUITests` suite, run twice** against production (account `will+uitest@dzierson.com`), fresh `STASH_DELETE_MARKER` reseeded via REST before each run:

  | Test | Run 1 | Run 2 |
  |---|---|---|
  | testWrongPasswordShowsErrorThenCorrectPasswordSignsIn | passed | passed |
  | testLibrarySmoke | passed | passed |
  | testDetailSheets | passed | passed |
  | testCardAnatomySmoke | passed | passed |
  | testTagFilterSheetOpens | passed | passed |
  | testCaptureSmoke | **failed** (subscription gate) | **failed** (subscription gate) |
  | testEditSmoke | passed | passed |
  | testDeleteSmoke | passed | passed |
  | testTagsAndPublicSmoke | passed | passed |
  | testAskSmoke | **failed** (sourceless after retry — see corrected record below) | **failed** (sourceless after retry — see corrected record below) |
  | testVoiceNoteSmoke | passed | passed |
  | testLocationPinSmoke | **failed** (subscription gate) | **failed** (subscription gate) |
  | testLocationEditSmoke | passed | passed |
  | testSettingsSmoke | passed | passed |

  Both runs: **11/14 passed**, matching the pre-adjudicated failure set by test name (testCaptureSmoke, testLocationPinSmoke, testAskSmoke) — but `testAskSmoke`'s failures are **not** ordinary flake; see the corrected record and live probe immediately below, which supersedes the "RAG-variance" framing this section originally used. Zero OTHER failures across both runs. Both runs independently hit the pre-existing, previously-documented (task-9-report.md) "Restarting after unexpected exit, crash, or test timeout" xcodebuild-runner recovery immediately after `testLocationPinSmoke`'s gate-blocked throw — cosmetic, not a new issue. Post-run REST cleanup: both runs' disposable delete-marker rows were consumed by `testDeleteSmoke` as designed; `note one`/`note two` fixtures self-healed to their canonical state (REST-verified: title/content exact, `is_public:false`, `supplemental_note:null`, 0 `item_tags` rows); 9 accumulated voice-note debris rows (7 pre-existing from Tasks 6–9's own runs + 1 from each of this task's 2 runs) plus their `stash-media` storage objects were deleted — the 12-fixture inventory was reconfirmed intact throughout.

#### `testAskSmoke` — corrected record + live probe (added at final review; a Critical review finding on the first draft of this section)

**The first draft of this section mis-framed this as ordinary flake. It is not.** The actual record across this plan, tabulated from every task's own report: **8-for-8 full-suite runs have failed `testAskSmoke`, always the same way** (a real, coherent streamed answer, but the SSE `.done` event's `sources` array empty on both the initial attempt AND the in-test retry) — T6 ×2 (task-6-report.md), T7 ×1 (task-7-report.md), T8 ×1 (task-8-report.md), T9 ×2 (task-9-report.md), T10 ×2 (this task, both runs above). Zero passes since Task 6. Contrast with **plan 3's own outcome doc** (`docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md:507,513`): both of plan 3's full-suite runs had `testAskSmoke` **succeed on the first attempt — the in-test retry never fired, 2-for-2 clean, ~24s each**. Something changed the observed behavior completely, coincident with this plan's start. The original framing ("worth a future look... isn't a regression this plan introduced") asserted the second half of that sentence with no supporting evidence — dropped, per review.

**Live probe (this task, in response to the review finding):** called `POST /functions/v1/chat-with-all-content` directly via curl (ROPC JWT, same `message`, `conversationHistory: []`, bypassing the app/test entirely) — **twice**:

- **Run 1:** streamed text non-empty ("Your saved items mention persimmons in the Stash UITEST fixture document...") — `sources`: **4 items**, first `{"id":"e5f66ca4-fa45-48b9-9d2a-d5aa8cb5aba4","title":"UITEST-FIXTURE: document one","type":"document","url":null}` (exactly the persimmons fixture).
- **Run 2:** same shape — non-empty text, **4 sources**, same document first.

**Both direct calls were correctly sourced.** Per the review's own decision rule ("if sourced → the break is client/test-side"): **server-side retrieval is confirmed working right now** — the `embeddings` row for `UITEST-FIXTURE: document one` (`item_id e5f66ca4-…`) exists, non-empty (`content_chunk` contains "persimmons" 3×), and `hybrid_search_content` finds and ranks it correctly. This rules out "plan 4's corpus changes broke retrieval" as the mechanism, since retrieval is demonstrably intact against the current corpus (62 items / 56 embeddings, post plan-4 fixture adds and Task-1 E2E row deletions — `embeddings.item_id` is `ON DELETE CASCADE`, so the deleted E2E rows left no orphaned vectors to pollute results).

**Additional finding, not requested but directly relevant:** the account's single `conversations` row has exactly 40 `messages`, and **the newest one is dated 2026-08-12T03:43** — before every one of the 8 plan-4 failures (T6 starts 2026-08-18). Plan 3's own testAskSmoke runs (and an evident manual investigation session asking the identical question ~5× in a row on 2026-08-11/12) **did** persist to this table; **nothing from plan 4's 8 runs has**, sourced or not. Whether persistence is conditioned on a successful/sourced exchange (in which case this is consistent with, not independent evidence for, 8/8 sourceless) or is itself broken since Task 6 is not established here — flagged as a concrete lead, not a conclusion.

**Corrected conclusion:** the server-side RAG pipeline is proven healthy by direct probe. What is **not** established, and is not resolved by this probe, is why the actual app/test invocation deterministically fails where a raw API call twice succeeds, or whether this began as something plan 4 introduced (the plan-3-vs-plan-4 behavioral discontinuity is real and unexplained, not dismissed). This needs client-side instrumentation (the literal outgoing request/response inside the app, not a curl proxy for it) to actually reproduce and root-cause — not attempted here, out of this task's scope. See the plan-5 handoff below for the escalation.

### 12-fixture inventory (REST-reconfirmed 2026-08-22, post-cleanup)

| Type | Title | Flavor / location |
|---|---|---|
| text | UITEST-FIXTURE: note one | — |
| text | UITEST-FIXTURE: note two | — |
| text | UITEST-FIXTURE: public sticky | — (public + sticky note) |
| text | UITEST-FIXTURE: located note | location: "Saratoga Springs, New York" |
| link | UITEST-FIXTURE: link one (example.com) | — (favicon-plate case) |
| link | UITEST-FIXTURE: link two (Wikipedia) | — (cover-image case) |
| link | GitHub — supabase/supabase-swift | flavor: repo |
| link | Rick Astley — Never Gonna Give You Up | flavor: video |
| image | UITEST-FIXTURE: image one | — |
| image | UITEST-FIXTURE: realtime demo — permanent | — |
| audio | UITEST-FIXTURE: audio one — permanent | — |
| document | UITEST-FIXTURE: document one | — |

### Deviations of record

1. **CLGeocoder, not BigDataCloud** (Task 6) — native, key-less reverse geocoding; same output shape (city/region/country → the same "City, Region" label rule as the web's `useCaptureLocation.ts`). Deliberate, disclosed at authoring time.
2. **`device-geolocation` LocationSource** (Task 1) — the TS union (`src/types/itemAttributes.ts`) widened to carry iOS's own collector name alongside the web's `browser-geolocation`; same `CapturedLocation` shape.
3. **URL-first note tie-break vs. web's chip-order** (Task 5) — iOS deterministically gives a batch's note to a detected URL (always first), where the web gives it to whichever object the user chipped first. Flagged for Will/product sign-off in both `docs/ui-changes.md`'s 2026-08-22 entry and task-5-report.md; not resolved in this plan.
4. **`CardPlates.swift`** — a 4th new file beyond the brief's named 3-file list for Task 7 (splitting `RepoPlate`/`FaviconPlate`/`FilePlate` out of `CardHero.swift` to honor the same brief's own "~120 lines per file" rule). `ItemCardView.swift` (**286 lines, re-measured at this final review** — 273 at Task 7's own commit, +13 from Task 9's `typeBadge` wrapping fix) and `CardHero.swift` (188 lines) still exceed that target even after the split — judged as reasonable given the scope (7 anatomy steps + legacy-collection branch + sticky/shimmer machinery; the web's equivalent split is 598 lines across 3 files for the same scope). Disclosed and reasoned in task-7-report.md.
5. **Native `.video`-type hero renders a static dark plate** (play-triangle icon + duration badge), not a real extracted poster frame — no `AVAssetImageGenerator` call. No fixture exists to verify against (none of the 12 permanent fixtures are a native video upload; Task 9's "video" fixture is link-flavor video, i.e. a `link` item). `item.thumbnailURL` for a true video type points at the video file itself, which can't be decoded as an image, so the honest static plate was chosen over a network fetch known to fail.

This list covers deviations material enough to affect a plan-5+ reader's decisions. It is not the full record of every disclosed minor — each task's own report has its own "Deviations"/"Concerns" section, and `progress.md` (this plan's running SDD ledger) has one line per task summarizing all of them, including several smaller, genuinely-inconsequential items not repeated here (e.g. Task 4's report-count arithmetic, Task 5's PhotosPicker-filename-probe coverage gap, Task 8's untested Escape-to-cancel path). See `progress.md` for the complete deferred-minors ledger.

### Triaged at this final review

Two items were explicitly ledgered as "final review to triage" (progress.md) rather than fixed inline during their originating tasks, since both are narrow, self-healing races in imperative/async glue code that StashKit's test suite has no seam to exercise directly (no CoreLocation mock, no network-response-ordering harness):

- **T6 — abandoned 10s location-fix timer lacks a generation check.** A cancelled resolution cycle's own timeout timer isn't itself invalidated, so it can (real-device-likelihood; not reproduced on the simulator, where fixes resolve instantly) spuriously fail a later, unrelated resolve. **Triage: accept, non-blocking, carry forward.** The Critical continuation/Task leak that was in the same area IS fixed (`50d93f2`, with a live sim sanity check); this is a narrower, lower-probability residual on top of that fix, not something the fix left behind.
- **T8 — rapid double location-commit race.** Two location-row edits committed in quick succession can have the first PATCH's response land after the second's and transiently revert it via `applyDetail` (no debounce/in-flight tracking on `saveAttributes`, unlike the debounced text fields — a location commit was treated as already-discrete, matching `NotesAppendComposer`'s own precedent). **Triage: accept, non-blocking, carry forward.** Self-healing on the next realtime update; the window requires committing the same row's location twice within one network round-trip, an edge case for a field that isn't the primary edit target of the sheet.

Recommendation: a dedicated hardening pass (not urgent, not plan-5-blocking) rather than a blind fix now — both need either a CoreLocation test double or a network-race harness StashKit doesn't currently have.

### Stripe-lapse blocker — PENDING WILL DECISION

Verbatim from the plan ledger (`progress.md`), confirmed still unresolved as of this wrap (`check-subscription` on the test account still returns `subscribed: false, subscriptionStatus: "paused", trialEnd: "2026-08-16T16:05:38.000Z"` — 6 days lapsed, visible directly in the Settings screenshot below as "Status: Expired"):

> UI-test account Stripe trial LAPSED 2026-08-16 (paused, no payment method); self-heal correctly refuses (history exists). Capture smokes (testCaptureSmoke/testLocationPinSmoke/testVoiceNoteSmoke) gate-blocked client-side; REST/server saves unaffected; edit/anatomy/settings smokes unaffected. Options for Will: comp the account (100% coupon / far-future trial_end) [recommended, durable], new history-free account + fixture re-seed [14-day time bomb], or accept degraded capture-smoke verification. Implementer correctly did NOT touch Stripe.

This plan's own implementers (Tasks 6, 6b) independently reconfirmed the mechanism (`create-trial-subscription`'s self-heal refuses once any subscription has ever existed — "lapsed users go through checkout, not a fresh trial") and did not touch Stripe. No plan-5 (or later) implementer should either, absent Will's decision here.

### Plan-5 (share extension) handoff

- **ESCALATION — Ask sourceless-response investigation (ties into Will's RAG-overhaul priority).** `testAskSmoke` has failed deterministically, 8-for-8, on every plan-4 full-suite run (see the corrected record above), a hard behavioral break from plan 3's clean 2-for-2 baseline. This task's live probe **rules out a server-side retrieval regression** (direct `chat-with-all-content` calls, bypassing the app, returned correctly-sourced answers 2/2) but does **not** explain why the app/test path deterministically fails where a raw API call succeeds — that gap is unreproduced and unresolved. Also unexplained: zero messages have persisted to the account's Ask conversation since 2026-08-12 (before any plan-4 run), versus plan 3's runs persisting normally. Whoever picks up plan 5 (or the RAG-overhaul work directly) should treat this as a real, open reliability question — not dismiss it as flake — and start with client-side instrumentation of the actual iOS request/response, since curl-level probing has now exhausted what it can distinguish.
- **Rides the attribute-capable endpoints for free.** `add-note`/`add-url`/`add-file` already accept `attributes` (Task 1) and `add-url` classifies `link.flavor` server-side — the extension's own capture calls carry `location`/`media` from day one, no new endpoint work needed.
- **Share-time location pin is a natural extension** of Task 6's `LocationBuild` (pure, StashKit-side, already shared-package-clean) — the app-side `LocationCapture` CoreLocation wrapper would need its own instance in the extension process (same pattern, new host).
- **Carried items** (open before plan 4, unaffected by it, load-bearing for plan 5 specifically — see `docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md`'s own ledger for full detail):
  - **Camera recoverability** — attachments still live only in in-memory `CaptureAttachment.data`; `RecordingStore`'s local-first-write pattern (proven durable for voice notes) isn't generalized to camera/file-picker attachments yet.
  - **Orphan-recording sweep** — `RecordingStore.pendingRecordings()` is dead API; a force-quit between Stop and Save still orphans `.m4a` files with no startup reconciliation.
  - **App Group Outbox migration** (per-user scoping + cross-process drain claim) — `Outbox.defaultDirectory(userId:)` still resolves under the app-sandboxed container (its own doc comment says "Plan 3 is expected to move this" — stale; it's now plan 5's prerequisite). A share extension process can't see the app's Outbox until this migrates, and the per-instance `isDraining` flag doesn't span processes.
  - **Extension memory budget** — the composer's attachment paths still read whole-file `Data` eagerly; a share extension's ~120MB cap needs streamed/bounded reads before this pipeline is reused there.
  - **Abandoned-timer generation check [T6] / double-location-commit race [T8]** (triaged above) — watch for real-device manifestation once the extension exercises location capture under tighter time/memory pressure than the host app.
  - **T9 date-wrap cosmetic** — the located-note footer wraps its date to 3 lines when a long location label + type badge share one row on a narrow 2-column card; two fix variants were tried live and rejected as worse (task-9-report.md). A real fix likely needs a layout rethink, not a footer patch — see masonry below.
  - **Masonry grid, serif display font (PPEditorialNew), rich slash-command composer, footer-pinning/row-height-equalization** — all explicitly deferred to plan 7 (visual/design parity) per this plan's Global Constraints and Task 6b's row-major-grid note.
- Other plan-2/3 carried items not specific to plan 5 (un-share/sticky-debounce race, Outbox attempts cap + dead-letter, `quick-pdf-summary` title-overwrite server fix) remain open and untouched by plan 4 — tracked in `docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md`'s own ledger, not restated here.

### Screenshots (read + described; ephemeral, kept in `/tmp`, not committed)

Captured via one temporary `StashUITests` method (`testTemporaryFourTabScreenshotRig` — written, run, screenshotted, then fully removed; `git diff` on `StashUITests.swift` confirmed zero residual diff before committing), same checkpoint/`xcrun simctl io screenshot` technique as every prior task. Tab order in the rig was Add → View → Settings → Ask (Ask last, deliberately — tapping another tab bar button immediately after an Ask send intermittently only dismissed the keyboard instead of switching, a live-reproduced glitch; putting Ask last sidesteps it without needing a real fix in a throwaway test).

- **Add tab** — the empty launch-tab composer: "Save a thought, a link, anything…" placeholder, attachment row (photos/camera/file/mic + lock + location-pin toggles), Add/Ask/View/Settings tab bar with Add active.
- **View tab (grid top)** — "12 items", search field, type chips (All/Links/Notes/Docs/Media/Collections), and excellent card variety in one screen: the located-note text card (footer shows date + location pin + "text" badge), the video-link favicon-plate ("Y" avatar, "youtube.com", "preview limited · saved anyway", "YOUTUBE.COM" kicker), and (partially visible) the repo dark plate (`</> supabase/su…`) and a document file-plate ("PDF").
- **View tab (scrolled)** — further variety: the public-sticky text card (yellow sticky badge), the audio card (M4A chip, violet annotation bar showing the user's own note under the AI transcript description), and the two plain-color image fixtures (green/purple squares, standard-height covers).
- **Settings tab** — Account (email, username, public feed URL), Phone Numbers, Tags (`plan2-smoke`: 12, `ios-test`: 1), and Subscription: **"Status: Expired"** with "Manage on gostash.it" — a direct, live, in-app confirmation of the Stripe-lapse blocker documented above.
- **Ask tab** — shows a prior successful sourced exchange (persisted server-side conversation history; `--uitest-reset-auth` only resets local auth, not server-side `conversations`) above a red **"AI chat needs an active trial or subscription."** banner, with this rig's own question ("What's in my stash?") sitting unsent in the composer — the send was blocked by the same client-side subscription gate documented throughout this plan (Ask was deliberately visited last in the rig, well past the fail-open `isLoading` window other smokes sometimes win by accident, so this screenshot shows the gate's steady-state behavior honestly rather than a lucky pass). That visible historical exchange is dated **2026-08-12** (confirmed via REST while investigating the `testAskSmoke` finding above) — it predates this entire plan; nothing from any plan-4 run appears in this account's conversation history at all.
