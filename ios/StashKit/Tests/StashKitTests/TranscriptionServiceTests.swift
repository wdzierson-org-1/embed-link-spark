import XCTest
@testable import StashKit

/// The job's server side, scripted: `startRebuild` succeeds (or throws `startError`, or waits for
/// `releaseStart()` when `holdsStart`), each attributes read returns the next scripted answer (the
/// last one repeats), and `fetchDetail` returns `detail` (or throws `detailError`).
private final class StubJobClient: TranscriptionJobClient, @unchecked Sendable {
    enum Read {
        case attributes(ItemAttributes?)
        case failure(Error)
    }

    private let lock = NSLock()
    private var reads: [Read]
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var startReleased = false
    private var started: [UUID] = []
    private var attributeReadCount = 0
    private var detailReadCount = 0
    var startError: Error?
    var holdsStart = false
    var detail: Item
    var detailError: Error?

    var startedItemIds: [UUID] { lock.withLock { started } }
    var attributeReads: Int { lock.withLock { attributeReadCount } }
    var detailReads: Int { lock.withLock { detailReadCount } }

    init(reads: [Read], detail: Item) {
        self.reads = reads
        self.detail = detail
    }

    func startRebuild(itemId: UUID) async throws {
        let hold = lock.withLock { () -> Bool in
            started.append(itemId)
            return holdsStart && !startReleased
        }
        if hold {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock { () -> Bool in
                    if startReleased { return true }
                    startContinuation = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        if let startError { throw startError }
    }

    func releaseStart() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            startReleased = true
            defer { startContinuation = nil }
            return startContinuation
        }
        waiting?.resume()
    }

    func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        let read = lock.withLock { () -> Read in
            attributeReadCount += 1
            return reads.count > 1 ? reads.removeFirst() : reads[0]
        }
        switch read {
        case .attributes(let attributes): return attributes
        case .failure(let error): throw error
        }
    }

    func fetchDetail(itemId: UUID) async throws -> Item {
        lock.withLock { detailReadCount += 1 }
        if let detailError { throw detailError }
        return detail
    }
}

/// `wait()` suspends until `open()` (a write still in flight).
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                self.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            isOpen = true
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume()
    }
}

/// A clock the fake `sleep` advances — the polling loop runs instantly in tests.
private final class FakeTime: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_790_000_000)
    private var slept: [TimeInterval] = []

    var now: Date { lock.withLock { current } }
    var sleeps: [TimeInterval] { lock.withLock { slept } }

    func sleep(_ seconds: TimeInterval) {
        lock.withLock {
            slept.append(seconds)
            current += seconds
        }
    }
}

