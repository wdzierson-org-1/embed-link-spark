import XCTest
@testable import StashKit

final class RecordingStoreTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "recordings-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // Real Application Support, not a tmp override — mirrors OutboxTests'
    // testPerUserDirectoriesAreIsolated: `defaultDirectory` is asserted directly (no `RecordingStore`
    // instance created, so no real directory is touched on the machine running the tests), purely
    // for its path SHAPE.
    func testDefaultDirectoryShapeIsIsolatedPerUser() {
        let uid1 = UUID()
        let uid2 = UUID()

        let dir1 = RecordingStore.defaultDirectory(userId: uid1)
        let dir2 = RecordingStore.defaultDirectory(userId: uid2)

        XCTAssertNotEqual(dir1, dir2, "two different users must resolve to two different recordings directories")
        XCTAssertEqual(dir1.lastPathComponent, uid1.uuidString.lowercased())
        XCTAssertEqual(dir2.lastPathComponent, uid2.uuidString.lowercased())
        XCTAssertEqual(dir1.deletingLastPathComponent().lastPathComponent, "StashRecordings")
        XCTAssertEqual(dir2.deletingLastPathComponent().lastPathComponent, "StashRecordings")

        // Same user, called twice, must resolve to the same directory.
        XCTAssertEqual(dir1, RecordingStore.defaultDirectory(userId: uid1))
    }

    // Task 2 (App Group): `defaultDirectory` now delegates to `AppGroup.userScopedURL` instead of
    // computing the Application-Support-plus-"StashRecordings" formula inline — mirrors
    // `OutboxTests.testDefaultDirectoryDelegatesToAppGroupUserScopedURL`.
    func testDefaultDirectoryDelegatesToAppGroupUserScopedURL() {
        let uid = UUID()
        XCTAssertEqual(RecordingStore.defaultDirectory(userId: uid),
                       AppGroup.userScopedURL("StashRecordings", userId: uid))
    }

    func testNewRecordingURLIsUniqueWithM4ASuffix() {
        let store = RecordingStore(userId: UUID(), directory: dir)

        let first = store.newRecordingURL()
        let second = store.newRecordingURL()

        XCTAssertNotEqual(first, second, "every call must mint a fresh, never-reused URL")
        XCTAssertEqual(first.pathExtension, "m4a")
        XCTAssertEqual(second.pathExtension, "m4a")
        XCTAssertEqual(first.deletingLastPathComponent().path, dir.path)
    }

    func testPendingRecordingsListsOnlyFiles() throws {
        let store = RecordingStore(userId: UUID(), directory: dir)
        let recording = store.newRecordingURL()
        try Data([0x01, 0x02, 0x03]).write(to: recording)
        // A stray subdirectory must never be handed back as if it were a recording.
        try FileManager.default.createDirectory(at: dir.appending(path: "not-a-recording"),
                                                 withIntermediateDirectories: true)

        let pending = store.pendingRecordings()

        // Compared by filename, not full `URL` equality: on macOS `temporaryDirectory` reports
        // `/var/folders/...`, a symlink to `/private/var/folders/...`, but
        // `FileManager.contentsOfDirectory` reports the resolved `/private/var/...` form —
        // Foundation's `URL.resolvingSymlinksInPath()` documents that it deliberately does NOT
        // resolve `/tmp`, `/var`, or `/etc`, so there is no clean way to make a hand-built `URL`
        // and a directory-listing result compare equal here. The filename is what this test
        // actually cares about (exactly the file that was written, not the stray subdirectory).
        XCTAssertEqual(pending.map(\.lastPathComponent), [recording.lastPathComponent])
    }

    func testDiscardRemovesTheFile() throws {
        let store = RecordingStore(userId: UUID(), directory: dir)
        let recording = store.newRecordingURL()
        try Data([0x01]).write(to: recording)
        XCTAssertEqual(store.pendingRecordings().count, 1)

        store.discard(recording)

        XCTAssertTrue(store.pendingRecordings().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.path))
    }
}
