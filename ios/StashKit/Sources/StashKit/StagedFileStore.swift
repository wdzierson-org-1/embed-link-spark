import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Thrown by `StagedFileStore.stageDownscaledImage` — the two ImageIO failure shapes that call
/// can hit, kept as an `Error` (not just `throws Never`/a generic message) so callers can tell
/// "not a readable image at all" apart from "opened, but the resize/encode step itself failed."
public enum StagedFileStoreError: Error, Equatable, Sendable {
    /// `CGImageSourceCreateWithURL` couldn't open `source` — missing, corrupt, or not an image
    /// format ImageIO recognizes.
    case cannotReadImage
    /// The source opened, but ImageIO couldn't produce a thumbnail, or couldn't finalize the JPEG
    /// destination (e.g. an unwritable staging directory).
    case downscaleFailed
}

/// Where a shared/staged file lives on local disk before it's uploaded — the Plan 5 generalization
/// of Plan 3's `RecordingStore` pattern (durable-on-disk-before-any-network-call) to every kind of
/// file this plan's share extension can receive, not just voice recordings. Getting bytes to the
/// server is still the `Outbox`'s job (a `.file` entry whose payload carries `local_file_path`,
/// exactly like a recording) — `StagedFileStore` only owns where staged files live and their
/// lifecycle on disk, never the network.
///
/// Global Constraints' memory ceiling (share extension, ~120 MB) is why every method here is
/// either a `FileManager` metadata/copy call or an ImageIO bounded-decode call — nothing on this
/// type ever reads a whole file into an in-memory `Data` value.
public struct StagedFileStore: Sendable {
    public var directory: URL

    /// `.../Application Support/StashStaging/<uid-lowercased>` (App Group container when
    /// entitled — see `AppGroup.userScopedURL`). Unlike `Outbox.defaultDirectory`/
    /// `RecordingStore.defaultDirectory`, there is no pre-App-Group "legacy" location to migrate
    /// from: this type is brand new in Task 4, so every install is already App-Group-aware from
    /// its very first write.
    static func defaultDirectory(userId: UUID) -> URL {
        AppGroup.userScopedURL("StashStaging", userId: userId)
    }

    public init(userId: UUID, directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory(userId: userId)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Copies `source` into this store under a fresh, never-reused name. `FileManager.copyItem` is
    /// a kernel-level file copy — it never brings the file's bytes into this process as `Data`,
    /// which is the whole point (a shared file handed to the extension via
    /// `NSItemProvider.loadFileRepresentation` must move straight from its temp URL onto durable
    /// local disk without ever being fully read into memory).
    public func stage(from source: URL, fileExtension: String) throws -> URL {
        let destination = directory.appending(path: "\(UUID().uuidString).\(fileExtension.lowercased())")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Downscales an image to at most `maxDimension` pixels on its longest side, re-encoded as
    /// JPEG at `quality`, written straight to a staged file. Uses ImageIO's thumbnail generator
    /// rather than "decode the full image, then redraw it scaled" (an ordinary `CGImage`/`UIImage`
    /// resize): `CGImageSourceCreateThumbnailAtIndex` can produce a downsampled decode directly
    /// from the source's compressed bytes for common formats, so this call's peak memory is
    /// bounded by the OUTPUT size, not the input's — a 50 MP photo shared from Photos never costs
    /// anywhere near its full decoded size here. `kCGImageSourceCreateThumbnailFromImageAlways`
    /// forces that path even when a smaller embedded thumbnail already exists (which could be
    /// smaller than `maxDimension` and defeat the caller's own size intent);
    /// `kCGImageSourceCreateThumbnailWithTransform` applies the source's EXIF orientation so a
    /// sideways phone photo doesn't end up staged sideways.
    ///
    /// No UIKit anywhere in this call (`StashKit` has none, and never will) — CoreGraphics/ImageIO
    /// only, so this runs identically under `swift test`'s macOS host and the real iOS app/
    /// extension.
    public func stageDownscaledImage(from source: URL, maxDimension: CGFloat, quality: CGFloat) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw StagedFileStoreError.cannotReadImage
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
            throw StagedFileStoreError.downscaleFailed
        }

        let destination = directory.appending(path: "\(UUID().uuidString).jpg")
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw StagedFileStoreError.downscaleFailed
        }
        let destinationOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(imageDestination, thumbnail, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw StagedFileStoreError.downscaleFailed
        }
        return destination
    }

    /// Staged files not yet cleaned up — either still queued for upload (an `Outbox` entry
    /// references one by path) or orphaned by a crash before that entry was ever enqueued
    /// (`sweepOrphans` below recovers those). Filters to regular files only, same rationale as
    /// `RecordingStore.pendingRecordings()`.
    public func pendingStaged() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
    }

    /// Deletes one staged file — used once its bytes are durably elsewhere (uploaded via the
    /// Outbox) or the share is abandoned before ever being enqueued (e.g. the user cancels the
    /// share sheet).
    public func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// File size straight from filesystem attributes — never opens/reads the file's content.
    public func fileSize(of url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }
}

