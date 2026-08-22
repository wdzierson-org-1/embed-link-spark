import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import StashKit

/// Failure modes for `writeNoiseImage` below — test-only, distinct from `StagedFileStoreError`
/// (which is what the PRODUCTION code under test is expected to throw).
private enum TestImageError: Error { case cannotCreateContext, cannotCreateImage, cannotCreateDestination, finalizeFailed }

/// Builds a real, ImageIO-readable PNG with genuinely noisy (incompressible) pixel data, written
/// via a raw `CGContext` bitmap — StashKit has no UIKit, so `UIGraphicsImageRenderer` (app-side)
/// isn't available here, per the brief's own Step 1 instruction. Noise, not a solid fill,
/// deliberately: a large SOLID-color source compresses so well under PNG that "the downscaled
/// output is smaller than the source" could pass even if downscaling were doing nothing useful —
/// noise makes the size comparison actually exercise the resize, not PNG's own compression.
private func writeNoiseImage(width: Int, height: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = width * 4
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw TestImageError.cannotCreateContext
    }
    guard let buffer = context.data else { throw TestImageError.cannotCreateContext }
    arc4random_buf(buffer, height * bytesPerRow)
    guard let cgImage = context.makeImage() else { throw TestImageError.cannotCreateImage }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TestImageError.cannotCreateDestination
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { throw TestImageError.finalizeFailed }
}

