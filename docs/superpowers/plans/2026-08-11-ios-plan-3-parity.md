# Stash iOS — Plan 3: Functional parity (Ask tab, voice notes, Settings, gates)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach functional parity with the web app: the Ask tab (streaming Q&A with citations, history, voice input, read-aloud, chat-as-capture), in-app voice notes with offline durability, the Settings tab, and the subscription gates.

**Architecture:** Same thin-client discipline. The Ask tab consumes `chat-with-all-content`'s SSE stream via a tested line-protocol parser; chat history is first-class in the `conversations`/`messages` tables (web parity). Voice notes record locally first and upload through the proven `add-file` audio pipeline — recordings persist on disk until confirmed uploaded, extending the Outbox with local-file entries (this seeds plan 4's attachment-recoverability requirement). Subscription gates port `useSubscription`'s exact boolean semantics.

**Tech Stack:** Swift 5.10 / SwiftUI, StashKit (supabase-swift 2.54.1 pinned), AVFoundation (AVAudioRecorder, AVSpeechSynthesizer), Speech (SFSpeechRecognizer dictation), URLSession `bytes(for:)` SSE.

**Plan sequence (re-sequenced 2026-08-11):** 1 foundation ✅ → 2 capture ✅ → **3 (this): parity** → 4 share extension → 5 widgets/intents → 6 visual/design parity.

## Global Constraints

- Everything from plans 1–2 still binds: min iOS 17, worktree-branch commits (no push), warning-free builds, exact-path `git add`, no credentials ever committed or printed, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`, `swift test` from `ios/StashKit`, sim UDID 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB + `-derivedDataPath DerivedData`, EXPORTED `TEST_RUNNER_*` env vars for UI tests, `--uitest-reset-auth`, fixture discipline (9 permanent `UITEST-FIXTURE:` rows — leave byte-exact; disposable rows use other prefixes and are cleaned), testEditSmoke flake watch protocol (re-run once; escalate on repeat), SourceKit single-file diagnostics are indexer noise.
- SSE wire contract (docs/PLATFORM_API.md:54-76, verified in ChatMole.tsx:247-287): POST `chat-with-all-content` `{message, conversationHistory:[{role,content}]}` with Authorization+apikey headers → `data: {"delta":"…"}` repeatedly, then `data: {"done":true,"sources":[{id,title,type,url}]}`; a `data: {"error":"…"}` line aborts. Lines split on `\n`, `data:` prefix trimmed, JSON after `data:` parsed; non-`data:` lines ignored; trailing partial line buffered.
- History contract (ChatMole.tsx:70-132): oldest conversation for the user or insert `{user_id, title:'Ask Stash'}`; restore last 60 messages (fetch desc, reverse, keep user/assistant roles); persist user msgs immediately, assistant on done with `source_items` = sources' ids (null when empty). Non-fatal failures never block chat.
- Chat-as-capture (moleRouting, already ported as `classifyMessage`): saveURL → `CaptureAPI.addURL`, saveNote → `CaptureAPI.addNote`, rendered as inline "saved" chips (pending → settled title), ask → SSE flow. Gates: capture paths behind `canAddContent`, ask behind `canUseAI`, with the web's toast copy ("Subscription needed" / "Subscribe to add new items." / "AI chat needs an active trial or subscription.").
- Subscription semantics (useSubscription.tsx): `check-subscription` invoke → `{subscribed, onTrial, daysLeft, …}`; if no subscription exists, call `create-trial-subscription` ONCE per app session then re-check; all gates are the same boolean = `loading || onTrial || subscribed` (fail-open while loading — web parity); status re-polled every 30s ONLY while the Settings tab is visible (spec) plus once on app foreground.
- Voice notes: AVAudioRecorder → m4a (AAC 44.1kHz mono 64kbps), mimeType `audio/mp4`; recording saved to `Application Support/StashRecordings/<uid>/<uuid>.m4a` BEFORE any upload; online path = upload + `addFile` + delete local; failure/offline path = Outbox `.file` entry with `local_file_path` (drain uploads the local file first, then addFile, then deletes local). A recording is never destroyed until the server confirms.
- Simulator permissions for tests: `xcrun simctl privacy <UDID> grant microphone it.gostash.stash` and `grant speech-recognition` before voice UI tests; `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` via project.yml (Info.plist TRIPWIRE applies again: diff the committed plist after xcodegen).
- Sign-out MOVES from the View toolbar to Settings; UI tests that used the toolbar sign-out must be updated to navigate via Settings (navigation-preamble edits only; assertions unweakened).
- Ask smoke question must be deterministic-ish: ask about the document fixture ("What do my saved items say about persimmons?") — the fixture's extracted page_body guarantees retrievable content; assert non-empty streamed text + ≥1 source chip.
- Do NOT build: share extension/App Group (plan 4), widgets/intents (plan 5), visual redesign (plan 6), Discover/social, in-app purchase, per-item chat (`chat-with-content` — web has it as a legacy parallel surface; deliberate cut, note in outcome).

---

### Task 1: `SSEClient` — the chat stream protocol, parsed and tested

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Chat/SSEClient.swift`
- Test: `ios/StashKit/Tests/StashKitTests/SSEClientTests.swift`

**Interfaces:**
- Consumes: `StashConfig` (URL + anon key).
- Produces:

```swift
public struct ChatSource: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let type: String?
    public let url: String?
}
public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case done(sources: [ChatSource])
    case serverError(String)
}
public func parseSSELine(_ line: String) -> SSEEvent?   // nil for non-data/blank/unparseable lines
public protocol ChatStreaming: Sendable {
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error>
}
public struct LiveChatStreamer: ChatStreaming { public init() {} }
// URLSession.bytes POST to functions/v1/chat-with-all-content; iterates lines,
// yields parseSSELine results; non-2xx → throws CaptureError.badStatus
```

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import StashKit