/// Small extension → MIME map for `sweepOrphans` below, which (unlike every other `.file` entry,
/// always enqueued alongside an explicit `mime_type` by whichever picker/recorder produced it) has
/// no source of truth for a recovered orphan's content type beyond its file extension. Falls back
/// to `application/octet-stream` for anything unrecognized — the same fallback
/// `Outbox.drain`/`send` already use for a `mime_type`-less payload — rather than skipping the
/// file: tagging it generically still gets its bytes durably queued, where dropping it silently
/// would not.
private func mimeType(forFileExtension fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "m4a": return "audio/mp4"
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "heic": return "image/heic"
    case "mp4": return "video/mp4"
    case "mov": return "video/quicktime"
    case "pdf": return "application/pdf"
    default: return "application/octet-stream"
    }
}

/// Files younger than this are skipped by `sweepOrphans` — may still be mid-write (a recording in
/// progress, a share-extension stage whose Outbox entry hasn't been enqueued yet) rather than
/// truly orphaned. `Outbox.sweepOrphanClaims` uses the same duration for its own, unrelated
/// young-file skip (stray `.claim` sidecars) — see that method's doc comment for why they're
/// deliberately the same number without being the same mechanism.
private let orphanSweepGracePeriod: TimeInterval = 60

/// Recovers files in `recordings`/`staging` that have no Outbox entry pointing at them — the
/// generalization of `RecordingStore.pendingRecordings()`'s long-documented "orphaned by a crash"
/// case (which nothing ever actually acted on before this task) to every local-file producer this
/// plan adds, not just voice recordings. Matches purely on `local_file_path` string equality
/// against every currently-pending entry's payload — a file with no entry whose `local_file_path`
/// equals its path gains one; a file that already has one is left alone.
///
/// Idempotent by construction: the entry this creates carries `local_file_path` set to the exact
/// file it recovered, so a second sweep sees that file as already-referenced and skips it — no
/// separate bookkeeping (a "swept" marker, a moved/renamed file, …) is needed to avoid
/// double-creating entries for the same orphan. New entries default to `is_public: "false"` and
/// carry no `content`/`attributes` — there is no user-provided context left to recover for a file
/// whose original capture attempt never got that far.
///
/// Also cleans up a second, unrelated crash artifact while it's here (Task 3 review carry, folded
/// in per the brief): stray `Outbox` `.claim` sidecars whose entry is already gone (a process
/// killed between deleting a sent/dropped entry's `.json` and releasing its claim). See
/// `Outbox.sweepOrphanClaims` for that half's own rules — disclosed: its count is deliberately NOT
/// folded into this function's return value, since the documented contract here is "entries
/// created," and deleting an inert claim file creates nothing.
///
/// - Parameter now: Injectable for tests (same pattern as `Outbox.init`/`drain`'s stale-claim
///   clock — not part of the brief's literal printed signature; added because the 60s young-file
///   skip below needs a controllable clock to test at all). Production call sites take the
///   default, real `Date()`.
public func sweepOrphans(userId: UUID, outbox: Outbox, recordings: RecordingStore, staging: StagedFileStore,
                         now: @Sendable () -> Date = { Date() }) async -> Int {
    let referencedPaths = Set(await outbox.pending().compactMap { $0.payload["local_file_path"] })
    let candidates = recordings.pendingRecordings() + staging.pendingStaged()

    var created = 0
    for url in candidates {
        guard !referencedPaths.contains(url.path) else { continue }
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              now().timeIntervalSince(modified) >= orphanSweepGracePeriod else { continue }

        let payload = [
            "local_file_path": url.path,
            "mime_type": mimeType(forFileExtension: url.pathExtension),
            "is_public": "false",
        ]
        if (try? await outbox.enqueue(.file, payload: payload)) != nil {
            created += 1
        }
    }

    _ = await outbox.sweepOrphanClaims(now: now)
    return created
}
