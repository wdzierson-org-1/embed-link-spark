# Stash iOS — Plan 2: Capture (Add tab, uploads, Outbox, editing)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app capture-first — a resident Add-tab composer (text/URL/photos/camera/files) with an offline Outbox, plus full item editing (title/description/notes-append/tags/public toggle/delete) — and clear plan 1's hygiene list.

**Architecture:** Same thin-client shape as plan 1: capture goes through the platform endpoints (`add-note`/`add-url`/`add-file`) via a new `CaptureAPI` with hand-rolled URLSession JSON POSTs (injectable for tests, reusable by the Outbox and by plan 3's share extension); edits go through PostgREST PATCH + the web's decoupled embedding-refresh contract, ported as `EmbeddingRefresher`. Views stay prose-specified where logic is code-specified and tested (plan-1 precedent).

**Tech Stack:** Swift 5.10 / SwiftUI, StashKit (supabase-swift 2.54.1 pinned), PhotosUI (`PhotosPicker`), `UIImagePickerController` wrapper for camera, XcodeGen, raw `xcodebuild`/`simctl` (XcodeBuildMCP when connected).

**Plan sequence:** 1 foundation (SHIPPED, merged 416ea4c) → **2 (this)** → 3 share extension → 4 voice + Ask → 5 widgets/intents/Settings/TestFlight.

## Global Constraints

- Everything from plan 1 still binds: min iOS 17, worktree-branch commits (no push), warning-free builds, exact-path `git add`, never commit `ios/.env.test.local` or credentials, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer, deploy edge functions via `supabase functions deploy <name>` + verify with `supabase functions list`, `swift test` from `ios/StashKit`, app builds with the task-8-report destination/derivedDataPath conventions, sim UDID-pinned, `--uitest-reset-auth` pattern, SourceKit single-file diagnostics are known indexer noise.
- Launch tab flips to **Add** in this plan (spec: "the app opens ready to capture"; keyboard raises on tap, not on launch).
- Capture routing (port of web `UnifiedInputPanel` submit, with the spec's collections cut): text containing a URL → `add-url` with `content` = text minus the URL; text only → `add-note`; ONE file (+optional text) → upload + `add-file` with `content` = text; MULTIPLE files → one `add-file` per file with no content, and non-empty text becomes its own separate note (composer shows "Saving N items").
- Upload paths are UUID-named: `<userId>/<UUID().uuidString.lowercased()>.<ext>` (hygiene: replaces web's `Date.now()` names; also moots URL-encoding).
- Web-parity rules (from source, exact): items PATCH → embedding refresh ONLY when a field in [title, description, content, supplemental_note] changed, scheduled from the FULL merged row (PostgREST `.select().single()` return), 4s idle debounce per item, latest-write-wins, delete-embeddings-then-insert (`src/utils/itemOperations.ts:10-75`). Field autosave debounce 400ms; close sends changed-fields-only and skips no-op PATCHes (`src/hooks/useEditItemSave.ts:65-118`). Delete = embeddings rows then item row (`itemOperations.ts:127-174`). Un-share with a sticky note present → UI confirms, then PATCH `{is_public: false, supplemental_note: null}` (`src/hooks/useEditItemSheet.ts:128-141`). Tags: `increment_tag_usage` RPC `{tag_name: lowercased, user_uuid}` → tagId, then insert `item_tags {item_id, tag_id}` if absent (`src/hooks/useTags.ts:38-97`); AI suggestions via `get-relevant-tags` `{title, content, description, availableTags}` → `{relevantTags}`, filter already-applied, cap 6 (`src/components/ItemTagsManager.tsx:42-85`).
- Embedding text builder port (exact field order, `itemOperations.ts:15-37`): title, description, plainText(content), supplemental_note, url, summary, page_body — joined with single spaces.
- Info.plist tripwire (ledgered in plan 1): this plan adds `NSCameraUsageDescription` via `project.yml` — after `xcodegen generate`, DIFF the committed `ios/Stash/Info.plist` and confirm the key landed; if xcodegen preserved a stale plist, delete the committed plist and regenerate before proceeding.
- Permanent fixtures gain: one public+sticky-note item, one real PDF document (committed asset), created via the platform APIs, titled `UITEST-FIXTURE:` (never cleaned).
- Do NOT build: collections assembly, rich-text editor (append-only per spec), voice (plan 4), share extension/App Group (plan 3), offline UI simulation tests (Outbox is unit-tested; sim network-kill is flaky — disclosed skip).

---

### Task 1: `add-file` hardening (hygiene) — error logging + path sanity

**Files:**
- Modify: `supabase/functions/add-file/index.ts`

**Interfaces:**
- Consumes: the deployed function from plan 1 (insert at ~line 41-74, enrichment closure at ~line 76-123).
- Produces: same contract, plus: 400 on `file_path` containing `..` or empty segments; every enrichment `invoke` checks `{ error }` and `console.error`s with the function name and itemId.

- [ ] **Step 1: Add path sanity right after the ownership check** (`file_path.startsWith(...)` block):

```ts
    const segments = file_path.split('/');
    if (segments.some((s: string) => s === '' || s === '..')) {
      return json(400, { error: 'file_path contains invalid segments' });
    }
```

- [ ] **Step 2: Check every discarded invoke result in the enrichment closure.** Image branch becomes:

```ts
        if (type === 'image') {
          const { error: imgErr } = await supabase.functions.invoke('analyze-image', {
            body: { itemId: item.id, imageUrl: publicUrl },
          });
          if (imgErr) console.error('add-file: analyze-image failed for', item.id, imgErr);
        }
```

Document branch: capture `{ error: embErr }` from the baseline `generate-embeddings` call, `{ error: qpsErr }` from `quick-pdf-summary`, `{ error: extErr }` from `extract-pdf-text`, each logged as `console.error('add-file: <fn> failed for', item.id, <err>)`. Audio branch already checks `tErr`; also capture and log the trailing `generate-embeddings` error the same way.

- [ ] **Step 3: Deploy + verify + contract re-check**

```bash
cd "$(git rev-parse --show-toplevel)"
supabase functions deploy add-file
supabase functions list | grep add-file
```

Then re-run the three Task-1 (plan 1) curl contract checks (401/400/403 — env setup per plan-1 Task 1 Step 4, creds from `ios/.env.test.local`) plus the new one:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/functions/v1/add-file" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"file_path\":\"$UID/../evil.png\",\"mime_type\":\"image/png\"}"   # expect 400
```

- [ ] **Step 4: Commit** — `git add supabase/functions/add-file/index.ts && git commit -m "fix: add-file path sanity + enrichment error logging"`

---

### Task 2: `CaptureAPI` — typed clients for add-note / add-url / add-file + UUID uploads

**Files:**
- Create: `ios/StashKit/Sources/StashKit/CaptureAPI.swift`
- Test: `ios/StashKit/Tests/StashKitTests/CaptureAPITests.swift`

**Interfaces:**
- Consumes: `StashConfig`, `StashClient` (auth session + storage), `Item` + `Item.decoder` (plan 1).
- Produces (Outbox, composer, editor, and plan 3's extension all consume these):

```swift
public protocol JSONPosting: Sendable {
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data
}
public struct FunctionsPoster: JSONPosting { public init() {} }   // real URLSession impl
public struct CaptureAPI: Sendable {
    public init(poster: JSONPosting = FunctionsPoster())
    public func addNote(content: String, title: String?, isPublic: Bool, accessToken: String) async throws -> Item
    public func addURL(_ url: String, note: String, isPublic: Bool, accessToken: String) async throws -> Item
    public func addFile(path: String, mimeType: String, fileSize: Int?, content: String?, isPublic: Bool, accessToken: String) async throws -> Item
}
public func makeUploadPath(userId: UUID, fileExtension: String) -> String  // "<uid>/<uuid>.<ext>", lowercased
public func uploadToStorage(data: Data, path: String, contentType: String) async throws  // supabase-swift storage
public enum CaptureError: Error, Equatable { case badStatus(Int), malformedResponse }
```

Response envelopes (from the deployed functions): add-note → `{ success, note }`; add-url and add-file → `{ success, item }`. `CaptureAPI` normalizes all three to `Item`.

- [ ] **Step 1: Failing tests** (stub poster; no network):

```swift
import XCTest
@testable import StashKit

final class StubPoster: JSONPosting, @unchecked Sendable {
    var lastPath: String?
    var lastBody: [String: Any] = [:]
    var response: Data = Data()
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        lastPath = path; lastBody = body; return response
    }
}

final class CaptureAPITests: XCTestCase {
    let itemJSON = """
    {"success":true,"item":{"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b","type":"image",
     "title":"t","content":null,"url":null,"file_path":"u/x.png","description":null,
     "summary":null,"created_at":"2026-08-11T10:00:00+00:00","mime_type":"image/png",
     "is_public":false,"supplemental_note":null}}
    """.data(using: .utf8)!
    let noteJSON = """
    {"success":true,"note":{"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4c","type":"text",
     "title":"hello","content":"hello world","url":null,"file_path":null,"description":null,
     "summary":null,"created_at":"2026-08-11T10:00:00+00:00","mime_type":null,
     "is_public":false,"supplemental_note":null}}
    """.data(using: .utf8)!

    func testAddNoteEnvelopeAndPayload() async throws {
        let stub = StubPoster(); stub.response = noteJSON
        let api = CaptureAPI(poster: stub)
        let item = try await api.addNote(content: "hello world", title: nil, isPublic: false, accessToken: "jwt")
        XCTAssertEqual(stub.lastPath, "add-note")
        XCTAssertEqual(stub.lastBody["content"] as? String, "hello world")
        XCTAssertNil(stub.lastBody["title"])
        XCTAssertEqual(item.type, .text)
        XCTAssertEqual(item.title, "hello")
    }

    func testAddURLPayload() async throws {
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)
        _ = try await api.addURL("https://example.com", note: "ctx", isPublic: true, accessToken: "jwt")
        XCTAssertEqual(stub.lastPath, "add-url")
        XCTAssertEqual(stub.lastBody["url"] as? String, "https://example.com")
        XCTAssertEqual(stub.lastBody["content"] as? String, "ctx")
        XCTAssertEqual(stub.lastBody["is_public"] as? Bool, true)
    }

    func testAddFilePayloadAndDecode() async throws {
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)
        let item = try await api.addFile(path: "u/x.png", mimeType: "image/png", fileSize: 12,
                                         content: nil, isPublic: false, accessToken: "jwt")
        XCTAssertEqual(stub.lastPath, "add-file")
        XCTAssertEqual(stub.lastBody["file_path"] as? String, "u/x.png")
        XCTAssertEqual(item.type, .image)
    }

    func testMalformedResponseThrows() async {
        let stub = StubPoster(); stub.response = Data("{}".utf8)
        let api = CaptureAPI(poster: stub)
        do { _ = try await api.addNote(content: "x", title: nil, isPublic: false, accessToken: "jwt"); XCTFail() }
        catch { XCTAssertEqual(error as? CaptureError, .malformedResponse) }
    }

    func testUploadPathShape() {
        let uid = UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!
        let path = makeUploadPath(userId: uid, fileExtension: "PNG")
        XCTAssertTrue(path.hasPrefix("6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b/"))
        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertEqual(path.split(separator: "/").count, 2)
        XCTAssertNil(path.rangeOfCharacter(from: CharacterSet.uppercaseLetters))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cd ios/StashKit && swift test 2>&1 | tail -5` → FAIL (symbols missing).
- [ ] **Step 3: Implement**

```swift
import Foundation
import Supabase

public enum CaptureError: Error, Equatable { case badStatus(Int), malformedResponse }

public protocol JSONPosting: Sendable {
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data
}

/// POSTs to <supabase>/functions/v1/<path> with the platform's two auth headers.
public struct FunctionsPoster: JSONPosting {
    public init() {}
    public func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

public struct CaptureAPI: Sendable {
    let poster: JSONPosting
    public init(poster: JSONPosting = FunctionsPoster()) { self.poster = poster }

    public func addNote(content: String, title: String?, isPublic: Bool, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["content": content, "is_public": isPublic]
        if let title { body["title"] = title }
        return try await send(path: "add-note", body: body, envelopeKey: "note", accessToken: accessToken)
    }

    public func addURL(_ url: String, note: String, isPublic: Bool, accessToken: String) async throws -> Item {
        let body: [String: Any] = ["url": url, "content": note, "is_public": isPublic]
        return try await send(path: "add-url", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    public func addFile(path: String, mimeType: String, fileSize: Int?, content: String?,
                        isPublic: Bool, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["file_path": path, "mime_type": mimeType, "is_public": isPublic]
        if let fileSize { body["file_size"] = fileSize }
        if let content, !content.isEmpty { body["content"] = content }
        return try await send(path: "add-file", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    private func send(path: String, body: [String: Any], envelopeKey: String, accessToken: String) async throws -> Item {
        let data = try await poster.post(path: path, body: body, accessToken: accessToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itemObject = root[envelopeKey],
              let itemData = try? JSONSerialization.data(withJSONObject: itemObject)
        else { throw CaptureError.malformedResponse }
        return try Item.decoder.decode(Item.self, from: itemData)
    }
}

public func makeUploadPath(userId: UUID, fileExtension: String) -> String {
    "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension.lowercased())"
}

public func uploadToStorage(data: Data, path: String, contentType: String) async throws {
    try await StashClient.shared.storage.from("stash-media")
        .upload(path, data: data, options: FileOptions(contentType: contentType))
}
```

(If `storage.from().upload` has a different signature in v2.54.1, check the checkout under `ios/StashKit/.build/checkouts/supabase-swift/Sources/Storage` and adapt with disclosure — plan-1 precedent.)

- [ ] **Step 4: Run tests** — PASS (suite 20/20: 15 + 5 new). **Step 5: Commit** — `git add ios/StashKit && git commit -m "feat(ios): CaptureAPI with typed platform-endpoint clients (tested)"`

---

### Task 3: `Outbox` — durable capture queue

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Outbox.swift`
- Test: `ios/StashKit/Tests/StashKitTests/OutboxTests.swift`

**Interfaces:**
- Consumes: `CaptureAPI` (Task 2).
- Produces (composer wires drain-on-foreground; plan 3's extension enqueues directly):

```swift
public struct OutboxEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case note, url, file }
    public var id: UUID
    public var kind: Kind
    public var payload: [String: String]   // string-keyed capture fields
    public var createdAt: Date
    public var attempts: Int
}
public actor Outbox {
    public init(directory: URL)                      // one JSON file per entry
    public static func defaultDirectory() -> URL     // Application Support/StashOutbox (App Group in plan 3)
    public func enqueue(_ kind: OutboxEntry.Kind, payload: [String: String]) async throws
    public func pending() async -> [OutboxEntry]     // oldest first
    public func drain(api: CaptureAPI, accessToken: String) async -> Int  // returns sent count; failures stay queued, attempts+1
}
```

Payload keys by kind — note: `content`, `title?`, `is_public`; url: `url`, `content`, `is_public`; file: `file_path`, `mime_type`, `file_size?`, `content?`, `is_public` (`is_public`/`file_size` stored as `"true"`/`"1234"` strings, converted at drain).

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import StashKit

final class OutboxTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeStub(responding: Data) -> StubPoster { let s = StubPoster(); s.response = responding; return s }
    let noteJSON = CaptureAPITests().noteJSON   // reuse the fixture from Task 2's test file

    func testEnqueuePersistsAcrossInstances() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "offline note", "is_public": "false"])
        let rehydrated = Outbox(directory: dir)
        let pending = await rehydrated.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["content"], "offline note")
    }

    func testDrainSendsAndRemoves() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let api = CaptureAPI(poster: makeStub(responding: noteJSON))
        let sent = await box.drain(api: api, accessToken: "jwt")
        XCTAssertEqual(sent, 1)
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDrainFailureRetainsAndIncrementsAttempts() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let failing = StubPoster(); failing.response = Data("{}".utf8)   // malformed → throw
        let sent = await box.drain(api: CaptureAPI(poster: failing), accessToken: "jwt")
        XCTAssertEqual(sent, 0)
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].attempts, 1)
    }

    func testOldestFirstOrdering() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "first", "is_public": "false"])
        try await box.enqueue(.note, payload: ["content": "second", "is_public": "false"])
        let pending = await box.pending()
        XCTAssertEqual(pending.map { $0.payload["content"] }, ["first", "second"])
    }
}
```

(Make `noteJSON` and `StubPoster` internal-visible for reuse, or duplicate the small fixture literal in this file — either is fine; if duplicating, say so in the report.)

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement**

```swift
import Foundation

