import AVFoundation
import Foundation

/// Where a voice recording lives on local disk before (and, briefly, while) it's uploaded. The
/// app's recorder (Task 6) records straight to a `newRecordingURL()` — the file exists on disk
/// before there is ever a chance to talk to the network, which is the whole point of this type:
/// a crash, a dropped connection, or the app being force-quit mid-recording never loses the
/// audio. Getting the bytes to the server is the `Outbox`'s job (a `.file` entry whose payload
/// carries `local_file_path`, drained like any other queued capture) — `RecordingStore` only owns
/// where local `.m4a` files live and their lifecycle on disk, never the network.
public struct RecordingStore: Sendable {
    public var directory: URL

    /// `.../Application Support/StashRecordings/<uid-lowercased>` — same per-user isolation
    /// rationale as `Outbox.defaultDirectory(userId:)`: a shared, user-agnostic recordings
    /// directory would let a leftover local recording from one account surface in
    /// `pendingRecordings()` after a different account signs into the same device.
    ///
    /// `internal`, not `public`, so tests can assert the default path SHAPE (two uids -> two
    /// distinct paths, both under `StashRecordings`, suffixed with the lowercased uid) via
    /// `@testable import` without the side effect of `init` creating a real directory under the
    /// test machine's actual Application Support folder — same rationale as
    /// `OutboxTests.testPerUserDirectoriesAreIsolated`.
    ///
    /// Plan 5 Task 2: resolves through `AppGroup.userScopedURL` (App Group container when
    /// entitled, Application Support fallback otherwise) with the same one-time
    /// `AppGroup.migrateLegacyDirectory` insurance as `Outbox.defaultDirectory` — see that doc
    /// comment for the full rationale.
    static func defaultDirectory(userId: UUID) -> URL {
        let destination = AppGroup.userScopedURL("StashRecordings", userId: userId)
        AppGroup.migrateLegacyDirectory(from: AppGroup.legacyUserScopedURL("StashRecordings", userId: userId),
                                        to: destination)
        return destination
    }

    public init(userId: UUID, directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory(userId: userId)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// A fresh, never-reused local path for one recording, inside this store's directory.
    public func newRecordingURL() -> URL {
        directory.appending(path: "\(UUID().uuidString).m4a")
    }

    /// Local recording files not yet cleaned up — either still queued for upload (an `Outbox`
    /// entry references one by path) or orphaned by a crash before that entry was ever enqueued.
    /// Filters to regular files only: this directory should only ever hold `.m4a` recordings, but
    /// a stray subdirectory must never be handed back to a caller as if it were one.
    ///
    /// Task 4: this finally gets a caller for the orphan case above — `sweepOrphans`
    /// (`StagedFileStore.swift`) reads this exact list (alongside `StagedFileStore.pendingStaged`)
    /// and re-enqueues an `Outbox` entry for any file no pending entry's `local_file_path` already
    /// references, recovering a recording that was written to disk but never got that far.
    public func pendingRecordings() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
    }

    /// Deletes one local recording file — used once its bytes are durably elsewhere (uploaded via
    /// the Outbox) or the recording is abandoned before ever being enqueued (e.g. the user
    /// discards it in the composer).
    public func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// AAC, 44.1kHz mono, 64kbps — the `AVAudioRecorder` settings the app's recorder (Task 6) uses,
/// defined here (rather than in the app target) so StashKit and the app share one definition
/// instead of duplicating this dictionary.
///
/// A computed property, not a stored constant: `[String: Any]` isn't `Sendable`, and a stored
/// top-level `let` of a non-`Sendable` type would need an `unchecked`/`nonisolated(unsafe)` escape
/// hatch to be read from arbitrary isolation contexts (the app's recorder is likely to construct
/// its `AVAudioRecorder` off the main actor). A computed property sidesteps that entirely — it
/// builds a fresh, unshared dictionary on every access, so nothing is ever shared across
/// isolation domains and there is nothing to check.
public var voiceRecordingSettings: [String: Any] {
    [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
    ]
}