final class SSEClientTests: XCTestCase {
    func testDeltaLine() {
        XCTAssertEqual(parseSSELine(#"data: {"delta":"hel"}"#), .delta("hel"))
        XCTAssertEqual(parseSSELine(#"data:{"delta":"lo"}"#), .delta("lo"))   // no space variant
    }
    func testDoneLineWithSources() {
        let line = #"data: {"done":true,"sources":[{"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b","title":"T","type":"document","url":null}]}"#
        guard case .done(let sources)? = parseSSELine(line) else { return XCTFail() }
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].title, "T")
    }
    func testDoneWithEmptySources() {
        XCTAssertEqual(parseSSELine(#"data: {"done":true,"sources":[]}"#), .done(sources: []))
    }
    func testErrorLine() {
        XCTAssertEqual(parseSSELine(#"data: {"error":"boom"}"#), .serverError("boom"))
    }
    func testIgnoredLines() {
        XCTAssertNil(parseSSELine(""))
        XCTAssertNil(parseSSELine(": keepalive"))
        XCTAssertNil(parseSSELine("event: message"))
        XCTAssertNil(parseSSELine("data: not-json"))
    }
}
```

- [ ] **Step 2: RED**, then **Step 3: Implement**

```swift
import Foundation

public struct ChatSource: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let type: String?
    public let url: String?
}

public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case done(sources: [ChatSource])
    case serverError(String)
}

/// One SSE line → event. Mirrors ChatMole.tsx:272-285 exactly: only `data:`
/// lines matter; the payload is JSON; delta / done+sources / error.
public func parseSSELine(_ line: String) -> SSEEvent? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("data:") else { return nil }
    let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    guard let data = payload.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    if let delta = object["delta"] as? String { return .delta(delta) }
    if object["done"] as? Bool == true {
        let sourcesData = (try? JSONSerialization.data(withJSONObject: object["sources"] ?? [])) ?? Data("[]".utf8)
        let sources = (try? JSONDecoder().decode([ChatSource].self, from: sourcesData)) ?? []
        return .done(sources: sources)
    }
    if let message = object["error"] as? String { return .serverError(message) }
    return nil
}

public protocol ChatStreaming: Sendable {
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error>
}

public struct LiveChatStreamer: ChatStreaming {
    public init() {}
    public func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/chat-with-all-content"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["message": message, "conversationHistory": history])
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    for try await line in bytes.lines {
                        if let event = parseSSELine(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: GREEN** (suite 62). **Step 5: Commit** — `git add ios/StashKit && git commit -m "feat(ios): SSE chat stream client with tested line protocol"`

---

### Task 2: `ChatStore` — history, persistence, the send state machine

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Chat/ChatStore.swift`, `ios/StashKit/Sources/StashKit/Chat/ChatHistoryAPI.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ChatStoreTests.swift`

**Interfaces:**
- Consumes: `SSEEvent`/`ChatStreaming` (Task 1), `classifyMessage`, `CaptureAPI`.
- Produces:

```swift
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant, saved }
    public var id: String
    public var role: Role
    public var content: String
    public var sources: [ChatSource]
    public var savedItemTitle: String?    // role == .saved chips
    public var savedKind: String?         // "link" | "note"
    public var isStreaming: Bool
}
public protocol ChatHistoryStoring: Sendable {
    func loadOrCreateConversation(userId: UUID) async throws -> UUID
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage]  // oldest-first
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async
}
public struct SupabaseChatHistory: ChatHistoryStoring { public init() {} }
@MainActor @Observable public final class ChatStore {
    public private(set) var messages: [ChatMessage]
    public private(set) var isStreaming: Bool
    public var errorMessage: String?
    public init(userId: UUID, streamer: ChatStreaming, history: ChatHistoryStoring, capture: CaptureAPI, accessToken: @escaping @Sendable () async throws -> String)
    public func loadHistoryOnce() async               // idempotent
    public func send(_ raw: String) async             // routes via classifyMessage
}
```

`send` semantics (ChatMole parity): saveURL/saveNote → pending `.saved` chip → CaptureAPI → settle title (failure: remove chip, set errorMessage); ask → append `.user` (persist immediately) + streaming `.assistant`, apply deltas, on `.done` set sources + persist assistant with source ids, on `.serverError`/throw remove BOTH the user and assistant messages and set errorMessage (web restores the input text — expose the failed text via `errorRestoredInput: String?`). History for the request = prior user/assistant messages as `[{role,content}]`.

- [ ] **Step 1: Failing tests** (stub streamer + history + poster; no network):

```swift
import XCTest
@testable import StashKit

final class StubStreamer: ChatStreaming, @unchecked Sendable {
    var events: [SSEEvent] = []
    var thrown: Error?
    var lastHistory: [[String: String]] = []
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        lastHistory = history
        return AsyncThrowingStream { c in
            for e in events { c.yield(e) }
            if let thrown { c.finish(throwing: thrown) } else { c.finish() }
        }
    }
}
final class StubHistory: ChatHistoryStoring, @unchecked Sendable {
    var persisted: [(String, String, [UUID]?)] = []
    var seeded: [ChatMessage] = []
    func loadOrCreateConversation(userId: UUID) async throws -> UUID { UUID() }
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] { seeded }
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async {
        persisted.append((role, content, sourceItemIds))
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    func makeStore(streamer: StubStreamer, history: StubHistory = StubHistory()) -> ChatStore {
        ChatStore(userId: UUID(), streamer: streamer, history: history,
                  capture: CaptureAPI(poster: StubPoster()), accessToken: { "jwt" })
    }

    func testAskStreamsAndPersists() async {
        let streamer = StubStreamer()
        let sourceId = UUID()
        streamer.events = [.delta("Hel"), .delta("lo"),
                           .done(sources: [ChatSource(id: sourceId, title: "S", type: "text", url: nil)])]
        let history = StubHistory()
        let store = makeStore(streamer: streamer, history: history)
        await store.loadHistoryOnce()
        await store.send("what is hello?")
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[1].content, "Hello")
        XCTAssertEqual(store.messages[1].sources.first?.id, sourceId)
        XCTAssertFalse(store.messages[1].isStreaming)
        XCTAssertEqual(history.persisted.map(\.0), ["user", "assistant"])
        XCTAssertEqual(history.persisted[1].2, [sourceId])
    }

    func testServerErrorRollsBackAndRestoresInput() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("par"), .serverError("boom")]
        let store = makeStore(streamer: streamer)
        await store.loadHistoryOnce()
        await store.send("failing question")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.errorRestoredInput, "failing question")
        XCTAssertNotNil(store.errorMessage)
    }

    func testHistorySentAsPriorTurnsOnly() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1", sources: [], savedItemTitle: nil, savedKind: nil, isStreaming: false),
                          ChatMessage(id: "2", role: .assistant, content: "a1", sources: [], savedItemTitle: nil, savedKind: nil, isStreaming: false)]
        let store = makeStore(streamer: streamer, history: history)
        await store.loadHistoryOnce()
        await store.send("q2")
        XCTAssertEqual(streamer.lastHistory, [["role": "user", "content": "q1"],
                                              ["role": "assistant", "content": "a1"],
                                              ["role": "user", "content": "q2"]])
    }

    func testSaveNoteRouteMakesChip() async {
        let streamer = StubStreamer()
        let store = makeStore(streamer: streamer)
        await store.loadHistoryOnce()
        await store.send("remember: buy milk")   // StubPoster returns empty Data → capture throws → chip removed + error
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }
}
```

- [ ] **Step 2: RED**, **Step 3: Implement** per the semantics block (SupabaseChatHistory uses the exact web queries: conversations oldest-first limit 1 maybeSingle → insert on nil; messages desc limit 60 reversed, role-filtered; inserts fire-and-forget with error print). **Step 4: GREEN** (suite ~66). **Step 5: Commit** — `git commit -am "feat(ios): ChatStore with streaming state machine + web-parity history (tested)"`

---

### Task 3: `SubscriptionStore` — gates with web-parity semantics

**Files:**
- Create: `ios/StashKit/Sources/StashKit/SubscriptionStore.swift`
- Test: `ios/StashKit/Tests/StashKitTests/SubscriptionStoreTests.swift`

**Interfaces:**
- Consumes: supabase-swift `functions.invoke` (decodable overload — v2.54.1 verified in plan 2).
- Produces:

```swift
public struct SubscriptionStatus: Codable, Equatable, Sendable {
    public var subscribed: Bool
    public var onTrial: Bool
    public var daysLeft: Int?
    enum CodingKeys: String, CodingKey { case subscribed, onTrial = "on_trial", daysLeft = "days_left" }
    // NOTE: verify the exact JSON keys against supabase/functions/check-subscription's
    // response at implementation time (web reads subscribed/onTrial/daysLeft camelCase —
    // check the function source and match EXACTLY; adapt CodingKeys with disclosure).
}
public protocol SubscriptionChecking: Sendable {
    func check() async throws -> SubscriptionStatus
    func createTrial() async throws
}
public struct SupabaseSubscriptionChecker: SubscriptionChecking { public init() {} }
@MainActor @Observable public final class SubscriptionStore {
    public private(set) var status: SubscriptionStatus?
    public private(set) var isLoading: Bool
    public var canAddContent: Bool { isLoading || status?.onTrial == true || status?.subscribed == true }
    public var canUseAI: Bool { canAddContent }   // same boolean on web (useSubscription.tsx:188-192)
    public init(checker: SubscriptionChecking)
    public func refresh() async     // on nil-subscription: createTrial() once per store lifetime, then re-check (web self-heal)
}
```

- [ ] **Step 1: Failing tests** — stub checker: (a) active sub → canAddContent true, not loading; (b) nothing → createTrial called EXACTLY once then re-check picks up trial; (c) check throws → fail-open (isLoading stays false, canAddContent FALSE? — NO: web fail-open means gates true only while loading; a completed failed check leaves gates closed? Web: loading||trialing||active — an errored check sets loading false and no status → gates false, but SubscriptionProvider retries. Port exactly: error → status nil, isLoading false, gates false, `lastError` set); (d) second refresh never re-calls createTrial.

```swift
final class StubChecker: SubscriptionChecking, @unchecked Sendable {
    var results: [Result<SubscriptionStatus, Error>] = []
    var trialCalls = 0
    func check() async throws -> SubscriptionStatus {
        guard !results.isEmpty else { throw CaptureError.badStatus(500) }
        return try results.removeFirst().get()
    }
    func createTrial() async throws { trialCalls += 1 }
}

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    func testActiveSubscriptionOpensGates() async {
        let checker = StubChecker()
        checker.results = [.success(SubscriptionStatus(subscribed: true, onTrial: false, daysLeft: nil))]
        let store = SubscriptionStore(checker: checker)
        await store.refresh()
        XCTAssertTrue(store.canAddContent)
        XCTAssertEqual(checker.trialCalls, 0)
    }
    func testNoSubscriptionSelfHealsOnce() async {
        let checker = StubChecker()
        let none = SubscriptionStatus(subscribed: false, onTrial: false, daysLeft: nil)
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 14)
        checker.results = [.success(none), .success(trial), .success(none)]
        let store = SubscriptionStore(checker: checker)
        await store.refresh()
        XCTAssertEqual(checker.trialCalls, 1)
        XCTAssertTrue(store.canAddContent)          // trial picked up on re-check
        await store.refresh()                        // later refresh sees `none` again…
        XCTAssertEqual(checker.trialCalls, 1)        // …but never re-creates a trial
    }
    func testLoadingFailsOpenThenErrorClosesGates() async {
        let checker = StubChecker()                  // empty results → throw
        let store = SubscriptionStore(checker: checker)
        XCTAssertTrue(store.canAddContent)           // pre-first-refresh: loading state fail-open
        await store.refresh()
        XCTAssertFalse(store.canAddContent)
        XCTAssertNotNil(store.lastError)
    }
}
```

(`isLoading` starts `true` — matching the web's initial loading fail-open — and flips false after the first refresh completes either way. Add `lastError: String?`.)

- [ ] **Step 2: RED**, **Step 3: Implement** (checker invokes `check-subscription` / `create-trial-subscription`; verify response keys against the edge function source FIRST and disclose the actual shape). **Step 4: GREEN** (~69). **Step 5: Commit** — `git commit -am "feat(ios): subscription gates with web-parity self-heal (tested)"`

---

### Task 4: Voice recording durability — `RecordingStore` + Outbox local-file entries

**Files:**
- Create: `ios/StashKit/Sources/StashKit/RecordingStore.swift`
- Modify: `ios/StashKit/Sources/StashKit/Outbox.swift` (drain handles `local_file_path`)
- Test: `ios/StashKit/Tests/StashKitTests/RecordingStoreTests.swift`, `ios/StashKit/Tests/StashKitTests/OutboxTests.swift` (add one case)

**Interfaces:**
- Consumes: `Outbox`, `CaptureAPI`, `makeUploadPath`, `uploadToStorage`.
- Produces:

```swift
public struct RecordingStore: Sendable {
    public init(userId: UUID, directory: URL? = nil)   // default Application Support/StashRecordings/<uid-lowercased>
    public var directory: URL
    public func newRecordingURL() -> URL               // <uuid>.m4a inside directory
    public func pendingRecordings() -> [URL]
    public func discard(_ url: URL)
}
/// Outbox change: a `.file` entry whose payload contains "local_file_path"
/// uploads that local file (upload closure injectable for tests) to a fresh
/// makeUploadPath BEFORE calling addFile, then deletes the local file on
/// success. Existing `.file` entries without the key behave as before.
/// Outbox.drain gains: `drain(api:accessToken:userId:upload:)` where
/// upload: @Sendable (Data, String, String) async throws -> Void = uploadToStorage
/// (data, path, contentType). userId is needed for makeUploadPath.
```

Recording settings constant (used by the app's recorder in Task 6): `public let voiceRecordingSettings: [String: Any]` = AAC (`kAudioFormatMPEG4AAC`), 44100 Hz, 1 channel, 64k bitrate — defined here so it's shared and documented.

- [ ] **Step 1: Failing tests** — RecordingStore: per-user directory shape (two uids → distinct dirs), newRecordingURL uniqueness + .m4a suffix, pending lists only files, discard removes. Outbox: enqueue `.file` with `local_file_path` pointing at a tmp file containing known bytes + `mime_type: "audio/mp4"`; drain with a recording `upload` stub → asserts upload received the file's bytes + a path shaped `<uid>/<uuid>.m4a`, addFile POST followed with that path, local file deleted; failure case: upload throws → entry retained, local file NOT deleted, attempts+1.
- [ ] **Step 2: RED**, **Step 3: Implement** (drain change is additive: read `local_file_path`; if present and file missing → treat as permanent failure: drop the entry with a print — the recording is gone, retrying is pointless; disclose this rule in a comment). **Step 4: GREEN** (~74). **Step 5: Commit** — `git commit -am "feat(ios): durable voice recordings — RecordingStore + Outbox local-file upload (tested)"`

---

### Task 5: Ask tab UI — streaming chat with citations, capture chips, dictation, read-aloud

**Files:**
- Create: `ios/Stash/Ask/AskView.swift`, `ios/Stash/Ask/ChatBubble.swift`, `ios/Stash/Ask/ChatComposerBar.swift`, `ios/Stash/Ask/DictationController.swift`
- Modify: `ios/Stash/MainTabView.swift` (Ask placeholder → AskView), `ios/project.yml` (mic + speech usage strings), `ios/StashUITests/StashUITests.swift`

**Interfaces:**
- Consumes: `ChatStore` (Task 2) with `LiveChatStreamer`/`SupabaseChatHistory`/`CaptureAPI()`, `SubscriptionStore` (Task 3 — threaded from StashApp as environment), `SupabaseItemsFetcher.fetchDetail` + `ItemDetailView` (citation taps open the existing detail sheet, read-only is fine), AVSpeechSynthesizer.
- Produces: the Ask tab. Prose spec (plan-1/2 precedent; logic all tested upstream):
  - Thread: scrolling `ChatMessage` list; user bubbles trailing/tinted, assistant leading with streaming cursor while `isStreaming`; `.saved` chips rendered as compact cards (icon by kind, title, "Saving…" shimmer until settled); auto-scroll to bottom on append/delta (throttle: scroll on message-count change and once per ~0.3s during streaming).
  - Assistant bubbles: text via `Text` (plain — markdown rendering deferred to plan 6, note it); sources row of chips under the bubble (`source.title`, tap → sheet with ItemDetailView via fetchDetail; loading state).
  - Read-aloud: speaker button on assistant bubbles → AVSpeechSynthesizer utterance of the content; tap again stops. One shared synthesizer in AskView.
  - Thumbs: up/down buttons on assistant bubbles → insert into `chat_feedback` (check the table's columns via the web's usage in ChatMole.tsx thumbs handler — read it at implementation time; fire-and-forget, filled state after tap).
  - Composer bar: TextField + mic + send. Routing = `store.send` (chips/gates handled inside). Placeholder teaches routing: "Ask, or paste a link / 'remember:' to save". Gate: when `!subscription.canUseAI` and the classified kind is ask → inline "AI chat needs an active trial or subscription." error line instead of sending (web toast copy); capture kinds gate on `canAddContent` with "Subscribe to add new items.".
  - `errorMessage`/`errorRestoredInput`: banner + restore the input text.
  - Dictation (`DictationController`): SFSpeechRecognizer + AVAudioEngine live transcription; mic button toggles; interim text fills the TextField live; on stop, final text stays in the field for user confirmation (deviation from web's auto-send — DISCLOSED intentional: mobile mis-dictation is common; note in report + outcome); hidden when `SFSpeechRecognizer` unauthorized/unavailable after request.
  - Identifiers: `ask.thread`, `ask.input`, `ask.send`, `ask.mic`, `ask.bubble.<index>`, `ask.sources.<index>`.
- [ ] **Step 1: Implement** (project.yml gains `NSMicrophoneUsageDescription` "Stash uses the microphone for voice notes and dictation." + `NSSpeechRecognitionUsageDescription` "Stash transcribes your speech on-device to fill the composer." — plist TRIPWIRE check after xcodegen).
- [ ] **Step 2: UI test `testAskSmoke`**: sim permission grants first (`simctl privacy … grant microphone/speech-recognition` — grants are best-effort pre-steps; the test itself doesn't exercise dictation); sign in → Ask tab → type "What do my saved items say about persimmons?" → send → assert a non-empty assistant bubble appears (wait ≤30s for stream completion — poll for the bubble's label to stabilize) + ≥1 sources chip exists → tap the source chip → assert detail sheet opens (the document fixture) → dismiss. Full UI suite ×2 green (flake protocol).
- [ ] **Step 3: Screenshots**: streamed answer with sources + the composer with dictation active if grantable (`/tmp/stash-plan3-task5-ask.png`, `-dictate.png` best-effort). Read + describe.
- [ ] **Step 4: Commit** — `git add ios && git commit -m "feat(ios): Ask tab — streaming chat, citations, capture chips, dictation, read-aloud"`

---

### Task 6: Voice notes — record, save, survive offline

**Files:**
- Create: `ios/Stash/Capture/VoiceRecorderSheet.swift`, `ios/Stash/Capture/AudioRecorderController.swift`
- Modify: `ios/Stash/Capture/CaptureComposerView.swift` (mic button → sheet), `ios/StashKit/Sources/StashKit/CaptureViewModel.swift` (voice-note submit path), `ios/StashKit/Tests/StashKitTests/CaptureViewModelTests.swift`, `ios/StashUITests/StashUITests.swift`

**Interfaces:**
- Consumes: `RecordingStore` + `voiceRecordingSettings` + Outbox local-file drain (Task 4), `CaptureAPI.addFile`, `uploadToStorage`, `makeUploadPath`.
- Produces:
  - `AudioRecorderController` (app target, `@Observable`): AVAudioSession record category, AVAudioRecorder into `recordingStore.newRecordingURL()` with `voiceRecordingSettings`, `elapsed: TimeInterval` timer, `averagePower` for a simple level meter, start/stop/cancel (cancel deletes the file).
  - `CaptureViewModel.submitVoiceNote(fileURL: URL) async -> CaptureOutcome`: reads the file, uploads (`makeUploadPath(userId:, "m4a")`, contentType `audio/mp4`), `addFile(mimeType: "audio/mp4", content: nil)`; on success deletes the local file and returns `.saved(count: 1, dropped: 0)`; on ANY failure enqueues an Outbox `.file` entry with `local_file_path` (keeping the file!) and returns `.queued(count: 1, dropped: 0)`. Tests (2, with StubPoster + tmp dirs): success path deletes local + correct payload; failure path retains file + outbox entry references it.
  - `VoiceRecorderSheet`: red record button → recording state (timer + level bar + Stop + Cancel); stop → preview state (duration, Save / Re-record / Cancel); Save → `submitVoiceNote` → toast via the existing capture toast pipeline; mic-permission denied → inline explainer with Settings link.
  - Composer: mic button (identifier `capture.voice`) opens the sheet; hidden only if mic hardware truly absent (never on permission — the sheet handles that).
- [ ] **Step 1: TDD the two `submitVoiceNote` tests** (RED → GREEN; suite ~76).
- [ ] **Step 2: Implement controller + sheet + wiring.**
- [ ] **Step 3: UI test `testVoiceNoteSmoke`**: `simctl privacy grant microphone` first; Add tab → `capture.voice` → record ~2s (sim records host-mic silence — fine) → Stop → Save → success toast → View tab → newest card is type audio (poll ≤15s; realtime) — then REST-poll the item until `description` non-null (Whisper on silence → "no speech" description path proven in plan 1) and REST-DELETE the disposable item + storage object. Full UI suite ×2 green.
- [ ] **Step 4: Screenshots**: recording state + preview state. Read + describe.
- [ ] **Step 5: Commit** — `git add ios && git commit -m "feat(ios): voice notes — durable recording through the add-file pipeline"`

---

### Task 7: Settings tab + gates wired everywhere

**Files:**
- Create: `ios/Stash/Settings/SettingsView.swift`, `ios/Stash/Settings/AccountSection.swift`, `ios/Stash/Settings/PhoneSection.swift`, `ios/Stash/Settings/TagsSection.swift`, `ios/Stash/Settings/SubscriptionSection.swift`
- Modify: `ios/Stash/MainTabView.swift` (Settings placeholder → SettingsView), `ios/Stash/StashApp.swift` (SubscriptionStore in environment + refresh on foreground), `ios/Stash/Library/LibraryToolbarContent.swift` (REMOVE sign-out — it moves), `ios/Stash/Capture/CaptureComposerView.swift` + `ios/StashKit/Sources/StashKit/CaptureViewModel.swift` (canAddContent gate), `ios/StashUITests/StashUITests.swift`
- Test: none new in StashKit (gate logic tested in Task 3; sections are thin reads)

**Interfaces:**
- Consumes: `SubscriptionStore` (environment), `SessionStore.signOut`, `fetchTags` + tag delete (`from("tags").delete().eq("id",…)` — mirror TagsSettings.tsx delete-only, no rename/merge), `user_phone_numbers` reads + insert (mirror usePhoneNumber.ts INCLUDING its auto-verify parity — `verified: true` client-side; add the code comment "web-parity gap: no OTP, see known-issues"), profiles read for username, `check-subscription` via the store.
- Produces (prose): `List`-style Settings — **Account** (email from session, username + public feed URL `https://gostash.it/feed/<username>` with copy button); **Phone numbers** (list, add with E.164-ish normalization mirroring the web, max 3, delete); **Tags** (list with usage counts, swipe-delete with confirm — deletes cascade item_tags per web); **Subscription** (status line: "Active" / "Trial — N days left" / "Expired", ProgressView while loading, "Manage on gostash.it" external link, refresh on section appear + 30s timer while visible); **Sign out** (red, confirm dialog); footer: legal links (gostash.it/privacy, /terms), app version from bundle. Identifiers: `settings.signout`, `settings.feedurl.copy`, etc.
- Gates wiring: composer Save disabled + inline "Subscribe to add new items." when `!canAddContent` (fail-open semantics mean this only bites post-load); Ask gating already in Task 5.
- [ ] **Step 1: Implement.** **Step 2: Update UI tests** — sign-out navigation preambles switch to Settings (`settings.signout`); add `testSettingsSmoke`: settings shows the account email + subscription line non-empty; sign out via Settings returns to SignInView. Full UI suite ×2 green.
- [ ] **Step 3: Screenshot** Settings. **Step 4: Commit** — `git add ios && git commit -m "feat(ios): Settings tab + subscription gates; sign-out relocated"`

