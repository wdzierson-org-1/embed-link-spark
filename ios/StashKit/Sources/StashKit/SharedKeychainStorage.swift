import Foundation
import Security
import Supabase

/// `AuthLocalStorage` (supabase-swift v2.54.1, `Sources/Auth/Storage/AuthLocalStorage.swift`) —
/// verified against the pinned checkout (SPM's cached bare clone, revision
/// `b118484ae0eb4a6b6ce1b216711d660baf6ec1aa`, tag 2.54.1):
///
/// ```swift
/// public protocol AuthLocalStorage: Sendable {
///   func store(key: String, value: Data) throws
///   func retrieve(key: String) throws -> Data?
///   func remove(key: String) throws
/// }
/// ```
///
/// Matches the brief's sketch exactly — no signature adaptation needed. `SupabaseClientOptions`
/// (`Sources/Supabase/Types.swift`) accepts it as `AuthOptions.init(storage: any AuthLocalStorage,
/// ...)`; `StashClient` passes a `SharedKeychainStorage` there directly.
///
/// A Keychain item that can carry an explicit access group, so the app and (from Plan 5 Task 5)
/// the share extension see the SAME signed-in session. Deliberately a fresh, minimal
/// reimplementation rather than reusing supabase-swift's own `KeychainLocalStorage`/`Keychain`
/// (`Sources/Auth/Internal/Keychain.swift`): that wrapper is `internal` to the `Auth` module, so
/// it isn't visible outside supabase-swift at all.
public struct SharedKeychainStorage: AuthLocalStorage {
    private let service: String
    private let accessGroup: String?

    public init(accessGroup: String?, service: String = "it.gostash.stash.session") {
        self.accessGroup = accessGroup
        self.service = service
    }

    public func store(key: String, value: Data) throws {
        var addQuery = query(forKey: key)
        addQuery[kSecValueData as String] = value
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: value]
            try assertSuccess(SecItemUpdate(query(forKey: key) as CFDictionary, update as CFDictionary))
        } else {
            try assertSuccess(addStatus)
        }
    }

    // Deliberate divergence from supabase-swift's own `KeychainLocalStorage.retrieve` — see
    // SharedKeychainStorageTests.testRetrieveReturnsNilWhenKeyWasNeverStored for the full
    // rationale: that reference implementation propagates `errSecItemNotFound` as a thrown
    // error, contradicting its own doc comment. This implements the documented protocol contract
    // ("or nil if none exists") directly.
    public func retrieve(key: String) throws -> Data? {
        var lookupQuery = query(forKey: key)
        lookupQuery[kSecReturnData as String] = true
        lookupQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try assertSuccess(status)
        return result as? Data
    }

    // Same divergence, for the same reason: deleting an absent item is treated as an already-true
    // success (idempotent), not an error — `remove` runs unconditionally on sign-out whether or
    // not a session was ever actually persisted.
    public func remove(key: String) throws {
        let status = SecItemDelete(query(forKey: key) as CFDictionary)
        if status == errSecItemNotFound { return }
        try assertSuccess(status)
    }

    private func query(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func assertSuccess(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw SharedKeychainStorageError(status: status) }
    }
}

public struct SharedKeychainStorageError: Error, CustomStringConvertible, Sendable {
    public let status: OSStatus

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "SharedKeychainStorage error \(status): \(message)"
    }
}

extension SharedKeychainStorage {
    /// The fully-qualified (`<TeamID>.<suffix>`) Keychain access group `StashClient` should pass
    /// to `SharedKeychainStorage.init`, or `nil` when this process isn't entitled to use one —
    /// `swift test`'s macOS host, or any other un-entitled context — in which case
    /// `SharedKeychainStorage` falls back to this process's own default (non-shared) keychain,
    /// exactly today's (pre-Plan-5) behavior.
    ///
    /// `$(AppIdentifierPrefix)` — the literal token the brief and `Stash.entitlements` use — is
    /// an Xcode BUILD-TIME macro: it's substituted only inside `.entitlements`/`Info.plist` files
    /// as Xcode produces the compiled binary's code signature. There is no runtime equivalent, so
    /// source code can't embed that literal string and expect Security.framework to expand it —
    /// `kSecAttrAccessGroup` is matched against the process's actual SIGNED entitlements
    /// verbatim. This resolves the real, Team-ID-qualified group the standard way (the technique
    /// behind Apple's own "discover my app's Team ID at runtime" guidance): write a throwaway
    /// keychain item with NO explicit access group, read back whatever access group the OS
    /// auto-assigned it (`"<TeamID>.<bundle-id-or-first-listed-group>"`), and take the substring
    /// before the first "." as the Team ID (Team IDs are a fixed alphanumeric format with no
    /// dots, so this holds regardless of which access group the OS actually defaulted to) — then
    /// verifies the CONSTRUCTED group is genuinely writable before trusting it, rather than
    /// assuming the Team ID alone is sufficient proof of entitlement.
    ///
    /// `#if os(iOS)`-gated for the same reason as `AppGroup.containerURL()`: verified empirically
    /// (throwaway spike, not checked in) that a bare macOS `swift test` host process — unsigned,
    /// un-sandboxed — can write a Keychain item under ANY arbitrary `kSecAttrAccessGroup` string
    /// with NO enforcement at all (`SecItemAdd` returned `errSecSuccess` even for a made-up
    /// `"FAKETEAMID1234.it.gostash.stash.shared"`). A "write it, see if it fails" probe is
    /// therefore meaningless on macOS — it would always report "entitled". iOS (device/Simulator)
    /// DOES enforce access groups against the process's real entitlements (confirmed working with
    /// this project's actual `Stash.entitlements`), so the dynamic probe only ever runs there;
    /// every other platform always resolves to `nil`, which is what keeps `swift test` hermetic
    /// per the brief's design intent. The entitled (non-nil) path is live-verified once the
    /// extension target exists and both processes carry the real entitlement (Task 5).
    static func resolvedAccessGroup(suffix: String, service: String) -> String? {
        #if os(iOS)
        guard let teamID = discoverTeamIDPrefix(service: service) else { return nil }
        let candidate = "\(teamID).\(suffix)"
        let probeKey = "accessGroupProbe"
        let probe = SharedKeychainStorage(accessGroup: candidate, service: service)
        guard (try? probe.store(key: probeKey, value: Data([0x01]))) != nil else { return nil }
        try? probe.remove(key: probeKey)
        return candidate
        #else
        return nil
        #endif
    }

    #if os(iOS)
    private static func discoverTeamIDPrefix(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "teamIDProbe",
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            status = SecItemAdd(query as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let accessGroup = attributes[kSecAttrAccessGroup as String] as? String,
              let teamID = accessGroup.split(separator: ".").first
        else { return nil }
        return String(teamID)
    }
    #endif
}
