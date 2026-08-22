import XCTest
@testable import StashKit

/// Exercises `SharedKeychainStorage` against the REAL local keychain (there is no in-memory
/// substitute for `Security.framework` — this is the same tradeoff supabase-swift's own
/// `KeychainLocalStorage` tests make). Every test uses a fresh, unique `service` string
/// (`setUp`) so runs never collide with each other, with other suites, or — critically — with
/// the actual production service string (`"it.gostash.stash.session"`), which is never touched
/// here.
final class SharedKeychainStorageTests: XCTestCase {
    var service: String!
    var storage: SharedKeychainStorage!

    override func setUp() {
        service = "it.gostash.stash.test.\(UUID().uuidString)"
        // accessGroup: nil — the only path `swift test` can hermetically exercise. The group
        // (non-nil) path needs a second, actually-entitled process to mean anything and is
        // live-verified once the extension target exists (Task 5), per the brief.
        storage = SharedKeychainStorage(accessGroup: nil, service: service)
    }

    override func tearDown() {
        try? storage.remove(key: "session")
        try? storage.remove(key: "other")
    }

    func testStoreThenRetrieveRoundTripsTheExactBytes() throws {
        let value = Data("hello session".utf8)

        try storage.store(key: "session", value: value)
        let retrieved = try storage.retrieve(key: "session")

        XCTAssertEqual(retrieved, value)
    }

    // Deliberate divergence from supabase-swift's own reference `KeychainLocalStorage.retrieve`
    // (Sources/Auth/Internal/Keychain.swift + Storage/AuthLocalStorage.swift, v2.54.1 checkout):
    // that implementation propagates `SecItemCopyMatching`'s `errSecItemNotFound` straight
    // through as a THROWN error, contradicting its own doc comment ("returns nil if none
    // exists") — supabase-swift's internal `SessionStorage.live().get` happens to paper over
    // this by catching every error and logging + returning nil, so the discrepancy is invisible
    // upstream. This type implements the documented CONTRACT directly, so a fresh install (no
    // session ever stored) never logs a spurious "failed to retrieve session" error.
    func testRetrieveReturnsNilWhenKeyWasNeverStored() throws {
        let retrieved = try storage.retrieve(key: "session")
        XCTAssertNil(retrieved, "a never-stored key must be a normal nil, never a thrown error")
    }

    func testStoreOverwritesAPreviousValueUnderTheSameKey() throws {
        try storage.store(key: "session", value: Data("first".utf8))
        try storage.store(key: "session", value: Data("second".utf8))

        let retrieved = try storage.retrieve(key: "session")

        XCTAssertEqual(retrieved, Data("second".utf8))
    }

    func testRemoveDeletesAStoredValue() throws {
        try storage.store(key: "session", value: Data("gone soon".utf8))

        try storage.remove(key: "session")

        XCTAssertNil(try storage.retrieve(key: "session"))
    }

    // Same divergence as `retrieve`: sign-out calls `remove` unconditionally, whether or not a
    // session was ever actually persisted (e.g. cancelling on the sign-in screen). That must
    // never throw.
    func testRemoveIsIdempotentWhenKeyWasNeverStored() {
        XCTAssertNoThrow(try storage.remove(key: "session"))
    }

    func testDistinctKeysUnderTheSameServiceDoNotCollide() throws {
        try storage.store(key: "session", value: Data("session value".utf8))
        try storage.store(key: "other", value: Data("other value".utf8))

        XCTAssertEqual(try storage.retrieve(key: "session"), Data("session value".utf8))
        XCTAssertEqual(try storage.retrieve(key: "other"), Data("other value".utf8))
    }

    func testDistinctServicesDoNotCollideOnTheSameKey() throws {
        let otherService = "it.gostash.stash.test.\(UUID().uuidString)"
        let otherStorage = SharedKeychainStorage(accessGroup: nil, service: otherService)
        defer { try? otherStorage.remove(key: "session") }

        try storage.store(key: "session", value: Data("mine".utf8))
        try otherStorage.store(key: "session", value: Data("theirs".utf8))

        XCTAssertEqual(try storage.retrieve(key: "session"), Data("mine".utf8))
        XCTAssertEqual(try otherStorage.retrieve(key: "session"), Data("theirs".utf8))
    }

    // MARK: - resolvedAccessGroup (StashClient's probe)

    // The entitled (non-nil) path is deliberately NOT exercised here — see the doc comment on
    // `resolvedAccessGroup` for why a naive "try the write, see if it fails" check can't be
    // trusted on macOS (which is what `swift test` always runs as), and why this is instead
    // platform-gated to only ever run its dynamic probe on iOS. That path is live-verified once
    // the extension target exists and both processes carry the real entitlement (Task 5), per
    // the brief. This asserts the un-entitled fallback, which the platform gate makes fully and
    // hermetically testable right now.
    func testResolvedAccessGroupIsNilWhenUnentitled() {
        let resolved = SharedKeychainStorage.resolvedAccessGroup(suffix: "it.gostash.stash.shared",
                                                                 service: "it.gostash.stash.test.probe")
        XCTAssertNil(resolved)
    }
}