---

### Task 8: Plan wrap

**Files:**
- Modify: `docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md` (outcome section)

- [ ] **Step 1:** StashKit full suite green (expect ~76) + warning-free; app build clean.
- [ ] **Step 2:** Full UI suite (11-ish tests) ×2 green (flake protocol; report counts).
- [ ] **Step 3:** `npm test` 17/89 green.
- [ ] **Step 4:** Screenshot set: all four tabs (Add, Ask with a streamed answer, View grid, Settings). Read + describe.
- [ ] **Step 5:** Outcome section: date, commits, suite counts, parity statement (what web features now exist on iOS; named cuts: per-item chat, Discover/social, markdown rendering in bubbles → plan 6), deviations of record, plan-4 handoff (share extension requirements from plan-2's named list + RecordingStore/local-file-outbox as the attachment-durability foundation + camera-photo recoverability requirement). Commit.

---

## Self-review notes (done at authoring time)

- **Spec coverage (phase-3 slice):** Ask tab (stream/citations/history/voice-in/read-aloud/chat-as-capture/⌘K-equivalent omitted — no keyboard shortcut convention on iOS, noted) ✓ T1/T2/T5; voice notes ✓ T4/T6; Settings ✓ T7; gates (spec: "client-side same as web, fail-open while loading") ✓ T3/T5/T7. Sign-out relocation per spec's Settings description ✓ T7.
- **Type consistency:** `ChatSource` defined T1, consumed T2/T5; `ChatStore` init signature T2 = T5 usage; `SubscriptionStore` T3 = T5/T7; `RecordingStore`/`voiceRecordingSettings` T4 = T6; `submitVoiceNote` outcome cases match plan-2's amended `CaptureOutcome`.
- **Deliberate deviations (disclosed in-plan):** dictation fills the field instead of auto-sending (mobile correction UX); assistant markdown deferred to plan 6; per-item chat cut.
- **Known risks, accepted:** check-subscription response key shapes verified at implementation time (T3 note); SFSpeechRecognizer entitlements/simulator behavior can be finicky — dictation is add-on UX, its failure modes never block typing; Ask smoke costs one real model call per run (~4 runs total — negligible).
- **Plan-1/2 precedent carried:** UI tasks prose-specified over tested logic; every task ends in a commit; TRIPWIRE on plist changes.

## Plan 3 outcome (2026-08-11)

Shipped on branch `worktree-ios-plan-3`, commits `759a06a..dc9f52f` (13 commits across Tasks 1–7, 6 fix rounds — T2/T3/T4/T5/T6/T7, one each — every task reviewed, fix rounds re-reviewed clean). This task (8) is the plan-wide verification wrap: three controller-directed test hardenings the review ledger accumulated landed first, in one further commit on top of `dc9f52f`, then full verification ran against the hardened suite.

**Controller-directed hardenings (landed before verification, this task):**
1. **`testEditSmoke` restore-first.** This exact fixture-corruption failure mode — a crashed run dying between the in-app edit and the test's own end-of-test restore, leaving `UITEST-FIXTURE: note one`'s TITLE itself mutated (`"... (edited <epoch>)"`) plus a stale appended notes paragraph — had hit twice (the Task 5 escalation; task-6-report.md's "discovered + repaired in passing"). Added a REST pre-flight (`restoreNoteOneFixtureToCanonical`, `StashUITests.swift`): a password-grant token for the test account, then a PATCH matched by a LIKE *prefix* (`UITEST-FIXTURE: note one*`), not an exact title match — specifically so it still finds and repairs the row when a prior crash left the title mutated, which an exact match would silently miss. Runs before any edit; the end-of-test restore stays too, as a belt. Verified live (read-only) against production before wiring in: the prefix matches "note one" only, never "note two." (Converting this test to `async throws` for the REST call's `await` made every `XCUIElement` call in it read as a possible off-main-actor access under Swift's concurrency checker — ~30 new warnings absent from the synchronous original; marked the test `@MainActor`, which is simply explicit about what was already true — XCTest runs test methods on the main thread in practice — rather than a workaround. Verified 0 warnings via a full `rm -rf DerivedData` clean rebuild.)
2. **`testAskSmoke` RAG-variance retry.** "Real streamed text but zero source chips" hit twice across T5–T7's runs — confirmed as the SSE `.done` event genuinely carrying an empty `sources` array some fraction of the time (server-side retrieval variance), not an XCUITest race. Refactored the send-and-wait-for-stable-reply logic into a shared nested helper and added one in-test retry: if the first attempt's bubble has real text but no source chip within 10s, the identical question is asked again as a fresh message (a new bubble pair) and re-asserted — still a genuine, reportable failure if both attempts come back sourceless. Neither of this task's two full-suite runs needed the retry to fire (both `testAskSmoke` attempts succeeded on the first try, ~23–26s each).
3. **Production debris sweep.** Deleted the 5 stray `UITEST-CAPTURE` rows (predating this session, flagged by Tasks 6/7 for T8) and the `plan2-smoke` tag row (`usage_count: 10`, zero `item_tags` references verified first). All 9 `UITEST-FIXTURE*` rows confirmed byte-exact canonical immediately after. (Both artifact types predictably reappeared in small numbers from this task's own two verification runs — `testCaptureSmoke` and `testTagsAndPublicSmoke` exercising real, already-documented, pre-existing behavior, not a regression — and were swept again after each run; the fixture inventory below is the post-everything baseline.)

**Suite counts (all green, this pass):**
- **StashKit**: 85/85 unit tests, `swift test` and a clean `rm -rf .build/*/debug && swift build --build-tests` — zero `warning:` lines. Unchanged from Task 7 (this task added no StashKit code — only `StashUITests.swift`).
- **App + UI-test target build**: `rm -rf DerivedData && xcodebuild build-for-testing` clean, 0 warnings.
- **UI suite**: 11 tests — **2/2 consecutive full-suite runs fully green, 0 failures each** (run 1: 308.3s; run 2: 315.2s), against the pinned simulator `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` (iPhone 15 Pro, iOS 17.5), exported `TEST_RUNNER_*` env vars, `-derivedDataPath DerivedData`. Both historically-flaky tests passed clean on **every** attempt across both runs: `testEditSmoke` ran the restore-first pre-flight both times with negligible added cost (41.9s / 42.3s, in line with its pre-hardening ~41s baseline); `testAskSmoke` succeeded on its first attempt both times (25.7s / 23.6s — the in-test retry never had to fire). Flake protocol was available but unused — no third run was needed.

  Run 2 per-test timings: testAskSmoke 23.6s, testCaptureSmoke 19.0s, testDeleteSmoke 17.3s, testDetailSheets 65.3s, testEditSmoke 42.3s, testLibrarySmoke 37.6s, testSettingsSmoke 18.9s, testTagFilterSheetOpens 13.7s, testTagsAndPublicSmoke 37.6s, testVoiceNoteSmoke 29.4s, testWrongPasswordShowsErrorThenCorrectPasswordSignsIn 10.5s.
- **Web**: `npm test` (`vitest run`) from repo root — **17 files / 89 tests**, all green (`npm ci` run fresh in this worktree first — no `node_modules` yet).

**Fixture inventory (9 permanent `UITEST-FIXTURE*` rows, re-verified via REST after both suite runs — byte-exact canonical, unchanged in substance from plan 2):**

| # | Title | Type | Notable state |
|---|---|---|---|
| 1 | UITEST-FIXTURE: note one | text | tagged `ios-test`; content restored byte-exact after each run's `testEditSmoke` append |
| 2 | UITEST-FIXTURE: note two | text | — |
| 3 | UITEST-FIXTURE: link one | link | supplemental_note set |
| 4 | UITEST-FIXTURE: link two | link | supplemental_note set |
| 5 | UITEST-FIXTURE: image one | image | — |
| 6 | UITEST-FIXTURE: realtime demo — permanent | image | — |
| 7 | UITEST-FIXTURE: audio one — permanent | audio | transcript in `page_body` |
| 8 | UITEST-FIXTURE: public sticky | text | `is_public=true`, sticky note set |
| 9 | UITEST-FIXTURE: document one | document (PDF) | `summary`/`page_body` populated |

Production debris swept clean: 0 stray `UITEST-CAPTURE*` rows, 0 `plan2-smoke` tag row remain (final REST verification, after the last test run of this task).

**Screenshots (fresh set, this pass; read and confirmed):**
- `/tmp/stash-plan3-task8-add.png` — Add tab immediately after sign-in: empty composer (placeholder "Save a thought, a link, anything…"), no keyboard raised, four attachment buttons (photo library, camera, file, mic) plus the private/public visibility toggle showing its "lock" (private-by-default) glyph, Add selected in the tab bar ahead of Ask/View/Settings.
- `/tmp/stash-plan3-task8-ask.png` — Ask tab mid-conversation: the persimmons smoke question (blue user bubble) and its streamed assistant answer, two source chips visible under the reply (`UITEST-FIXTURE: document one` plus a partially-visible second chip), speaker/thumbs-up/thumbs-down row beneath, composer with keyboard raised.
- `/tmp/stash-plan3-task8-grid.png` — View grid, unfiltered, **"9 items"** header (re-captured via a solo `testLibrarySmoke` run after final cleanup, so this is the clean fixture-only state, not a run-in-progress snapshot with a disposable row still present). `document one` and `public sticky` (yellow sticky badge) sort first, followed by `audio one` and `realtime demo`'s green placeholder image.
- `/tmp/stash-plan3-task8-settings.png` — Settings: Account (email `will+uitest@dzierson.com`, username `uitest`, feed URL with copy icon), Phone Numbers (empty, Add correctly disabled for blank input), Tags (**both** `ios-test` (1) — the one real permanent tag — **and** `plan2-smoke` (1) are visible; the latter was a cross-run carryover, not evidence of within-run ordering — see the correction note below), Subscription ("Trial — 5 days left", blue "Manage on gostash.it" link).

  **Caption correction (post-review):** this caption originally, incorrectly, claimed only
  `ios-test` was present, reasoning that `testSettingsSmoke` ran before `testTagsAndPublicSmoke`
  "in the same suite." That premise was right but insufficient — verified via both runs' raw
  logs (`Test Case ... started` timestamps, not assumption): execution order in every run was
  alphabetical, so run 2's `testSettingsSmoke` (started at log line 1206) genuinely did run
  before run 2's own `testTagsAndPublicSmoke` (line 1365). The tag visible in the frame is real,
  and the true sequence is a CROSS-run carryover the caption didn't account for: the initial
  production debris sweep (hardening 3, before either verification run) deleted the pre-existing
  `plan2-smoke` row (`usage_count: 10`); run 1's own `testTagsAndPublicSmoke` then re-created it
  fresh (`usage_count: 1`, confirmed via REST immediately after run 1); that row was deliberately
  left in place between runs (tag cleanup was explicitly deferred to "the final post-run2
  cleanup pass," not repeated after every run) — so it still existed, unchanged at
  `usage_count: 1`, when run 2's `testSettingsSmoke` fired this checkpoint partway through run 2.
  Run 2's own `testTagsAndPublicSmoke` later reused the same row (`usage_count: 1→2`,
  same id `e9f4b207-…`, confirmed identical across both the post-run-1 and pre-deletion REST
  reads). It was deleted for good in this task's final cleanup pass (zero `item_tags`
  references reverified first) — the "Production debris swept clean" line above and the
  fixture-inventory section already reflect that true, independently-reverified end state; only
  this screenshot's caption was wrong about the transient mid-run frame.

## PARITY STATEMENT

**What web features now exist on iOS, after plans 1–3:** capture (notes/links/photos/camera/files/voice, offline-durable via the Outbox), a library grid with search/type-filter/tag-filter, item detail sheets with type-specific tabs (Summary/Original Content/Notes/Transcript) and inline field editing, notes-append, delete, tags (add/remove with usage counts) and public sharing with a sticky note, streaming Ask/chat over the whole stash with citations, persisted chat history, voice-in (dictation) and read-aloud, chat-as-capture (save a link or note straight from the Ask composer), a Settings tab (account/feed URL, phone numbers for SMS/WhatsApp capture, tag management, subscription status), and client-side subscription gates matching the web's exact fail-open-while-loading semantics.

**Named cuts (deliberate, disclosed at authoring time):**
- **Per-item chat** (`chat-with-content`) — the web's parallel/legacy per-item chat surface; the Ask tab's whole-stash chat (`chat-with-all-content`) is the only chat surface on iOS.
- **Discover/social** — no feed browsing, following, or social surface.
- **Markdown rendering in assistant chat bubbles** — plain `Text`, not a markdown renderer; deferred to plan 6 (visual/design parity).
- **⌘K / command-palette equivalent** — not really a cut, N/A: no keyboard-shortcut convention exists on iOS.
- **Collections** — cut in plan 2, still true.
- **In-app subscription management** — Settings links out to gostash.it rather than embedding a purchase flow.

**Deviations of record:**
1. **Dictation confirm-first (Task 5).** The web's `useVoiceInput` auto-sends the final transcript the instant recognition ends; `DictationController` instead leaves it in the composer field for the user to read, edit, and send explicitly. Disclosed mobile-UX correction: background noise, a dropped word, or an early cutoff is common enough on-device that auto-sending risks firing a garbled question the user never meant to ask.
2. **Foreground-refresh preemption (Task 5 → Task 7).** `StashApp.swift`'s `SubscriptionStore` environment injection plus its launch- and scenePhase-foreground refresh wiring — filed under Task 7's brief — actually landed in Task 5's commit instead, because the Ask tab's gates needed a live `SubscriptionStore` immediately and Task 5 didn't want to block on Task 7. Task 7's own report explicitly re-verified this wiring rather than re-implementing it (confirmed no double-wire); its only addition on top was `SubscriptionSection`'s own while-visible 30s poll.
3. **`user_profiles` correction (Task 7).** The brief's prose said "profiles read for username"; the web's actual `useProfile.ts` queries `user_profiles` (no `profiles` table exists). `AccountSection` was implemented against the real table, correcting the brief's paraphrase — the same class of brief-vs-source mismatch Task 3 also caught and corrected for `check-subscription`'s response keys.

**Plan-4 handoff:**

1. **Share-extension named requirements, carried forward from plan-2's outcome — all 6 still open, none actioned by plan 3** (plan 3's own Global Constraints explicitly excluded the share extension/App Group):
   - **Offline camera capture recoverability** — still open; confirmed by re-reading `CaptureViewModel.swift`: `CaptureAttachment.data` (camera/file-picker bytes) is held only in memory until `submit()`; an upload failure there is classified an `UnqueueableFailure` and the bytes are gone (the composer already cleared before attempting). See item 2 below for the now-proven fix pattern.
   - **Un-share vs sticky-debounce race** — still open; `Debouncer` (`Debouncer.swift`) still has no externally-callable `cancel()`, only its own internal pending-task replacement inside `call()`. `testTagsAndPublicSmoke` still dodges this with an explicit `sleep(2)` before toggling public off.
   - **Outbox attempts cap + dead-letter** — still open; `Outbox.drain` (`Outbox.swift`) increments `attempts` on every failure but never checks it against a cap — a permanently-failing entry (e.g. a 403) retries forever.
   - **Extension memory budget** — still open; the composer's attachment paths (`CaptureComposerView.swift`, `CaptureViewModel.swift`) still read whole-file `Data` eagerly — a share extension's ~120MB memory cap needs streamed/bounded reads before this pipeline is reused there.
   - **App Group Outbox migration** — still open; `Outbox.defaultDirectory(userId:)` still resolves under the app-sandboxed Application Support directory; its own doc comment already flags both the migration and the per-user-scoping invariant that migration must preserve.
   - **Server fix: `quick-pdf-summary` title overwrite** — still open, unchanged; `supabase/functions/quick-pdf-summary/index.ts`'s update-on-upload still sets `title` unconditionally (guarded only by `page_body IS NULL`, not by "was a title caller-supplied"). Out of any client plan's scope — needs an edge-function change.
2. **`RecordingStore` + local-file `Outbox` entries as the attachment-durability foundation.** Task 4's local-file `Outbox` extension is the proven, already-shipped pattern for closing the camera-capture-recoverability requirement above: voice notes write to local disk *before* any network attempt (`RecordingStore.newRecordingURL()`), and the Outbox only ever deletes the local copy once a checkpoint confirms the transition to an uploaded `file_path` is durable on disk (`Outbox.swift`'s persist-before-delete ordering, fixed in Task 4's own review round). `submitVoiceNote`'s doc comment says this explicitly: unlike `submit()`'s in-memory attachment path, "ANY failure here... is always safe... to hand to the Outbox." Generalizing `RecordingStore` (or adding a sibling) so camera photos and file-picker attachments stage through the same local-first write, instead of living only in `CaptureAttachment.data`, is the direct way to close that requirement without inventing a second durability mechanism.
   - **Startup reconciliation sweep for orphaned pre-Save recordings** — `RecordingStore.pendingRecordings()` is currently dead API; a force-quit between Stop and Save orphans the `.m4a` silently until this sweeps them into the Outbox (or prompts).
3. **`DictationController` session-rollback shape (found in plan 3, deliberately left unfixed).** `DictationController.start()` (`ios/Stash/Ask/DictationController.swift:67-102`) calls `session.setActive(true, ...)` (line 74), then if `audioEngine.start()` subsequently throws (line 97), returns early (lines 99-101) without ever deactivating the session — the identical shape `AudioRecorderController`'s own Task 6 review Finding 2 fixed for the voice-recorder's audio session. Left untouched across Tasks 5/6 on explicit review instruction to avoid scope creep in the Ask tab; still open, still the same shape.
4. **Task 4's drain-drop counting gap.** `Outbox.drain` (`Outbox.swift`, the local-recording-missing branch around lines 84-94, vs. the `-> Int` return built from `sent` alone) drops a permanently-unrecoverable entry with a `print` and no counter — callers have no way to learn how many entries a given drain permanently lost. Flagged since Task 4's own review as a plan-level gap, never folded into any later task's scope. A share-extension-fed Outbox makes this more visible: surfacing "N recordings could not be recovered" to the user needs `drain` to return (or callback) a `dropped` count alongside `sent`.
5. **Auto-finalize dictation edge.** `DictationController`'s `recognitionTask` result handler (`DictationController.swift:106-116`) sets `transcript` and calls `stop()` (which flips `isListening` false) synchronously, in the same MainActor step, when a result is final. `AskView.onChange(of: dictation.transcript)` only merges into the composer's `input` while `dictation.isListening` is true — and since SwiftUI's `onChange` fires asynchronously relative to the property mutation that triggered it, a short utterance whose very first recognition callback is already `isFinal` can have both the transcript update and the `isListening` flip land before `onChange` ever observes the intermediate `true` state, silently dropping the entire utterance. Flagged since Task 5 as a low-priority follow-up: flush the final transcript independent of the `isListening` flip.
6. **Read-aloud/dictation audio-session hygiene bundle (plan 6).** Group item 3's still-open `DictationController` session-rollback gap with any other `AVSpeechSynthesizer`/`AVAudioSession` lifecycle cleanup the final review turned up for read-aloud and dictation, and land them as one bundled pass rather than scattered fixes.
7. **Voice-notes-inherit-public-toggle visibility (plan 4 or 6).** `submitVoiceNote` already threads the composer's `isPublic` through to `addFile` correctly (`CaptureViewModel.swift:168`), but `VoiceRecorderSheet` never surfaces that public/private state to the user while recording or previewing — needs a visible indicator.

**Post-review addendum (parked residual, 2026-08-12):** `SubscriptionStore.reset()` closes the unconditional cross-account bleed, but an in-flight `refresh()` started before sign-out has no generation guard and can clobber the next account's state when it resolves (narrow race: same-device account switch inside a ~1s network window). Plan-4 named requirement: apply the `ItemStore.loadGeneration` token pattern to `SubscriptionStore.refresh()` (reset bumps the generation), and widen the cancellation check to also match `URLError(.cancelled)` (transport-level cancellation shape that `is CancellationError` misses).