private struct StubError: Error, LocalizedError, Equatable {
    var message: String
    var errorDescription: String? { message }
}

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    private let itemId = UUID(uuidString: "1B2C3D4E-5F60-4718-8291-0A1B2C3D4E5F")!

    private func fixture(filePath: String? = "u/rec.m4a", pageBody: String? = "old transcript",
                         transcript: [String: JSONValue]? = nil) -> Item {
        var media = MediaAttributes(durationS: 42)
        if let transcript { media.extra["transcript"] = .object(transcript) }
        return Item(id: itemId, type: .audio, title: "Voice note", content: "my own notes", url: nil,
                    filePath: filePath, description: "old description", summary: nil, pageBody: pageBody,
                    supplementalNote: nil, mimeType: "audio/m4a", isPublic: false, createdAt: .now,
                    attributes: ItemAttributes(media: media))
    }

    private func attributes(status: String, error: String? = nil, updatedAt: String = "2026-09-29T18:40:59.335Z") -> ItemAttributes {
        var transcript: [String: JSONValue] = ["status": .string(status), "updated_at": .string(updatedAt)]
        if let error { transcript["error"] = .string(error) }
        return ItemAttributes(media: MediaAttributes(durationS: 42, extra: ["transcript": .object(transcript)]))
    }

    /// A private activity and write queue unless passed.
    private func makeService(_ client: StubJobClient, time: FakeTime = FakeTime(),
                             activity: TranscriptionActivity? = nil,
                             writeQueue: ItemWriteQueue? = nil) -> TranscriptionService {
        TranscriptionService(client: client, activity: activity ?? TranscriptionActivity(),
                             writeQueue: writeQueue ?? ItemWriteQueue(),
                             now: { time.now }, sleep: { time.sleep($0) })
    }

    // MARK: - Job mode

    /// The job owns every write: the client starts it for this item, watches the status through
    /// `pending` → `processing` → `done`, then hands back the finished row — it never PATCHes.
    func testARebuildStartsTheServerJobAndReturnsTheFinishedRow() async throws {
        var finished = fixture(pageBody: "**Speaker A · 0:00**\n\nhello")
        finished.description = "A short chat"
        finished.attributes = attributes(status: "done")
        let client = StubJobClient(reads: [.attributes(attributes(status: "pending")),
                                           .attributes(attributes(status: "processing")),
                                           .attributes(attributes(status: "processing")),
                                           .attributes(attributes(status: "done"))],
                                   detail: finished)
        let time = FakeTime()

        let outcome = try await makeService(client, time: time).retranscribe(item: fixture())

        XCTAssertEqual(outcome, .finished(finished))
        XCTAssertEqual(client.startedItemIds, [itemId])
        XCTAssertEqual(client.attributeReads, 4)
        XCTAssertEqual(client.detailReads, 1, "the page_body-carrying row is read once, at the end")
        XCTAssertEqual(time.sleeps, [3, 3, 3, 3], "polled every 3 s while young")
    }

    /// The finished row is read in the item's write slot: a sheet save already in flight lands
    /// first, so adopting the row can never roll that save back.
    func testTheSettledRowIsReadAfterWritesAlreadyInFlightForTheItem() async throws {
        let writeQueue = ItemWriteQueue()
        var finished = fixture()
        finished.attributes = attributes(status: "done")
        let client = StubJobClient(reads: [.attributes(attributes(status: "done"))], detail: finished)
        let gate = AsyncGate()
        let itemId = itemId
        let inFlightSave = Task { try await writeQueue.enqueue(itemId: itemId) { await gate.wait(); return 1 } }
        while !writeQueue.isBusy(itemId) { try await Task.sleep(for: .milliseconds(2)) }

        let run = Task { try await makeService(client, writeQueue: writeQueue).retranscribe(item: fixture()) }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(client.detailReads, 0, "waits for the write already in flight")

        gate.open()
        _ = try await inFlightSave.value
        let outcome = try await run.value
        XCTAssertEqual(outcome, .finished(finished))
        XCTAssertEqual(client.detailReads, 1)
    }

    func testAFailedJobReportsItsReasonWithTheRowAsItStands() async throws {
        var after = fixture(pageBody: nil)
        after.attributes = attributes(status: "failed", error: "no_speech")
        let client = StubJobClient(reads: [.attributes(attributes(status: "processing")),
                                           .attributes(after.attributes)],
                                   detail: after)

        let outcome = try await makeService(client).retranscribe(item: fixture())

        XCTAssertEqual(outcome, .failed(after, reason: "no_speech"))
    }

    /// Offline for a moment mid-job: the job doesn't depend on this client, so a failed read is
    /// just retried — never reported as a failed transcription.
    func testReadFailuresWhileWatchingAreRetried() async throws {
        var finished = fixture()
        finished.attributes = attributes(status: "done")
        let client = StubJobClient(reads: [.failure(URLError(.notConnectedToInternet)),
                                           .failure(URLError(.timedOut)),
                                           .attributes(attributes(status: "done"))],
                                   detail: finished)

        let outcome = try await makeService(client).retranscribe(item: fixture())

        XCTAssertEqual(outcome, .finished(finished))
        XCTAssertEqual(client.attributeReads, 3)
    }

    func testPollingSlowsDownAfterTheFirstMinuteAndStopsAtTheLimit() async throws {
        let client = StubJobClient(reads: [.attributes(attributes(status: "processing"))], detail: fixture())
        let time = FakeTime()

        do {
            _ = try await makeService(client, time: time).retranscribe(item: fixture())
            XCTFail("expected stoppedWatching")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .stoppedWatching)
        }
        XCTAssertEqual(time.sleeps.prefix(20).filter { $0 == 3 }.count, 20, "3 s for the first minute")
        XCTAssertEqual(time.sleeps.last, 8, "8 s after that")
        XCTAssertGreaterThanOrEqual(time.sleeps.reduce(0, +), TranscriptionService.maxWait)
        XCTAssertLessThan(time.sleeps.reduce(0, +), TranscriptionService.maxWait + 9)
        XCTAssertEqual(client.detailReads, 0)
    }

    func testAJobThatFinishedButCantBeReadBackIsNotAFailure() async throws {
        let client = StubJobClient(reads: [.attributes(attributes(status: "done"))], detail: fixture())
        client.detailError = URLError(.notConnectedToInternet)

        do {
            _ = try await makeService(client).retranscribe(item: fixture())
            XCTFail("expected stoppedWatching")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .stoppedWatching)
        }
        XCTAssertGreaterThan(client.detailReads, 1, "the read is retried until the limit")
    }

    func testAStartThatFailsChangesNothingAndIsReported() async throws {
        let client = StubJobClient(reads: [.attributes(nil)], detail: fixture())
        client.startError = StubError(message: "transcribe-audio answered HTTP 500")
        let activity = TranscriptionActivity()

        do {
            _ = try await makeService(client, activity: activity).retranscribe(item: fixture())
            XCTFail("expected startFailed")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .startFailed("transcribe-audio answered HTTP 500"))
        }
        XCTAssertEqual(client.attributeReads, 0, "nothing to watch")
        XCTAssertFalse(activity.isRunning(itemId), "the busy state ends with the failed start")
    }

    func testNoStoredMediaStartsNothing() async throws {
        let client = StubJobClient(reads: [.attributes(nil)], detail: fixture())
        do {
            _ = try await makeService(client).retranscribe(item: fixture(filePath: nil))
            XCTFail("expected noStoredMedia")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .noStoredMedia)
        }
        XCTAssertTrue(client.startedItemIds.isEmpty)
    }

    /// The busy state lives app-wide for the whole run (a reopened sheet still shows it), and a
    /// second run for the same item can't start while one is in flight.
    func testARunIsTrackedAppWideAndNeverStartedTwice() async throws {
        var finished = fixture()
        finished.attributes = attributes(status: "done")
        let client = StubJobClient(reads: [.attributes(attributes(status: "done"))], detail: finished)
        client.holdsStart = true
        let activity = TranscriptionActivity()
        let service = makeService(client, activity: activity)
        let item = fixture()
        let first = Task { try await service.retranscribe(item: item) }
        while !activity.isRunning(item.id) { try await Task.sleep(for: .milliseconds(5)) }

        do {
            _ = try await service.retranscribe(item: item)
            XCTFail("expected alreadyRunning")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .alreadyRunning)
        }
        let followed = try await service.follow(itemId: item.id)
        XCTAssertNil(followed, "already watched — that watcher delivers the result")

        client.releaseStart()
        _ = try await first.value
        XCTAssertEqual(client.startedItemIds, [item.id], "one paid run")
        XCTAssertFalse(activity.isRunning(item.id), "the busy state ends with the run")
    }

    /// A sheet opened while a job runs (a fresh recording's first transcription, or a rebuild
    /// started from a sheet since closed) follows it without starting anything.
    func testFollowingARunningJobNeverStartsOne() async throws {
        var finished = fixture()
        finished.attributes = attributes(status: "done")
        let client = StubJobClient(reads: [.attributes(attributes(status: "processing")),
                                           .attributes(attributes(status: "done"))],
                                   detail: finished)

        let outcome = try await makeService(client).follow(itemId: itemId)

        XCTAssertEqual(outcome, .finished(finished))
        XCTAssertTrue(client.startedItemIds.isEmpty)
    }

    /// Its own short request — `{ itemId, rebuild: true }` with the platform's two auth headers —
    /// never the preview body (`{ audioUrl, fileName }`), which defers files over 24 MiB.
    func testTheStartRequestAsksForAServerSideRebuild() throws {
        let request = try SupabaseTranscriptionJobClient.startRequest(itemId: itemId, accessToken: "user-jwt")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, StashConfig.supabaseURL.host)
        XCTAssertEqual(request.url?.path, "/functions/v1/transcribe-audio")
        XCTAssertEqual(request.timeoutInterval, SupabaseTranscriptionJobClient.startTimeout)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), StashConfig.supabaseAnonKey)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["itemId"] as? String, itemId.uuidString.lowercased())
        XCTAssertEqual(body["rebuild"] as? Bool, true)
        XCTAssertEqual(body.count, 2)
    }

    // MARK: - TranscriptJobState

    func testJobStateReadsTheServersTranscriptStatus() throws {
        let attributes = ItemAttributes(media: MediaAttributes(extra: ["transcript": .object([
            "status": .string("processing"), "chunks_total": .number(3), "chunks_done": .number(1),
            "attempts": .number(1), "source": .string("openai:gpt-4o-transcribe-diarize"),
            "updated_at": .string("2026-09-29T18:40:59.335Z"),
        ])]))
        let state = try XCTUnwrap(TranscriptJobState(attributes: attributes))
        XCTAssertEqual(state.status, .processing)
        XCTAssertEqual(state.chunksDone, 1)
        XCTAssertEqual(state.chunksTotal, 3)
        XCTAssertNil(state.error)
        let updatedAt = try XCTUnwrap(state.updatedAt)
        XCTAssertEqual(updatedAt.timeIntervalSince1970, 1_790_707_259.335, accuracy: 0.001)

        XCTAssertNil(TranscriptJobState(attributes: ItemAttributes()), "no media")
        XCTAssertNil(TranscriptJobState(attributes: ItemAttributes(media: MediaAttributes(durationS: 3))), "no transcript")
        XCTAssertNil(TranscriptJobState(attributes: self.attributes(status: "thinking")), "unknown status")
        XCTAssertEqual(TranscriptJobState(attributes: self.attributes(status: "failed", error: "no_speech"))?.error, "no_speech")
    }

    /// Running = pending/processing AND recently touched: a status the job stopped updating long ago
    /// (a crashed job the sweep never resumed, a legacy row) must not pin "Transcribing…" forever.
    func testOnlyAFreshPendingOrProcessingStatusIsRunning() {
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        func state(_ status: TranscriptJobState.Status, updatedAt: Date? = stamp) -> TranscriptJobState {
            TranscriptJobState(status: status, updatedAt: updatedAt)
        }
        XCTAssertTrue(state(.pending).isRunning(at: stamp.addingTimeInterval(60)))
        XCTAssertTrue(state(.processing).isRunning(at: stamp.addingTimeInterval(19 * 60)))
        XCTAssertFalse(state(.processing).isRunning(at: stamp.addingTimeInterval(21 * 60)), "stalled")
        XCTAssertFalse(state(.processing, updatedAt: nil).isRunning(at: stamp), "no timestamp — can't be vouched for")
        XCTAssertFalse(state(.done).isRunning(at: stamp))
        XCTAssertFalse(state(.failed).isRunning(at: stamp))
        XCTAssertEqual(TranscriptJobState.parseTimestamp("2026-09-29T18:40:59Z")?.timeIntervalSince1970, 1_790_707_259)
    }
}
