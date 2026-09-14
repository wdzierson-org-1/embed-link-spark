import XCTest
@testable import StashKit

private struct StubInvoker: TranscriptionInvoking, @unchecked Sendable {
    var result: Result<TranscriptionOutcome, Error> = .success(.init(transcription: "Speaker 1: hi", description: "A chat"))

    // A class-backed box so the "last call" recorder survives being read after the (value-type)
    // stub is captured by `invoke`'s async call — mirrors the `@unchecked Sendable` + mutable
    // `var`/`private(set)` shape `StubAccountDeletionTransport` uses, just via a small reference
    // box since this stub's `invoke` is non-mutating (protocol requirement).
    final class Recorder: @unchecked Sendable { var audioUrl: String?; var fileName: String? }
    let recorder = Recorder()

    func invoke(audioUrl: String, fileName: String) async throws -> TranscriptionOutcome {
        recorder.audioUrl = audioUrl
        recorder.fileName = fileName
        switch result {
        case .success(let outcome): return outcome
        case .failure(let error): throw error
        }
    }
}

private final class StubPatcher: TranscriptPatching, @unchecked Sendable {
    var errorToThrow: Error?
    var resultItem: Item?
    private(set) var lastPageBody: String?
    private(set) var lastDescription: String??

    func patchTranscript(itemId: UUID, pageBody: String, description: String?) async throws -> Item {
        lastPageBody = pageBody
        lastDescription = description
        if let errorToThrow { throw errorToThrow }
        return resultItem ?? TranscriptionServiceTests.fixture(pageBody: pageBody, description: description)
    }
}

private final class RecordingTranscriptionSyncer: EmbeddingSyncing, @unchecked Sendable {
    var calls: [(UUID, String)] = []
    func replaceEmbeddings(itemId: UUID, text: String) async throws { calls.append((itemId, text)) }
}

private struct StubError: Error, LocalizedError, Equatable {
    var message: String
    var errorDescription: String? { message }
}

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    nonisolated static func fixture(filePath: String? = "u/rec.m4a", pageBody: String? = "old transcript",
                                    description: String? = "old description") -> Item {
        Item(id: UUID(uuidString: "1B2C3D4E-5F60-4718-8291-0A1B2C3D4E5F")!, type: .audio,
             title: "Voice note", content: nil, url: nil, filePath: filePath,
             description: description, summary: nil, pageBody: pageBody, supplementalNote: nil,
             mimeType: "audio/m4a", isPublic: false, createdAt: .now)
    }

    func testSuccessPatchesOnlyPageBodyAndDescriptionThenSchedulesEmbeddingRefresh() async throws {
        var invoker = StubInvoker()
        invoker.result = .success(.init(transcription: "Speaker 1: hello\nSpeaker 2: hi", description: "Two speakers chat"))
        let patcher = StubPatcher()
        let syncer = RecordingTranscriptionSyncer()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(20))
        let service = TranscriptionService(invoker: invoker, patcher: patcher, refresher: refresher)

        let item = Self.fixture()
        let updated = try await service.retranscribe(item: item)

        XCTAssertEqual(patcher.lastPageBody, "Speaker 1: hello\nSpeaker 2: hi")
        XCTAssertEqual(patcher.lastDescription, "Two speakers chat")
        XCTAssertEqual(updated.pageBody, "Speaker 1: hello\nSpeaker 2: hi")
        // Web parity: only page_body/description are patched — content (the user's own notes)
        // is never part of this call's body at all, so there's nothing to assert "unchanged"
        // beyond the fact `TranscriptPatching`'s signature has no way to send it in the first place.
        XCTAssertEqual(invoker.recorder.fileName, "rec.m4a")
        XCTAssertTrue(invoker.recorder.audioUrl?.contains("u/rec.m4a") ?? false)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(syncer.calls.count, 1, "Expected the embedding refresh to have been scheduled from the merged row")
    }

    func testNoStoredMediaThrowsWithoutInvokingOrPatching() async throws {
        let invoker = StubInvoker()
        let patcher = StubPatcher()
        let refresher = EmbeddingRefresher(syncer: RecordingTranscriptionSyncer())
        let service = TranscriptionService(invoker: invoker, patcher: patcher, refresher: refresher)

        do {
            _ = try await service.retranscribe(item: Self.fixture(filePath: nil))
            XCTFail("expected noStoredMedia")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .noStoredMedia)
        }
        XCTAssertNil(invoker.recorder.audioUrl)
        XCTAssertNil(patcher.lastPageBody)
    }

    func testInvokeErrorPreservesPreviousTranscript() async throws {
        var invoker = StubInvoker()
        invoker.result = .failure(StubError(message: "the network is down"))
        let patcher = StubPatcher()
        let refresher = EmbeddingRefresher(syncer: RecordingTranscriptionSyncer())
        let service = TranscriptionService(invoker: invoker, patcher: patcher, refresher: refresher)

        let item = Self.fixture(pageBody: "the original transcript")
        do {
            _ = try await service.retranscribe(item: item)
            XCTFail("expected invokeFailed")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .invokeFailed("the network is down"))
        }
        // Never reached the patch step at all — the previous transcript was never at risk.
        XCTAssertNil(patcher.lastPageBody)
    }

    func testEmptyTranscriptThrowsWithoutPatching() async throws {
        var invoker = StubInvoker()
        invoker.result = .success(.init(transcription: "   ", description: nil))
        let patcher = StubPatcher()
        let refresher = EmbeddingRefresher(syncer: RecordingTranscriptionSyncer())
        let service = TranscriptionService(invoker: invoker, patcher: patcher, refresher: refresher)

        do {
            _ = try await service.retranscribe(item: Self.fixture())
            XCTFail("expected emptyTranscript")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .emptyTranscript)
        }
        XCTAssertNil(patcher.lastPageBody)
    }

    func testPatchErrorPreservesPreviousTranscriptAndSkipsEmbeddingRefresh() async throws {
        var invoker = StubInvoker()
        invoker.result = .success(.init(transcription: "Speaker 1: new content", description: "new"))
        let patcher = StubPatcher()
        patcher.errorToThrow = StubError(message: "PATCH failed")
        let syncer = RecordingTranscriptionSyncer()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(20))
        let service = TranscriptionService(invoker: invoker, patcher: patcher, refresher: refresher)

        let item = Self.fixture(pageBody: "the original transcript")
        do {
            _ = try await service.retranscribe(item: item)
            XCTFail("expected patchFailed")
        } catch {
            XCTAssertEqual(error as? TranscriptionServiceError, .patchFailed("PATCH failed"))
        }
        // The patch call was attempted (and its input recorded) but its failure means the server
        // row — and hence "the original transcript" — was never actually overwritten.
        XCTAssertEqual(patcher.lastPageBody, "Speaker 1: new content")

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(syncer.calls.isEmpty, "A failed patch must never schedule an embedding refresh")
    }
}
