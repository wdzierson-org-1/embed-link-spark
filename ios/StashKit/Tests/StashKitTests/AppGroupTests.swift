import XCTest
@testable import StashKit

// Beyond the brief's literal Test: file list (`SharedKeychainStorageTests.swift`,
// `OutboxTests.swift`) but deliberately added and disclosed in task-2-report.md: the task's own
// Step 2 says "TDD SharedKeychainStorage + AppGroup + migration helper", and `AppGroup`'s
// container-resolution/migration logic doesn't belong inside Outbox's or RecordingStore's own
// suites — it's a standalone type with its own contract, so it gets its own file.
final class AppGroupTests: XCTestCase {
    // MARK: - containerURL

    func testContainerURLFallsBackToApplicationSupportWhenUnentitled() {
        // `swift test` always runs as a plain, unsigned macOS host process (Package.swift lists
        // `.macOS(.v14)` solely so the suite can run on the host Mac — there is no macOS Stash
        // target), which carries no App Group entitlement at all. See `AppGroup.containerURL()`'s
        // doc comment for why this is asserted via a platform gate rather than trusting
        // `containerURL(forSecurityApplicationGroupIdentifier:)`'s return value directly.
        let expected = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        XCTAssertEqual(AppGroup.containerURL(), expected)
    }

    // MARK: - userScopedURL

    func testUserScopedURLShapeIsIsolatedPerUserAndStable() {
        let uid1 = UUID()
        let uid2 = UUID()

        let url1 = AppGroup.userScopedURL("StashOutbox", userId: uid1)
        let url2 = AppGroup.userScopedURL("StashOutbox", userId: uid2)

        XCTAssertNotEqual(url1, url2, "two different users must resolve to two different directories")
        XCTAssertEqual(url1.lastPathComponent, uid1.uuidString.lowercased())
        XCTAssertEqual(url1.deletingLastPathComponent().lastPathComponent, "StashOutbox")
        XCTAssertEqual(url1.deletingLastPathComponent().deletingLastPathComponent(), AppGroup.containerURL(),
                       "must be rooted at the shared container, not some other base")
        XCTAssertEqual(url1, AppGroup.userScopedURL("StashOutbox", userId: uid1), "must be stable across calls")
    }

    func testUserScopedURLDiffersByComponent() {
        let uid = UUID()
        let outbox = AppGroup.userScopedURL("StashOutbox", userId: uid)
        let recordings = AppGroup.userScopedURL("StashRecordings", userId: uid)
        XCTAssertNotEqual(outbox, recordings, "different components for the same user must not collide")
    }

    // MARK: - migrateLegacyDirectory

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "appgroup-\(UUID().uuidString)")
    }

    func testMigrateLegacyDirectoryMovesContentsWhenDestinationIsEmpty() throws {
        let legacy = makeTempDir()
        let destination = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacy)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old entry".utf8).write(to: legacy.appending(path: "entry.json"))

        AppGroup.migrateLegacyDirectory(from: legacy, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path),
                       "legacy directory must be MOVED (not copied, not left behind)")
        let moved = destination.appending(path: "entry.json")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "old entry")
    }

    func testMigrateLegacyDirectoryLeavesLegacyAloneWhenDestinationAlreadyHasData() throws {
        let legacy = makeTempDir()
        let destination = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: legacy)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy entry".utf8).write(to: legacy.appending(path: "entry.json"))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("current entry".utf8).write(to: destination.appending(path: "current.json"))

        AppGroup.migrateLegacyDirectory(from: legacy, to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appending(path: "entry.json").path),
                      "must never discard the legacy data just because it wasn't moved — dev-stage decision of " +
                      "record is 'no merge semantics', not 'destructive no-op'")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appending(path: "current.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "entry.json").path),
                       "must not merge legacy files into an already-populated destination")
    }

    func testMigrateLegacyDirectoryNoOpsWhenLegacyNeverExisted() {
        let legacy = makeTempDir()
        let destination = makeTempDir()
        defer { try? FileManager.default.removeItem(at: destination) }

        AppGroup.migrateLegacyDirectory(from: legacy, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                       "nothing to migrate must never conjure a destination directory into existence")
    }

    func testMigrateLegacyDirectoryNoOpsWhenPathsAreIdentical() throws {
        // The un-entitled case (`swift test`, and any process that never gets the App Group
        // entitlement): `userScopedURL` and `legacyUserScopedURL` compute the IDENTICAL formula,
        // so `Outbox`/`RecordingStore` calling this on every `defaultDirectory` resolution must
        // never treat "already there" as "move it into itself".
        let same = makeTempDir()
        defer { try? FileManager.default.removeItem(at: same) }
        try FileManager.default.createDirectory(at: same, withIntermediateDirectories: true)
        try Data("stay put".utf8).write(to: same.appending(path: "entry.json"))

        AppGroup.migrateLegacyDirectory(from: same, to: same)

        XCTAssertEqual(try String(contentsOf: same.appending(path: "entry.json"), encoding: .utf8), "stay put")
    }

    // MARK: - legacyUserScopedURL

    func testLegacyUserScopedURLMatchesApplicationSupportFormulaOutboxUsedToUseDirectly() {
        // This is exactly `Outbox.defaultDirectory`'s PRE-Task-2 formula — the whole point of
        // `legacyUserScopedURL` is to keep computing that old path so `migrateLegacyDirectory` can
        // find data written before this task shipped.
        let uid = UUID()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let expected = base.appending(path: "StashOutbox").appending(path: uid.uuidString.lowercased())

        XCTAssertEqual(AppGroup.legacyUserScopedURL("StashOutbox", userId: uid), expected)
    }
}