public struct OutboxEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case note, url, file }
    public var id: UUID
    public var kind: Kind
    public var payload: [String: String]
    public var createdAt: Date
    public var attempts: Int
}

/// One JSON file per pending capture. Survives crashes and offline periods;
/// plan 3 moves the directory into the App Group container.
public actor Outbox {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "StashOutbox")
    }

    public func enqueue(_ kind: OutboxEntry.Kind, payload: [String: String]) throws {
        let entry = OutboxEntry(id: UUID(), kind: kind, payload: payload, createdAt: Date(), attempts: 0)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: entry.id), options: .atomic)
    }

    public func pending() -> [OutboxEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? JSONDecoder().decode(OutboxEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func drain(api: CaptureAPI, accessToken: String) async -> Int {
        var sent = 0
        for var entry in pending() {
            do {
                _ = try await send(entry, api: api, accessToken: accessToken)
                try? FileManager.default.removeItem(at: fileURL(for: entry.id))
                sent += 1
            } catch {
                entry.attempts += 1
                if let data = try? JSONEncoder().encode(entry) {
                    try? data.write(to: fileURL(for: entry.id), options: .atomic)
                }
            }
        }
        return sent
    }

    private func send(_ entry: OutboxEntry, api: CaptureAPI, accessToken: String) async throws -> Item {
        let isPublic = entry.payload["is_public"] == "true"
        switch entry.kind {
        case .note:
            return try await api.addNote(content: entry.payload["content"] ?? "",
                                         title: entry.payload["title"], isPublic: isPublic,
                                         accessToken: accessToken)
        case .url:
            return try await api.addURL(entry.payload["url"] ?? "",
                                        note: entry.payload["content"] ?? "", isPublic: isPublic,
                                        accessToken: accessToken)
        case .file:
            return try await api.addFile(path: entry.payload["file_path"] ?? "",
                                         mimeType: entry.payload["mime_type"] ?? "application/octet-stream",
                                         fileSize: entry.payload["file_size"].flatMap(Int.init),
                                         content: entry.payload["content"], isPublic: isPublic,
                                         accessToken: accessToken)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
```

- [ ] **Step 4: Run tests** — PASS. **Step 5: Commit** — `git commit -am "feat(ios): file-backed Outbox actor with drain semantics (tested)"`

---

### Task 4: `ItemStore` — refresh generation token + `applyNew` + pinned column contract

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/ItemStore.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemStoreTests.swift` (add cases), `ios/StashKit/Tests/StashKitTests/ItemDecodingTests.swift` (add one case)

**Interfaces:**
- Consumes: existing `ItemStore` (plan 1).
- Produces: `func applyNew(_ item: Item)` (prepend if id absent — composer calls it on capture success); stale-refresh protection: a refresh that started before a newer one MUST NOT overwrite the newer one's results (closes final-review Important #3).

- [ ] **Step 1: Failing tests.** Generation token (uses a gate-controllable fetcher):

```swift
final class GatedFetcher: ItemsFetching, @unchecked Sendable {
    var gates: [CheckedContinuation<[Item], Error>] = []
    var pendingTypes: [[ItemType]?] = []
    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        pendingTypes.append(types)
        return try await withCheckedThrowingContinuation { gates.append($0) }
    }
    func fetchDetail(id: UUID) async throws -> Item { fatalError("unused") }
    func release(_ index: Int, with items: [Item]) { gates[index].resume(returning: items) }
}

func testStaleRefreshCannotOverwriteNewerOne() async {
    let fetcher = GatedFetcher()
    let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)
    let old = makeItem(minutesAgo: 99)
    let new = makeItem(minutesAgo: 1)

    async let first: Void = store.refresh()          // starts, blocks on gate 0
    try? await Task.sleep(for: .milliseconds(50))
    async let second: Void = store.refresh()         // starts, blocks on gate 1
    try? await Task.sleep(for: .milliseconds(50))

    fetcher.release(1, with: [new])                  // newer refresh completes first
    try? await Task.sleep(for: .milliseconds(50))
    fetcher.release(0, with: [old])                  // stale refresh completes last
    _ = await (first, second)

    XCTAssertEqual(store.items.map(\.id), [new.id])  // stale result dropped
}

func testApplyNewPrependsOnceOnly() async {
    let fetcher = StubFetcher()
    let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)
    let item = makeItem(minutesAgo: 0)
    store.applyNew(item)
    store.applyNew(item)
    XCTAssertEqual(store.items.count, 1)
    XCTAssertEqual(store.items.first?.id, item.id)
}
```

Pinned column contract (ItemDecodingTests):

```swift
func testListColumnsMatchWebContractLiterally() {
    XCTAssertEqual(Item.listColumns,
        "id,type,title,content,url,file_path,description,summary,created_at,mime_type,is_public,supplemental_note")
    XCTAssertEqual(Item.detailColumns, Item.listColumns + ",page_body")
}
```

- [ ] **Step 2: Run to verify failure** (stale test fails against current code), then **Step 3: Implement** in `ItemStore`:

```swift
    private var loadGeneration = 0

    public func applyNew(_ item: Item) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: 0)
    }
```

and in `load(reset:)`: increment `loadGeneration` at entry into a local `let generation = ...`; after the `await fetcher.fetchPage(...)` returns (and in the catch path), `guard generation == loadGeneration else { return }` before mutating `items`/`hasMore`/`loadError`. `isLoading` becomes `activeLoads` counting or is set false only when `generation == loadGeneration` — keep it simple: `defer { if generation == loadGeneration { isLoading = false } }` with `isLoading = true` at entry.

- [ ] **Step 4: All tests PASS** (suite now 27). **Step 5: Commit** — `git commit -am "feat(ios): ItemStore generation token + applyNew + pinned column contract (tested)"`

---

### Task 5: `TipTapAppend` + `EmbeddingRefresher` (edit-side ports)

**Files:**
- Create: `ios/StashKit/Sources/StashKit/TipTapAppend.swift`, `ios/StashKit/Sources/StashKit/EmbeddingRefresher.swift`
- Test: `ios/StashKit/Tests/StashKitTests/TipTapAppendTests.swift`, `ios/StashKit/Tests/StashKitTests/EmbeddingRefresherTests.swift`

**Interfaces:**
- Consumes: `renderTipTap` conventions (plan 1), `Item`.
- Produces:

```swift
public func appendNoteParagraph(to content: String?, note: String) -> String
// nil/empty → note as plain text; TipTap doc JSON → doc with appended
// {"type":"paragraph","content":[{"type":"text","text":note}]}; plain text → content + "\n\n" + note

public func buildEmbeddingText(from item: Item) -> String
// exact web order: title, description, plainText(content), supplementalNote, url, summary, pageBody

public protocol EmbeddingSyncing: Sendable {
    func replaceEmbeddings(itemId: UUID, text: String) async throws
}
public struct SupabaseEmbeddingSyncer: EmbeddingSyncing { public init() {} }
// DELETE embeddings where item_id, then functions.invoke generate-embeddings {itemId, textContent}
public actor EmbeddingRefresher {
    public init(syncer: EmbeddingSyncing, idle: Duration = .seconds(4))
    public func schedule(_ item: Item)   // per-item idle debounce, latest row wins
}
```

`plainText(content)` = `String(renderTipTap(content).characters)` — reuses the tested renderer as the plain-text extractor (mirror of the web's `extractPlainTextFromNovelContent` role).

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import StashKit

final class TipTapAppendTests: XCTestCase {
    func testEmptyContentBecomesPlainNote() {
        XCTAssertEqual(appendNoteParagraph(to: nil, note: "hi"), "hi")
        XCTAssertEqual(appendNoteParagraph(to: "", note: "hi"), "hi")
    }
    func testPlainTextGetsSeparatedAppend() {
        XCTAssertEqual(appendNoteParagraph(to: "existing", note: "more"), "existing\n\nmore")
    }
    func testDocJSONGetsParagraphNode() throws {
        let doc = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]}"#
        let out = appendNoteParagraph(to: doc, note: "b")
        let root = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
        let content = root["content"] as! [[String: Any]]
        XCTAssertEqual(content.count, 2)
        let last = content[1]
        XCTAssertEqual(last["type"] as? String, "paragraph")
        let text = ((last["content"] as! [[String: Any]])[0])["text"] as? String
        XCTAssertEqual(text, "b")
        // Round-trips through the renderer
        XCTAssertTrue(String(renderTipTap(out).characters).contains("b"))
    }
    func testNonDocJSONTreatedAsPlainText() {
        XCTAssertEqual(appendNoteParagraph(to: #"{"weird":1}"#, note: "n"), "{\"weird\":1}\n\nn")
    }
}

final class RecordingSyncer: EmbeddingSyncing, @unchecked Sendable {
    var calls: [(UUID, String)] = []
    func replaceEmbeddings(itemId: UUID, text: String) async throws { calls.append((itemId, text)) }
}

final class EmbeddingRefresherTests: XCTestCase {
    func fixture(title: String) -> Item {
        Item(id: UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!, type: .text,
             title: title, content: "body", url: "https://x.com", filePath: nil,
             description: "desc", summary: "sum", pageBody: "pb", supplementalNote: "sn",
             mimeType: nil, isPublic: false, createdAt: .now)
    }
    func testEmbeddingTextOrderMatchesWeb() {
        let text = buildEmbeddingText(from: fixture(title: "T"))
        XCTAssertEqual(text, "T desc body sn https://x.com sum pb")
    }
    func testLatestRowWinsAfterIdle() async throws {
        let syncer = RecordingSyncer()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(60))
        await refresher.schedule(fixture(title: "first"))
        await refresher.schedule(fixture(title: "second"))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(syncer.calls.count, 1)
        XCTAssertTrue(syncer.calls[0].1.hasPrefix("second"))
    }
}
```

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement**

```swift
import Foundation

public func appendNoteParagraph(to content: String?, note: String) -> String {
    guard let content, !content.isEmpty else { return note }
    guard content.hasPrefix("{"),
          let data = content.data(using: .utf8),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          root["type"] as? String == "doc"
    else { return content + "\n\n" + note }

    var children = root["content"] as? [[String: Any]] ?? []
    children.append(["type": "paragraph", "content": [["type": "text", "text": note]]])
    root["content"] = children
    guard let out = try? JSONSerialization.data(withJSONObject: root),
          let string = String(data: out, encoding: .utf8) else { return content + "\n\n" + note }
    return string
}
```

```swift
import Foundation
import Supabase

/// Port of the web's decoupled search-index refresh (itemOperations.ts:10-75):
/// saves resolve on the PATCH; embeddings regenerate on a per-item idle
/// debounce from the full merged row, latest-write-wins.
public func buildEmbeddingText(from item: Item) -> String {
    var parts: [String] = []
    if let t = item.title, !t.isEmpty { parts.append(t) }
    if let d = item.description, !d.isEmpty { parts.append(d) }
    if let c = item.content {
        let plain = String(renderTipTap(c).characters)
        if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(plain) }
    }
    if let s = item.supplementalNote, !s.isEmpty { parts.append(s) }
    if let u = item.url, !u.isEmpty { parts.append(u) }
    if let s = item.summary, !s.isEmpty { parts.append(s) }
    if let p = item.pageBody, !p.isEmpty { parts.append(p) }
    return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
}

public protocol EmbeddingSyncing: Sendable {
    func replaceEmbeddings(itemId: UUID, text: String) async throws
}

public struct SupabaseEmbeddingSyncer: EmbeddingSyncing {
    public init() {}
    public func replaceEmbeddings(itemId: UUID, text: String) async throws {
        try await StashClient.shared.from("embeddings").delete()
            .eq("item_id", value: itemId.uuidString).execute()
        try await StashClient.shared.functions.invoke("generate-embeddings",
            options: FunctionInvokeOptions(body: ["itemId": itemId.uuidString, "textContent": text]))
    }
}

public actor EmbeddingRefresher {
    private let syncer: EmbeddingSyncing
    private let idle: Duration
    private var pending: [UUID: Task<Void, Never>] = [:]

    public init(syncer: EmbeddingSyncing, idle: Duration = .seconds(4)) {
        self.syncer = syncer
        self.idle = idle
    }

    public func schedule(_ item: Item) {
        pending[item.id]?.cancel()
        pending[item.id] = Task { [idle, syncer] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            let text = buildEmbeddingText(from: item)
            guard !text.isEmpty else { return }
            do { try await syncer.replaceEmbeddings(itemId: item.id, text: text) }
            catch { print("Embedding refresh failed (non-fatal): \(error)") }
        }
    }
}
```

(`functions.invoke` signature: check the v2.54.1 checkout `Sources/Functions` if it differs; adapt with disclosure.)

- [ ] **Step 4: Tests PASS** (suite ~33). **Step 5: Commit** — `git commit -am "feat(ios): TipTap append + decoupled embedding refresher, web-parity (tested)"`

---

### Task 6: `ItemEditor` — save / delete / public toggle / tag operations

**Files:**
- Create: `ios/StashKit/Sources/StashKit/ItemEditor.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemEditorTests.swift`

**Interfaces:**
- Consumes: `EmbeddingRefresher` (Task 5), `StashClient`, `StashTag` (plan 1 TagsAPI).
- Produces:

```swift
public struct ItemPatch: Equatable, Sendable {
    public var title: String?; public var description: String?
    public var content: String?; public var supplementalNote: String?; public var isPublic: Bool?
    public init(...)                 // all nil by default
    public var isEmpty: Bool
    public var restBody: [String: Any?]   // snake_case keys, only non-nil fields
    public var touchesTextFields: Bool    // any of title/description/content/supplemental_note set
}
public func changedFields(from snapshot: Item, title: String, description: String,
                          supplementalNote: String) -> ItemPatch
// changed-fields-only diff, "" compared against nil-as-"" (web flushAndFinalSave semantics)

public protocol ItemPatching: Sendable {
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item        // PATCH + .select().single()
    func deleteItemCascade(itemId: UUID) async throws                      // embeddings rows then item row
    func itemTags(itemId: UUID) async throws -> [StashTag]
    func addTag(named: String, userId: UUID, itemId: UUID) async throws    // increment_tag_usage RPC → item_tags insert-if-absent
    func removeTag(tagId: UUID, itemId: UUID) async throws                 // item_tags row delete
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String]
}
public struct SupabaseItemPatcher: ItemPatching { public init() {} }
@MainActor public final class ItemEditor {                                 // used by the detail view
    public init(patcher: ItemPatching, refresher: EmbeddingRefresher)
    public func save(itemId: UUID, patch: ItemPatch) async throws -> Item  // skips when patch.isEmpty; schedules refresher when touchesTextFields
    public func togglePublic(item: Item, to isPublic: Bool) -> ItemPatch   // pure: builds the patch incl. sticky-clear rule
    public func delete(itemId: UUID) async throws
}
```

- [ ] **Step 1: Failing tests** — pure logic + recorded-patcher behavior:

```swift
import XCTest
@testable import StashKit

final class RecordingPatcher: ItemPatching, @unchecked Sendable {
    var patches: [(UUID, ItemPatch)] = []
    var deleted: [UUID] = []
    var patchResult: Item!
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item { patches.append((itemId, patch)); return patchResult }
    func deleteItemCascade(itemId: UUID) async throws { deleted.append(itemId) }
    func itemTags(itemId: UUID) async throws -> [StashTag] { [] }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws {}
    func removeTag(tagId: UUID, itemId: UUID) async throws {}
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] { [] }
}

@MainActor
final class ItemEditorTests: XCTestCase {
    func snapshot(title: String? = "T", note: String? = nil, isPublic: Bool = false) -> Item {
        Item(id: UUID(), type: .text, title: title, content: nil, url: nil, filePath: nil,
             description: "D", summary: nil, pageBody: nil, supplementalNote: note,
             mimeType: nil, isPublic: isPublic, createdAt: .now)
    }

    func testChangedFieldsDiffIsMinimal() {
        let patch = changedFields(from: snapshot(), title: "T", description: "D2", supplementalNote: "")
        XCTAssertNil(patch.title)                       // unchanged → omitted
        XCTAssertEqual(patch.description, "D2")
        XCTAssertNil(patch.supplementalNote)            // "" vs nil → unchanged
        XCTAssertFalse(patch.isEmpty)
        XCTAssertTrue(patch.touchesTextFields)
    }

    func testNoOpDiffIsEmpty() {
        let patch = changedFields(from: snapshot(), title: "T", description: "D", supplementalNote: "")
        XCTAssertTrue(patch.isEmpty)
    }

    func testSaveSkipsEmptyPatch() async throws {
        let patcher = RecordingPatcher()
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)))
        _ = try? await editor.save(itemId: UUID(), patch: ItemPatch())
        XCTAssertTrue(patcher.patches.isEmpty)
    }

    func testUnshareWithNoteClearsSticky() {
        let editor = ItemEditor(patcher: RecordingPatcher(), refresher: EmbeddingRefresher(syncer: RecordingSyncer()))
        let patch = editor.togglePublic(item: snapshot(note: "sticky", isPublic: true), to: false)
        XCTAssertEqual(patch.isPublic, false)
        XCTAssertEqual(patch.supplementalNote, "")       // maps to null in restBody
        XCTAssertTrue(patch.restBody.keys.contains("supplemental_note"))
        let toPublic = editor.togglePublic(item: snapshot(note: nil, isPublic: false), to: true)
        XCTAssertNil(toPublic.supplementalNote)          // sharing never touches the note
    }
}
```

Semantics note baked into the design: `ItemPatch.supplementalNote = ""` encodes as SQL `null` in `restBody` (the web sends `supplemental_note: null` on un-share) — document this in a code comment.

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement.** `SupabaseItemPatcher` concrete calls: `patch` → `StashClient.shared.from("items").update(patch.restBody-as-AnyJSON).eq("id",...).select(Item.detailColumns).single().execute().data` decoded via `Item.decoder` (use `AnyJSON`/`[String: AnyJSON]` conversion if the SDK requires Encodable bodies — check the checkout, disclose adaptations); `deleteItemCascade` → delete `embeddings` where `item_id`, then delete `items` where `id` (web order, `itemOperations.ts:135-155`); `itemTags` → `from("item_tags").select("tags(id,name,usage_count)").eq("item_id",...)` flattened; `addTag` → `rpc("increment_tag_usage", params: ["tag_name": name.lowercased(), "user_uuid": userId.uuidString])` → returned tagId → check-then-insert `item_tags`; `suggestTags` → `functions.invoke("get-relevant-tags")` with the four-field body, returning `relevantTags`. `ItemEditor.save`: guard `!patch.isEmpty`; `let merged = try await patcher.patch(...)`; if `patch.touchesTextFields` `await refresher.schedule(merged)`; return merged. `togglePublic`: pure patch builder with the sticky-clear rule.
- [ ] **Step 4: Tests PASS.** **Step 5: Commit** — `git commit -am "feat(ios): ItemEditor with web-parity save/delete/toggle/tag ops (tested)"`

---

### Task 7: Capture composer — the Add tab goes live

**Files:**
- Create: `ios/Stash/Capture/CaptureComposerView.swift`, `ios/Stash/Capture/CaptureViewModel.swift`, `ios/Stash/Capture/CaptureAttachmentsRow.swift`, `ios/Stash/Capture/CameraPicker.swift`
- Modify: `ios/Stash/MainTabView.swift` (Add placeholder → composer; launch selection → `.add`), `ios/project.yml` (camera usage string), `ios/StashUITests/StashUITests.swift` (capture smoke)

**Interfaces:**
- Consumes: `CaptureAPI`, `makeUploadPath`, `uploadToStorage`, `Outbox`, `classifyMessage`-style URL regex (use `firstMatch(of:)` with the same pattern via a small `detectFirstURL(in:) -> String?` helper you add to `MessageRouting.swift` — public, one-line, reusing the existing pattern constant), `ItemStore.applyNew` via an `onCaptured: (Item) -> Void` closure that `MainTabView` threads to the View tab's store... **Correction for implementability:** `LibraryView` owns its store privately. Instead: `MainTabView` holds nothing; after a successful capture the composer switches the selected tab to `.view` ONLY on user tap of the success toast (default: stay in Add), and the View tab picks the new item up via its existing realtime subscription (~1s, live-proven in plan 1). `applyNew` is still used *within* the composer's own flow when the user is already on View — skip that complexity: realtime is the single reconciliation path. Document this in the code.
- Produces: `CaptureViewModel` with `text: String`, `attachments: [CaptureAttachment]` (`struct CaptureAttachment: Identifiable { id, data: Data, fileExtension: String, mimeType: String, kind: enum {photo, file} }`), `isPublic: Bool`, `pendingOutboxCount: Int`, `func submit() async -> CaptureOutcome` (`enum CaptureOutcome: Equatable { case saved(count: Int), queued(count: Int), nothingToSave }`), `func drainOutbox() async`. Routing per Global Constraints. On any `CaptureError`/network throw → enqueue to Outbox and return `.queued`. Upload size guard: images > 20 MB downscale via `UIImage` JPEG re-encode (max dimension 4096, quality 0.85); other files > 20 MB (docs) / > 100 MB (A/V) rejected with a message — mirror web limits (`MediaUploadTypes.ts:26-28`).

- [ ] **Step 1: Implement `CaptureViewModel`** (logic first — it is unit-testable if kept UIKit-free except the downscale hook; inject `downscale: (Data) -> Data` defaulting to the UIImage impl and add `CaptureViewModelTests` covering routing: URL text → addURL called; plain text → addNote; one file + text → addFile with content; three files + text → three addFile calls with nil content + one addNote; failure → outbox entry + `.queued`. Use `StubPoster` + tmp-dir Outbox. ~5 tests, same fixtures as Tasks 2-3.)
- [ ] **Step 2: Run the new tests** — PASS (StashKit suite grows to ~38-40).
- [ ] **Step 3: Build the views (prose-specified, plan-1 precedent).** `CaptureComposerView`: large multiline `TextEditor` with placeholder "Save a thought, a link, anything…", detected-URL chip under it (globe icon + truncated URL) when `detectFirstURL` hits; attachments row (thumbnails for photos via `UIImage(data:)`, doc icon + filename for files, X to remove); bottom bar: PhotosPicker (multi-select, `.images`), camera button (presents `CameraPicker` — `UIImagePickerController` wrapper, `.camera` source, unavailable-safe on simulator: hide the button when `!UIImagePickerController.isSourceTypeAvailable(.camera)`), file button (`.fileImporter`, `[.pdf, .plainText, .movie, .audio]` + images), public toggle (globe), Save button (disabled when nothing to save, `ProgressView` while submitting). Success → green toast "Saved" / "Saved N items" (tappable → switch tab to `.view`); queued → amber toast "Offline — will sync (N pending)". Outbox badge: small count pill in the composer header when `pendingOutboxCount > 0`; `.task` on the composer calls `drainOutbox()` on appear and on `scenePhase == .active` transitions. Accessibility identifiers: `capture.editor`, `capture.save`, `capture.urlchip`, `capture.toggle.public`, `capture.toast`. Keyboard: NOT auto-raised on launch (spec); tap the editor to focus.
- [ ] **Step 4: MainTabView + project.yml.** Launch selection `.add`; Add tab hosts `CaptureComposerView(userId:)`. project.yml `info.properties` gains `NSCameraUsageDescription: "Stash uses the camera to capture photos straight into your stash."`. Run `xcodegen generate`, then the TRIPWIRE: `git diff ios/Stash/Info.plist` must show the camera key added to the committed plist — if it does not, delete `ios/Stash/Info.plist`, regenerate, and confirm; state the outcome in your report.
- [ ] **Step 5: UI test `testCaptureSmoke`** (extend the existing suite; env-creds + reset-auth pattern): launch → assert Add tab is selected at launch (`capture.editor` exists without tapping any tab) → type "UITEST-CAPTURE: smoke note <epoch>" → tap `capture.save` → assert success toast → switch to View tab → assert a card containing "UITEST-CAPTURE: smoke note" appears within 10s (realtime path) → DELETE the created item via REST (curl, in the shell after the test — capture the id by querying `title=like.UITEST-CAPTURE*`; these smoke items are disposable, unlike UITEST-FIXTURE rows). Run the full UI suite 2× consecutively — green both times.
- [ ] **Step 6: Screenshots** — composer empty + composer with URL chip and 2 photo attachments (`/tmp/stash-plan2-task7-composer.png`, `-attach.png`); Read and describe both.
- [ ] **Step 7: Commit** — `git add ios && git commit -m "feat(ios): resident capture composer — text/URL/photos/camera/files with Outbox fallback"`

---

### Task 8: Edit in the detail sheet — fields, notes append, delete

**Files:**
- Create: `ios/Stash/Detail/EditableFieldsSection.swift`, `ios/Stash/Detail/NotesAppendComposer.swift`
- Modify: `ios/Stash/Detail/ItemDetailView.swift`, `ios/Stash/Detail/ItemDetailHeader.swift`, `ios/StashUITests/StashUITests.swift`

**Interfaces:**
- Consumes: `ItemEditor`, `changedFields`, `appendNoteParagraph`, `Debouncer` (plan 1), `ItemStore.applyDetail`.
- Produces: editable title/description with 400ms-debounced saves (each keystroke schedules `Debouncer`; the debounced action computes `changedFields` and calls `editor.save`), final changed-fields-only save on sheet dismiss (`.onDisappear`), notes append (TextField + "Add to notes" button → `appendNoteParagraph` → `editor.save(patch: ItemPatch(content: newContent))` → `store.applyDetail(merged)` → renderer re-renders), delete button (red, confirmation dialog "Delete this item? This can't be undone." → `editor.delete` → dismiss + store removal via `store.refresh()`), detail-sheet realtime (hygiene): `.onChange(of: store.items)` — when the sheet's item id appears with a newer field set (e.g. summary landed), merge it into the local `@State item` unless the user has unsaved local edits to that field (defer to local edits; comment the rule).

- [ ] **Step 1: Implement** per the interface block (views prose-specified; ALL mutation logic already tested in Tasks 5-6). Save-status indicator: subtle "Saving…"/"Saved" caption under the title field driven by an enum, mirroring web's `saveStatus`.
- [ ] **Step 2: UI test `testEditSmoke`**: open "UITEST-FIXTURE: note one" from View → edit title to append " (edited <epoch>)" → wait 1s (debounce) → dismiss → reopen → assert the edited title persisted → append a note "appended-<epoch>" via the composer → assert it renders in Notes → **restore**: clear the title back to exactly "UITEST-FIXTURE: note one" and PATCH the content back via REST in the shell (capture original content before the test with a GET; fixtures stay canonical). Full UI suite 2× green.
- [ ] **Step 3: Screenshot** edit-in-progress with Saved indicator (`/tmp/stash-plan2-task8-edit.png`); Read + describe.
- [ ] **Step 4: Commit** — `git add ios && git commit -m "feat(ios): detail editing — debounced field saves, notes append, delete"`

---

### Task 9: Tags + public toggle + sticky note UI

**Files:**
- Create: `ios/Stash/Detail/ItemTagsSection.swift`, `ios/Stash/Detail/PublicToggleSection.swift`
- Modify: `ios/Stash/Detail/ItemDetailView.swift`, `ios/StashUITests/StashUITests.swift`

**Interfaces:**
- Consumes: `ItemPatching` tag methods via `ItemEditor`'s patcher (expose `editor.patcher` or add pass-throughs `editor.itemTags/addTag/removeTag/suggestTags` — add the pass-throughs, keep the patcher private), `togglePublic` patch builder.
- Produces: tags section (current tags as removable chips ✕; input field with add-on-return; AI suggestion chips below — `suggestTags(title, plainText(content), description, availableTags)` filtered against applied, cap 6, tap-to-add; loading shimmer while suggesting); public section (toggle; when turning OFF with a sticky note present → `confirmationDialog` "Make private? The sticky note will be removed." destructive-confirm before applying `togglePublic`'s patch; when public → sticky-note TextField (yellow-tinted card) autosaving via the same debounced path with `supplementalNote`).

- [ ] **Step 1: Implement** per interface block.
- [ ] **Step 2: UI test `testTagsAndPublicSmoke`**: open "UITEST-FIXTURE: note two" → add tag "plan2-smoke" → assert chip appears → remove it → assert gone (and REST-verify the item_tags row count returned to baseline in the shell) → toggle public ON → type sticky "UITEST-FIXTURE sticky check" → toggle OFF → confirm dialog → assert sticky field gone; REST-verify `is_public=false, supplemental_note=null` → **this leaves note two exactly as it started**. Full UI suite 2× green.
- [ ] **Step 3: Commit** — `git add ios && git commit -m "feat(ios): tags manager + public toggle with sticky-note lifecycle"`

---

### Task 10: Permanent fixtures — public+sticky item and a real PDF document

**Files:**
- Create: `ios/fixtures/uitest-fixture.pdf` (commit a real, tiny PDF — generate with `textutil -convert html` no; use: `python3 -c` unavailable-safe route below)
- Modify: none (production seeding + screenshots)

**Interfaces:**
- Consumes: `add-note`, storage REST, `add-file` (deployed), the env/JWT shell pattern.
- Produces: fixture #8 "UITEST-FIXTURE: public sticky" (`is_public=true`, `supplemental_note='UITEST-FIXTURE: this is the sticky note'` — set via REST PATCH after add-note); fixture #9 "UITEST-FIXTURE: document one" (the committed PDF uploaded + add-file). Closes: sticky-badge + shimmer + document-detail visual gaps AND plan-1's deferred document E2E.

- [ ] **Step 1: Create the PDF asset** — deterministic, no extra tooling:

```bash
cd "$(git rev-parse --show-toplevel)"
mkdir -p ios/fixtures
cat > /tmp/fixture.html <<'EOF'
<html><body><h1>Stash UITEST fixture document</h1>
<p>This is a permanent test document for the Stash iOS suite. It mentions
persimmons, typewriters, and the number forty-two so full-text extraction
has something distinctive to find.</p></body></html>
EOF
# macOS ships cupsfilter; if missing, open the HTML in headless Chrome --print-to-pdf
cupsfilter /tmp/fixture.html > ios/fixtures/uitest-fixture.pdf 2>/dev/null || \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
  --print-to-pdf=ios/fixtures/uitest-fixture.pdf /tmp/fixture.html