final class StagedFileStoreTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "staging-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func makeSourceFile(bytes: Data = Data([0x01, 0x02, 0x03])) throws -> URL {
        let source = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).bin")
        try bytes.write(to: source)
        return source
    }

    // MARK: - stage(from:fileExtension:)

    func testStageCopiesFileLeavingSourceIntactAndByteEqual() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let bytes = Data([0x01, 0x02, 0x03, 0xFF, 0xEE])
        let source = try makeSourceFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: source) }

        let staged = try store.stage(from: source, fileExtension: "bin")

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the source file must survive staging untouched")
        XCTAssertEqual(try Data(contentsOf: source), bytes, "the source's own bytes must be unmodified")
        XCTAssertEqual(try Data(contentsOf: staged), bytes, "the staged copy must be byte-for-byte identical")
        XCTAssertEqual(staged.pathExtension, "bin")
        XCTAssertEqual(staged.deletingLastPathComponent().path, dir.path)
    }

    func testStageProducesAFreshNameEveryCall() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let source = try makeSourceFile()
        defer { try? FileManager.default.removeItem(at: source) }

        let first = try store.stage(from: source, fileExtension: "bin")
        let second = try store.stage(from: source, fileExtension: "bin")

        XCTAssertNotEqual(first, second, "every call must mint a fresh, never-reused destination")
    }

    // MARK: - stageDownscaledImage

    func testStageDownscaledImageBoundsPixelSizeAndReducesFileSize() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let source = dir.appending(path: "source.png")
        try writeNoiseImage(width: 1200, height: 900, to: source)
        let sourceSize = try XCTUnwrap(store.fileSize(of: source))

        let staged = try store.stageDownscaledImage(from: source, maxDimension: 300, quality: 0.6)

        guard let imageSource = CGImageSourceCreateWithURL(staged as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return XCTFail("staged output must be a readable image")
        }
        XCTAssertLessThanOrEqual(max(width, height), 300, "the staged output must be bounded by maxDimension")
        let stagedSize = try XCTUnwrap(store.fileSize(of: staged))
        XCTAssertLessThan(stagedSize, sourceSize, "downscaling a large noisy image must produce a smaller file")
        XCTAssertEqual(staged.pathExtension, "jpg")
    }

    func testStageDownscaledImageThrowsForUnreadableSource() {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let missing = dir.appending(path: "does-not-exist.png")

        XCTAssertThrowsError(try store.stageDownscaledImage(from: missing, maxDimension: 300, quality: 0.6)) { error in
            XCTAssertEqual(error as? StagedFileStoreError, .cannotReadImage)
        }
    }

    // MARK: - pendingStaged / discard / fileSize

    func testPendingStagedListsOnlyFiles() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let source = try makeSourceFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let staged = try store.stage(from: source, fileExtension: "bin")
        // A stray subdirectory must never be handed back as if it were a staged file — mirrors
        // RecordingStoreTests.testPendingRecordingsListsOnlyFiles.
        try FileManager.default.createDirectory(at: dir.appending(path: "not-a-file"), withIntermediateDirectories: true)

        let pending = store.pendingStaged()

        XCTAssertEqual(pending.map(\.lastPathComponent), [staged.lastPathComponent])
    }

    func testDiscardRemovesTheFile() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let source = try makeSourceFile()
        defer { try? FileManager.default.removeItem(at: source) }
        let staged = try store.stage(from: source, fileExtension: "bin")

        store.discard(staged)

        XCTAssertTrue(store.pendingStaged().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testFileSizeMatchesActualByteCount() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let source = try makeSourceFile(bytes: Data(repeating: 0xAB, count: 777))
        defer { try? FileManager.default.removeItem(at: source) }
        let staged = try store.stage(from: source, fileExtension: "bin")

        XCTAssertEqual(store.fileSize(of: staged), 777)
    }

    func testFileSizeIsNilForMissingFile() {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        XCTAssertNil(store.fileSize(of: dir.appending(path: "nope.bin")))
    }

    // MARK: - defaultDirectory

    // Mirrors OutboxTests/RecordingStoreTests' own `testDefaultDirectoryDelegatesToAppGroupUserScopedURL`
    // — proves the WIRING (not just the path shape), same rationale as those.
    func testDefaultDirectoryDelegatesToAppGroupUserScopedURL() {
        let uid = UUID()
        XCTAssertEqual(StagedFileStore.defaultDirectory(userId: uid), AppGroup.userScopedURL("StashStaging", userId: uid))
    }

    // MARK: - sweepOrphans: recordings/staging files with no referencing Outbox entry

    func testSweepOrphansCreatesEntryForUnreferencedRecording() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let userId = UUID()
        let outbox = Outbox(directory: outboxDir)
        let recordings = RecordingStore(userId: userId, directory: recordingsDir)
        let staging = StagedFileStore(userId: userId, directory: dir)

        let orphan = recordings.newRecordingURL()
        try Data([0x01, 0x02]).write(to: orphan)
        // NOT `orphan.path` — `pendingRecordings()` lists via `FileManager.contentsOfDirectory`,
        // which (on macOS) reports the SYMLINK-RESOLVED `/private/var/...` form of `temporaryDirectory`'s
        // own `/var/...`, so the path `sweepOrphans` actually captures differs textually (though not
        // in the file it names) from the hand-built URL above — exact same quirk
        // RecordingStoreTests documents for `pendingRecordings()` itself. Deriving the expected
        // value through the same listing call sidesteps it.
        let canonicalOrphanPath = try XCTUnwrap(recordings.pendingRecordings().first).path

        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }
        let created = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings,
                                         staging: staging, now: farFuture)

        XCTAssertEqual(created, 1)
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].kind, .file)
        XCTAssertEqual(pending[0].payload["local_file_path"], canonicalOrphanPath)
        XCTAssertEqual(pending[0].payload["mime_type"], "audio/mp4")
    }

    func testSweepOrphansIsIdempotent() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let userId = UUID()
        let outbox = Outbox(directory: outboxDir)
        let recordings = RecordingStore(userId: userId, directory: recordingsDir)
        let staging = StagedFileStore(userId: userId, directory: dir)
        let orphan = recordings.newRecordingURL()
        try Data([0x01]).write(to: orphan)
        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

        let first = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging, now: farFuture)
        XCTAssertEqual(first, 1)

        let second = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertEqual(second, 0, "a file already referenced by an Outbox entry must never get a second one")
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
    }

    func testSweepOrphansSkipsFilesYoungerThan60s() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let userId = UUID()
        let outbox = Outbox(directory: outboxDir)
        let recordings = RecordingStore(userId: userId, directory: recordingsDir)
        let staging = StagedFileStore(userId: userId, directory: dir)
        let orphan = recordings.newRecordingURL()
        try Data([0x01]).write(to: orphan)   // just written — younger than 60s under the real clock

        let created = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging)

        XCTAssertEqual(created, 0, "a file that may still be mid-write must never be swept")
        let pending = await outbox.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testSweepOrphansCoversStagedFilesToo() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let userId = UUID()
        let outbox = Outbox(directory: outboxDir)
        let recordings = RecordingStore(userId: userId, directory: recordingsDir)
        let staging = StagedFileStore(userId: userId, directory: dir)
        let source = try makeSourceFile()
        defer { try? FileManager.default.removeItem(at: source) }
        _ = try staging.stage(from: source, fileExtension: "png")
        // See `testSweepOrphansCreatesEntryForUnreferencedRecording`'s comment: derive the
        // expected path through the same `contentsOfDirectory`-backed listing `sweepOrphans`
        // itself uses, rather than the hand-built `URL` returned by `stage`, to sidestep macOS's
        // `/var` vs `/private/var` symlink-resolution quirk.
        let canonicalOrphanPath = try XCTUnwrap(staging.pendingStaged().first).path
        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

        let created = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertEqual(created, 1)
        let pending = await outbox.pending()
        XCTAssertEqual(pending[0].payload["local_file_path"], canonicalOrphanPath)
        XCTAssertEqual(pending[0].payload["mime_type"], "image/png")
    }

    // MARK: - sweepOrphans: stray Outbox `.claim` sidecars with no matching entry (Task 3 review carry)

    func testSweepOrphansDeletesStrayClaimFileWithNoMatchingEntry() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let outbox = Outbox(directory: outboxDir)
        try await outbox.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let pending = await outbox.pending()
        let entryId = try XCTUnwrap(pending.first).id
        let claimed = await outbox.claimEntry(id: entryId)
        XCTAssertTrue(claimed)
        // Simulate the crash window this closes: the entry's own `.json` is already gone (e.g. a
        // successful send just removed it) but the process died before it could release the claim.
        try FileManager.default.removeItem(at: outboxDir.appending(path: "\(entryId.uuidString).json"))
        let claimURL = outboxDir.appending(path: "\(entryId.uuidString).claim")
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path))

        let recordings = RecordingStore(userId: UUID(), directory: recordingsDir)
        let staging = StagedFileStore(userId: UUID(), directory: dir)
        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

        _ = await sweepOrphans(userId: UUID(), outbox: outbox, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path),
                       "a claim whose entry is already gone is inert clutter and must be swept")
    }

    func testSweepOrphansNeverTouchesALiveClaimWithAMatchingEntry() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let outbox = Outbox(directory: outboxDir)
        try await outbox.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let pending = await outbox.pending()
        let entryId = try XCTUnwrap(pending.first).id
        let claimed = await outbox.claimEntry(id: entryId)
        XCTAssertTrue(claimed)
        let claimURL = outboxDir.appending(path: "\(entryId.uuidString).claim")

        let recordings = RecordingStore(userId: UUID(), directory: recordingsDir)
        let staging = StagedFileStore(userId: UUID(), directory: dir)
        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

        _ = await sweepOrphans(userId: UUID(), outbox: outbox, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path),
                      "a claim whose entry still exists must never be touched, regardless of age")
        let pendingAfter = await outbox.pending()
        XCTAssertEqual(pendingAfter.count, 1, "the still-claimed entry itself must survive untouched")
    }

    func testSweepOrphansSkipsYoungOrphanClaims() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        let recordingsDir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outboxDir)
            try? FileManager.default.removeItem(at: recordingsDir)
        }
        let outbox = Outbox(directory: outboxDir)
        try await outbox.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let pending = await outbox.pending()
        let entryId = try XCTUnwrap(pending.first).id
        _ = await outbox.claimEntry(id: entryId)
        try FileManager.default.removeItem(at: outboxDir.appending(path: "\(entryId.uuidString).json"))
        let claimURL = outboxDir.appending(path: "\(entryId.uuidString).claim")

        let recordings = RecordingStore(userId: UUID(), directory: recordingsDir)
        let staging = StagedFileStore(userId: UUID(), directory: dir)

        // Default `now` (real current time) — the claim was created microseconds ago.
        _ = await sweepOrphans(userId: UUID(), outbox: outbox, recordings: recordings, staging: staging)

        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path),
                      "a just-orphaned claim within the grace period must survive — it may be " +
                      "mid-cleanup by its own owning process")
    }
}
