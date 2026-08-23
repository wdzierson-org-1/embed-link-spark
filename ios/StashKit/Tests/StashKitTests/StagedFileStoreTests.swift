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

    // MARK: - mimeType(forFileExtension:) (Task 7 fix round, Critical review finding)

    // `public` specifically so `ProviderLoader` (share extension, a different MODULE) can derive a
    // mime type from a STAGED file's own concrete extension instead of `UTType(typeIdentifier:)`'s
    // abstract category constants (`public.image`/`public.movie`/`public.audio`), whose
    // `.preferredMIMEType` returns `nil` on this toolchain — verified here against the same
    // extensions `ProviderLoader`'s image/movie/audio/pdf branches actually stage to.
    func testMimeTypeForFileExtensionCoversEveryKnownExtension() {
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "png"), "image/png")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "jpg"), "image/jpeg")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "jpeg"), "image/jpeg")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "heic"), "image/heic")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "mov"), "video/quicktime")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "mp4"), "video/mp4")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "m4a"), "audio/mp4")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "pdf"), "application/pdf")
        // Task 7 fix round 2: widened map coverage.
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "gif"), "image/gif")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "webp"), "image/webp")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "mp3"), "audio/mpeg")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "wav"), "audio/wav")
    }

    func testMimeTypeForFileExtensionIsCaseInsensitive() {
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "PNG"), "image/png")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "MOV"), "video/quicktime")
    }

    func testMimeTypeForFileExtensionFallsBackToOctetStreamForUnknownExtensions() {
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: "xyz"), "application/octet-stream")
        XCTAssertEqual(StagedFileStore.mimeType(forFileExtension: ""), "application/octet-stream")
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

        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }
        let created = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings,
                                         staging: staging, now: farFuture)

        XCTAssertEqual(created, 1)
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].kind, .file)
        // Fix round 1: `sweepOrphans` now stores the CANONICALIZED path (see `canonicalPath`),
        // which — for a path built by plain appending like `orphan` here — is identical to
        // `orphan.path` itself, so this compares directly rather than round-tripping through
        // another `pendingRecordings()` call the way this test used to (deviation #9, no longer
        // needed now that the comparison, not the test, absorbs the `/private/var` divergence).
        XCTAssertEqual(pending[0].payload["local_file_path"], orphan.path)
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
        let orphan = try staging.stage(from: source, fileExtension: "png")
        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

        let created = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertEqual(created, 1)
        let pending = await outbox.pending()
        // Fix round 1: compares directly against `orphan.path` — see the comment on
        // `testSweepOrphansCreatesEntryForUnreferencedRecording` for why the old round-trip-through
        // -a-listing workaround (deviation #9) is no longer needed.
        XCTAssertEqual(pending[0].payload["local_file_path"], orphan.path)
        XCTAssertEqual(pending[0].payload["mime_type"], "image/png")
    }

    // Fix round 1 (Important review finding): `referencedPaths` (built from entry payloads written
    // by plain `URL.appending(path:)` — `RecordingStore.newRecordingURL`, `StagedFileStore.stage`,
    // `CaptureViewModel`'s own recording path) and `candidates` (built from
    // `FileManager.contentsOfDirectory` listings) can be TWO DIFFERENT SPELLINGS of the identical
    // file on macOS: a listing reports the symlink-resolved `/private/var/...` form of
    // `temporaryDirectory`'s own `/var/...`. A raw string compare between the two must never read a
    // genuinely-pending file as "unreferenced" — that would mint a duplicate entry for the same
    // physical file, which has no claim protection against its sibling across processes (the exact
    // cross-process double-upload hazard T5+'s claim protocol exists to prevent).
    //
    // This deliberately enqueues the entry the way a NORMAL (non-sweep) capture path does —
    // `CaptureViewModel.submitVoiceNote`'s failure branch stores `fileURL.path` straight off
    // `RecordingStore.newRecordingURL()`, never round-tripped through a directory listing — so the
    // divergence in `sweepOrphans`'s own comparison is exactly what's under test, not an artifact
    // of the test's own setup.
    func testSweepOrphansNeverDuplicatesAnEntryWhoseLocalFilePathDiffersOnlyBySymlinkForm() async throws {
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

        let recording = recordings.newRecordingURL()
        try Data([0x01, 0x02, 0x03]).write(to: recording)
        // Sanity: this must actually exercise the unresolved `/var/...` form — if `temporaryDirectory`
        // ever stopped resolving this way on some future OS, this test would otherwise silently pass
        // for the wrong reason (no divergence to catch).
        XCTAssertTrue(recording.path.hasPrefix("/var/"),
                      "fixture assumption: temporaryDirectory must be the unresolved /var form on this host")
        try await outbox.enqueue(.file, payload: [
            "local_file_path": recording.path,
            "mime_type": "audio/mp4",
            "is_public": "false",
        ])

        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }
        let created = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertEqual(created, 0,
                       "a file already referenced by a pending entry must never be treated as an " +
                       "orphan just because the listing form of its path differs from the entry's own")
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1, "there must be exactly one entry for this file, never a duplicate")
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