python3 - <<'EOF'
import re
data = open('ios/fixtures/uitest-fixture.pdf','rb').read()
assert data[:5] == b'%PDF-', 'not a PDF'
print('PDF OK,', len(data), 'bytes')
EOF
```

- [ ] **Step 2: Seed both fixtures** (env/JWT pattern; idempotency check by title first): add-note "UITEST-FIXTURE: public sticky" with content "permanent public fixture — do not delete" → REST PATCH `{is_public: true, visibility: 'public', supplemental_note: 'UITEST-FIXTURE: this is the sticky note'}`; upload the PDF to `$UID/uitest-fixture.pdf` → add-file `{file_path, mime_type: 'application/pdf', title: 'UITEST-FIXTURE: document one'}`. **Immediately** (within ~30s) launch the app and screenshot the grid showing the document card's processing shimmer (`/tmp/stash-plan2-task10-shimmer.png`) — this is the one chance to catch it live. Then poll REST until `summary` is non-null (≤180s; quick summary then full extraction) and assert `page_body ilike '%persimmons%'`.
- [ ] **Step 3: Visual verification screenshots**: grid card showing the yellow sticky badge on "public sticky" (`-sticky-card.png`); document detail with Summary/Original/Notes tabs populated (`-doc-detail.png`); sticky note visible in the public item's detail (`-sticky-detail.png`). Read + describe each.
- [ ] **Step 4: Commit** — `git add ios/fixtures && git commit -m "test(ios): permanent PDF fixture asset (public-sticky + document fixtures seeded in prod)"`

---

### Task 11: Plan wrap — full verification + outcome section

**Files:**
- Modify: `docs/superpowers/plans/2026-08-11-ios-plan-2-capture.md` (outcome section)

- [ ] **Step 1:** `cd ios/StashKit && swift test` — entire suite green (expect ~40); `swift build 2>&1 | grep -i warning` empty.
- [ ] **Step 2:** Full UI suite (now 7 tests) 2× consecutively — green both runs.
- [ ] **Step 3:** `npm test` from repo root — 17 files / 89 tests still green (no web regression; the worktree-exclude landed on main pre-branch).
- [ ] **Step 4:** Fresh screenshot set: Add tab at launch, View grid (now 9 fixtures incl. sticky badge + document), document detail. Read + describe.
- [ ] **Step 5:** Append a "## Plan 2 outcome" section to this plan doc (date, commits, suite counts, fixture inventory 9 rows, deviations, carries for plan 3 — at minimum: Outbox → App Group migration, share-extension auth via keychain access group, `applyNew` unused-by-design note if still true). Commit — `git add docs/superpowers/plans/2026-08-11-ios-plan-2-capture.md && git commit -m "docs: plan-2 outcome"`

---

## Self-review notes (done at authoring time)

- **Spec coverage (plan-2 slice):** Add tab resident composer + launch flip ✓ (T7), capture routing incl. multi-file rule ✓ (T7 + Global Constraints), photos/camera/files ✓ (T7), Outbox ✓ (T3, wired T7), edit title/description/notes-append ✓ (T5/T6/T8), tags ✓ (T6/T9), public toggle + sticky lifecycle ✓ (T6/T9), delete ✓ (T6/T8). Hygiene list: add-file logging + path sanity ✓ (T1), UUID uploads ✓ (T2), generation token ✓ (T4), pinned column test ✓ (T4), detail-sheet realtime ✓ (T8), badge/shimmer/document fixtures + document E2E ✓ (T10), plist tripwire ✓ (T7 Step 4). Deliberately out (later plans): collections, rich editor, voice, share extension/App Group, Spotlight, id tie-breaker (no bulk insert exists; re-check before any import feature).
- **Type consistency:** `CaptureAPI` signatures identical in T2 (definition), T3 (Outbox.send), T7 (composer); `ItemPatch`/`changedFields` shared T6→T8; `EmbeddingRefresher.schedule(_: Item)` T5→T6; `StubPoster`/fixtures reuse noted with duplication permission; `detectFirstURL` added to MessageRouting.swift in T7's Consumes (public one-liner reusing the existing pattern — implementer adds it there, disclosed).
- **Known risks, accepted:** supabase-swift storage/functions/rpc signatures may drift (checkout-check + disclose, plan-1 precedent); `cupsfilter` may be absent on newer macOS (Chrome headless fallback given); camera untestable on simulator (button hidden when unavailable — UI test asserts only in-app paths that work on sim).
- **Deliberate deviation (plan-1 precedent):** T7-T9 view assembly is exhaustive prose over tested logic; everything else is literal code.

## Plan 2 outcome (2026-08-11)

Shipped on branch `worktree-ios-plan-2`, commits `da5ed5a..5b0c082` (14 commits across 10 tasks, 4 fix rounds — T2/T3/T6/T7 — every task reviewed, fix rounds re-reviewed clean). This task (11) is the plan-wide verification wrap; only this outcome section is committed on top.

**Suite counts (all green, this pass):**
- **StashKit**: 52/52 unit tests, `swift test` and a clean `rm -rf .build && swift build` — zero `warning:` lines.
- **UI suite**: 8 tests (`testCaptureSmoke`, `testDeleteSmoke`, `testDetailSheets`, `testEditSmoke`, `testLibrarySmoke`, `testTagFilterSheetOpens`, `testTagsAndPublicSmoke`, `testWrongPasswordShowsErrorThenCorrectPasswordSignsIn`) — **2/2 consecutive runs fully green, 0 failures each** (run 1: 258.4s; run 2: 236.8s), against the pinned simulator `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` (iPhone 15 Pro, iOS 17.5), `-derivedDataPath DerivedData`, `TEST_RUNNER_*` exported in the invoking shell. The disclosed `testEditSmoke` keyboard-focus flake (1-in-4 in T9's runs) did **not** reproduce in either run here — both executions passed cleanly on the first attempt, so the flake-protocol re-run branch was never needed.
- **Web**: `npm test` (`vitest run`) from repo root — **17 files / 89 tests**, all green; no web regression (`node_modules` needed a fresh `npm ci` in this worktree, otherwise unmodified).
- **Fixture discipline**: `testEditSmoke` (run twice this pass) appended two note paragraphs to `UITEST-FIXTURE: note one`'s content and left it in that state after both runs — restored via REST PATCH back to the byte-exact canonical content (`"UITEST-FIXTURE: stable note for library smoke — do not delete"`), verified against `task-8-report.md`'s documented baseline post-restore. `testTagsAndPublicSmoke` (run twice) left a dangling `plan2-smoke` tag row (`usage_count: 2`, no items attached — `removeTag`'s documented scope, T6/T9) — deleted as a bonus, matching T9's precedent. All disposable `UITEST-CAPTURE*`/`UITEST-DELETE*` rows created by the two full-suite runs and the screenshot-driver run were deleted via REST; final sweep confirms zero remain and all 9 `UITEST-FIXTURE*` rows match their documented canonical state exactly (title/content/description/is_public/supplemental_note/tags all verified via REST GET).

**Fixture inventory (9 permanent `UITEST-FIXTURE*` rows, verified via REST):**

| # | Title | Type | Notable state |
|---|---|---|---|
| 1 | UITEST-FIXTURE: note one | text | tagged `ios-test` |
| 2 | UITEST-FIXTURE: note two | text | — |
| 3 | UITEST-FIXTURE: link one | link | supplemental_note set |
| 4 | UITEST-FIXTURE: link two | link | supplemental_note set |
| 5 | UITEST-FIXTURE: image one | image | — |
| 6 | UITEST-FIXTURE: realtime demo — permanent | image | — |
| 7 | UITEST-FIXTURE: audio one — permanent | audio | transcript in `page_body` |
| 8 | UITEST-FIXTURE: public sticky | text | `is_public=true`, sticky note set |
| 9 | UITEST-FIXTURE: document one | document (PDF) | `summary`/`page_body` populated |

**Screenshots (fresh set, this pass; read and confirmed):**
- `/tmp/stash-plan2-task11-add-launch.png` — Add tab immediately after sign-in, no navigation: empty composer (placeholder "Save a thought, a link, anything…"), no keyboard raised, Save disabled, Add selected (blue) in the tab bar ahead of Ask/View/Settings. Confirms the launch-tab flip and the "keyboard not auto-raised" spec requirement together, live.
- `/tmp/stash-plan2-task11-grid.png` — View grid, unfiltered, "9 items" header. The two newest fixtures (document one, public sticky) sort first and share the top row: `public sticky`'s card shows the yellow rotated sticky badge top-right; `document one`'s card renders its real title/description (not mid-processing) with a plain grey placeholder block standing in for a PDF thumbnail. Confirms both closed plan-1 visual gaps (sticky badge, document card) are visible together in one normal, unfiltered grid state — no special setup needed to see them.
- `/tmp/stash-plan2-task11-doc-detail.png` — `document one`'s detail sheet, Summary tab selected by default, AI-generated description and summary both populated and legible (mentions persimmons/typewriters/forty-two, confirming real extraction, not a placeholder). Original Content/Notes tabs present alongside Summary, matching `contentTabsConfig(for: .document)`.

**Deviations of record:**
- **`CaptureOutcome` contract amendment (T7 fix round 1).** The brief's original enum (`saved(count:)`/`queued(count:)`/`nothingToSave`) had no slot for oversized/upload-failed attachments, which were silently print-dropped — confirmed as real data loss (a lone oversized file produced no error and no save). Reviewer-directed contract change: `saved(count:dropped:)`, `queued(count:dropped:)`, new `.rejected(dropped:)`, `nothingToSave` unchanged. Composer toast copy updated to surface the drop count in every affected case. This is the one place this plan changed a brief-specified public interface after authoring time.
- **`CaptureViewModel` placement in StashKit, not the app target (T7).** The brief's file list showed it under `ios/Stash/Capture/`; it actually lives in `ios/StashKit/Sources/StashKit/CaptureViewModel.swift` because StashKit tests can't see app-target types and the brief's own Step 1 requires the routing logic under `swift test`. Stays UIKit-free via three injectable seams (`downscale`, `upload`, `accessToken`), each defaulting to the real implementation; the app supplies the real `UIImage`-based downscaler at construction. Disclosed at authoring time in `task-7-report.md`, not an improvisation.
- **`TEST_RUNNER_*` env-var guidance, corrected mid-plan (T8→T9).** T8 initially misdiagnosed trailing `KEY=VALUE` `xcodebuild` arguments as build-setting overrides that don't reach the test host's process environment, and worked around it with a PlistBuddy `.xctestrun` patch. Reviewer traced the actual mechanism: **exporting** `TEST_RUNNER_*` in the invoking shell before `xcodebuild test` works directly (plan-1 already relied on this) — the PlistBuddy patch is a fallback, not the primary path. T9 onward (and this task) used the exported-vars form exclusively, with zero PlistBuddy fallback needed. Standing guidance for plan 3+: export first, patch only if that ever regresses.

**Carries into plan 3** (at minimum):
- **Outbox → App Group migration.** `Outbox.defaultDirectory()` currently returns `Application Support/StashOutbox`, app-sandboxed; the share extension needs a shared container. Doc comments in `Outbox.swift`/the plan-1 doc already flag this — no code changes needed here, just the App Group entitlement + directory swap when the extension target exists.
- **Share-extension auth via keychain access group + one-time re-sign-in.** Plan 1 deliberately shipped with supabase-swift's default (app-only) keychain storage (`NO app-group/keychain-group entitlements in this plan (plan 3 adds them; costs one dev re-sign-in, zero real users affected)`). Plan 3 must add the shared keychain access group so the extension can read the host app's session; expect exactly one forced re-sign-in on the dev/test account when that entitlement lands, zero impact to real users (none exist yet).
- **`quick-pdf-summary` server bug: unconditional title overwrite (found in T10, not fixed — server code, out of this plan's scope).** `supabase/functions/quick-pdf-summary/index.ts` overwrites a caller-supplied `title` unconditionally on every document upload (no guard, unlike `add-note`'s `title ? skip : generate`). Surfaced for the first time by T10's document fixture; corrected at the data level only (fixture title REST-patched back). Needs an edge-function fix before any future document-titling feature depends on caller-supplied titles surviving.
- **Eager AI-suggestions fetch on every tag-sheet open (T9, deferred).** `ItemTagsSection`'s `.task { await loadAll() }` calls `suggestTags` (an LLM edge function) on every detail-sheet open, unconditionally — the web gates the equivalent call behind an explicit "editing" toggle. Cost/latency divergence worth reconciling before this ships to real users at volume.
- **Field-autosave failures are invisible to the user (T8, deferred).** `ItemDetailView.saveChangedFields`'s catch branch resets `saveStatus` to `.idle` with no error surface — unlike the delete/notes-append paths, which do propagate failures. A failed title/description save currently looks identical to "nothing changed."
- **`testDetailSheets`'s "Original Content" tab has no content-level assertion.** The test asserts the tab exists for link items but never taps it or checks its text — unlike the audio case, which does assert real transcript text. Worth adding once a stable content fixture (e.g. the T10 document, or link one/two) is chosen as the target.
- **`ItemCardView.stickyBadge` has no accessibility identifier (T10, deferred).** Every other stateful/interactive element in this codebase has one; the sticky badge is currently only verifiable by screenshot or walking the view hierarchy for `Image(systemName: "note.text")`. Add one before any automated coverage depends on it.
- **`testEditSmoke` flake watch.** Failed once in T9's four full-suite runs (`Failed to synthesize event: Neither element nor any descendant has keyboard focus`, on the notes-composer field, immediately after `ItemTagsSection`'s async loads populated the same sheet) — investigated at length, not reproduced on immediate re-run, root cause unproven. Passed cleanly in both of this task's runs (2/2), so still classified as a flake, not a bug, per the standing protocol — but it has now been observed once in ~6 total full-suite executions across T8/T9/T11. Keep watching; escalate to "bug" if it recurs.
- **`ItemStore.applyNew` remains unused-by-design.** Confirmed still true: `grep` for call sites outside `StashKit`'s own tests finds none in the app target. T7's `CaptureComposerView` deliberately does not call it — realtime is the single reconciliation path for a newly-captured item to appear in the View tab (documented in `CaptureViewModel.swift`'s header comment). The method stays public and tested (`ItemStoreTests`) as a load-bearing primitive for a future caller, not dead code to remove.
