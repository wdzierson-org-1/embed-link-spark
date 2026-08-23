import Foundation
import os.log

/// The App Group container the app and (from Plan 5 Task 5) the share extension both read and
/// write: durable on-disk state — `Outbox`, `RecordingStore`, and Task 4's `StagedFileStore` —
/// lives here so the extension can enqueue into the same Outbox the app drains. This is a
/// SEPARATE sharing mechanism from the Keychain: see `SharedKeychainStorage` for session sharing,
/// which uses its own `keychain-access-groups` entitlement/namespace, not this identifier.
public enum AppGroup {
    public static let identifier = "group.it.gostash.stash"

    private static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// The shared container when the `com.apple.security.application-groups` entitlement is
    /// present and actually honored; falls back to this process's own Application Support
    /// directory otherwise (unit tests + any other un-entitled context). Callers never need to
    /// know which one they got — the returned URL is always a valid, creatable directory root.
    ///
    /// `#if os(iOS)`-gated rather than trusting
    /// `containerURL(forSecurityApplicationGroupIdentifier:)`'s return value on every platform:
    /// verified empirically (throwaway `swift run` spike, not checked in) that a bare, unsigned
    /// macOS host process — exactly what `swift test` runs as, since Package.swift lists
    /// `.macOS(.v14)` solely so this suite can run on the host Mac; there is no macOS Stash
    /// target — asking for `containerURL(forSecurityApplicationGroupIdentifier: identifier)` with
    /// NO entitlement at all got back a real, non-nil `~/Library/Group Containers/...` URL. The
    /// directory didn't exist yet, but ordinary POSIX permissions would have let the process
    /// create and write under it anyway: macOS only enforces the Group-Containers redirect for
    /// App-Sandboxed processes, and a bare command-line/XCTest host binary isn't sandboxed. Left
    /// ungated, that would make `swift test` silently read/write real files under the
    /// developer's own `~/Library/Group Containers/group.it.gostash.stash/` — exactly what the
    /// brief's "Application Support fallback" design is meant to prevent. iOS (device/Simulator)
    /// DOES enforce the entitlement correctly (confirmed working for the real, entitled app), so
    /// the real check only ever runs there; every other platform always takes the Application
    /// Support branch, which keeps `swift test` hermetic unconditionally.
    /// Final fix wave: fires exactly once, the first time (if ever) `containerURL()` below takes
    /// the Application-Support fallback ON iOS — i.e. the `com.apple.security.application-groups`
    /// entitlement exists in source but ISN'T actually being honored at runtime (a mis-provisioned
    /// build/profile), as distinct from the `#if os(iOS)` guard's OWN documented fallback case
    /// (the un-sandboxed `swift test` macOS host, which never reaches this call at all). Silent
    /// before this fix: the app and the share extension would each quietly fall back to their own
    /// PROCESS-LOCAL Application Support directory, meaning nothing captured by one process is
    /// EVER visible to the other — indistinguishable from a subtle, silent data-loss bug unless
    /// someone happens to compare the two processes' sandboxes directly. `static let` (rather than
    /// a mutable `Bool` flag checked-then-set by the caller) so the one-time contract rides on
    /// Swift's own lazy-static single-initialization guarantee instead of hand-rolled
    /// synchronization — safe even if `containerURL()` is ever called concurrently from app and
    /// extension processes (each process gets its own one-time log, which is the correct behavior
    /// here: a warning per PROCESS that hit the fallback, not a single global warning). Log-only:
    /// no behavior change, and the fallback itself is unchanged.
    private static let logUnentitledFallbackOnce: Void = {
        os_log(.error, "App Group container unavailable — captures will not be shared between app and extension; check provisioning")
    }()

    public static func containerURL() -> URL {
        #if os(iOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        _ = logUnentitledFallbackOnce
        #endif
        return applicationSupportURL
    }

    /// `<container>/<component>/<uid-lowercased>` — the per-user scoping `Outbox` and
    /// `RecordingStore` both rely on to keep one account's on-disk state invisible to another
    /// after a sign-out/sign-in on the same device (see `Outbox.defaultDirectory`'s doc comment
    /// for the cross-account leak this closes).
    public static func userScopedURL(_ component: String, userId: UUID) -> URL {
        containerURL().appending(path: component).appending(path: userId.uuidString.lowercased())
    }

    /// Where `userScopedURL` resolved BEFORE this App Group container existed — plain
    /// Application Support, no App Group indirection (exactly `Outbox.defaultDirectory`'s formula
    /// prior to this task). Only ever differs from `userScopedURL` when the App Group entitlement
    /// is genuinely active (a real, entitled iOS run): an un-entitled process computes the
    /// IDENTICAL path for both, which is what makes `migrateLegacyDirectory` below a guaranteed
    /// no-op there.
    static func legacyUserScopedURL(_ component: String, userId: UUID) -> URL {
        applicationSupportURL.appending(path: component).appending(path: userId.uuidString.lowercased())
    }

    /// One-time, move-if-exists relocation for on-disk state that predates the App Group
    /// container. Dev-stage decision of record (Task 2 report): zero real users, so this is
    /// cheap insurance against silently orphaning a not-yet-drained Outbox entry or a
    /// not-yet-uploaded recording on the first launch that starts resolving `defaultDirectory` to
    /// the real App Group container instead of Application Support — NOT a general migration
    /// framework. No merge semantics: if `destination` already has anything, `legacy` is left
    /// untouched rather than clobbered (never destroys data); if `legacy` never existed, or the
    /// two paths are identical (the un-entitled case), this is a no-op. Cheap enough (one or two
    /// `fileExists` stats in the common case) to call unconditionally on every `defaultDirectory`
    /// resolution.
    ///
    /// Carried from the Task 2 review: the `fileExists`-then-`moveItem` sequence below is a
    /// check-then-act race with no lock, and this runs on every composer/recorder presentation
    /// (`defaultDirectory` is called on every access, not cached) — worst case, Plan 5 Task 5+
    /// puts the app and the share extension in separate PROCESSES that could both call this for
    /// the same user around the same first-launch-after-upgrading moment. Left unguarded rather
    /// than adding a lock, per the review's own judgment: low risk, not risk-free. Two overlapping
    /// callers can both pass the `fileExists` guard, but `moveItem` resolves to a single POSIX
    /// `rename()` of `legacy` — atomic at the filesystem level — so at most one caller's move can
    /// actually succeed; the other's `try?` just fails harmlessly once `legacy` is already gone.
    /// Also cited by the review: `legacy`/`destination` are per-user directories (UUID user-id
    /// segment), so two DIFFERENT users' migrations can never target the same path pair in the
    /// first place — only two callers racing to migrate the SAME user, the scenario above, are
    /// ever in play at all.
    ///
    /// That atomicity is also why a losing/failing caller is intentionally untested here: `legacy`
    /// is only ever removed by a `moveItem` call that itself succeeded, so a caller that loses the
    /// race (or hits any other `moveItem` failure) leaves `legacy` exactly as it was, and the next
    /// `defaultDirectory` call anywhere just retries the move. There's no way to force `moveItem`
    /// to fail partway through in a unit test without mocking `FileManager` itself, and the
    /// property that actually matters — source survives any failure — falls out of `moveItem`'s
    /// own all-or-nothing contract, not out of code written here.
    static func migrateLegacyDirectory(from legacy: URL, to destination: URL) {
        guard legacy != destination else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: destination.path) else { return }
        try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: legacy, to: destination)
    }
}
