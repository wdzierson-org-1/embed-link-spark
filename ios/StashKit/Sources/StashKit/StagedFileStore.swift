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

    /// Small extension → MIME map. Originally private, for `sweepOrphans` below alone (which —
    /// unlike every other `.file` entry, always enqueued alongside an explicit `mime_type` by
    /// whichever picker/recorder produced it — has no source of truth for a recovered orphan's
    /// content type beyond its file extension). Made `public` (Task 7 fix round, Critical review
    /// finding) so a cross-MODULE caller — the share extension's `ProviderLoader` — can reuse this
    /// EXACT map instead of re-deriving mime types from `UTType(typeIdentifier:)`'s ABSTRACT
    /// category constants (`public.image`/`public.movie`/`public.audio`): verified empirically that
    /// `.preferredMIMEType` returns `nil` for those (only a concrete type like `com.adobe.pdf`
    /// resolves), which was silently mislabeling every shared PNG/movie/voice-memo as
    /// `application/octet-stream` — wrong DB `type` server-side, no analyze-image/transcribe-audio
    /// enrichment. A `static` method on `StagedFileStore` (not a bare top-level function) so the
    /// public API reads clearly at that cross-module call site:
    /// `StagedFileStore.mimeType(forFileExtension:)`. Falls back to `application/octet-stream` for
    /// anything unrecognized — the same fallback `Outbox.drain`/`send` already use for a
    /// `mime_type`-less payload — rather than skipping the file: tagging it generically still gets
    /// its bytes durably queued/registered, where dropping it silently would not.
    ///
    /// Widened in Task 7 fix round 2 to also cover gif/webp (images) and mp3/wav (audio) — cheap,
    /// low-risk additions to the same map under the same fallback contract; not tied to any
    /// specific bug, just closing an easy gap while this map was already under review.
    public static func mimeType(forFileExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

/// Files younger than this are skipped by `sweepOrphans` — may still be mid-write (a recording in
/// progress, a share-extension stage whose Outbox entry hasn't been enqueued yet) rather than
/// truly orphaned. `Outbox.sweepOrphanClaims` uses the same duration for its own, unrelated
/// young-file skip (stray `.claim` sidecars) — see that method's doc comment for why they're
/// deliberately the same number without being the same mechanism.
private let orphanSweepGracePeriod: TimeInterval = 60

/// Canonicalizes a file path so `sweepOrphans` can compare two INDEPENDENTLY-constructed spellings
/// of the same file (Fix round 1, Important review finding). `FileManager.contentsOfDirectory`
/// reports paths with every symlink in their directory chain already resolved — on macOS, `/var`
/// (and `/tmp`, `/etc`) is itself a symlink to `/private/var`, so a `candidates` entry from a
/// listing can read `/private/var/folders/...` while the IDENTICAL file's path as written into an
/// Outbox payload (`RecordingStore.newRecordingURL`, `StagedFileStore.stage`, and
/// `CaptureViewModel`'s own recording path — all built by plain `URL.appending(path:)` on a
/// directory that was never listed) reads `/var/folders/...`. A raw string compare between the two
/// spellings of one inode would read a genuinely-pending file as unreferenced and mint a duplicate
/// entry for it — the exact cross-process double-upload hazard T5+'s claim protocol exists to
/// prevent, since the sweep-created duplicate has no claim relationship to the original at all.
///
/// `resolvingSymlinksInPath()` closes this specifically for `/private/var`↔`/var` (and `/tmp`,
/// `/etc`): empirically verified (not just assumed) to collapse `/private/var/...` DOWN to
/// `/var/...` — the reverse of naive symlink resolution, and Apple's documented special case for
/// exactly these three top-level BSD symlinks — while being a no-op on a path that's already in
/// the short form. Applying it to both sides makes them converge on the same string either way.
private func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

/// Recovers files in `recordings`/`staging` that have no Outbox entry pointing at them — the
/// generalization of `RecordingStore.pendingRecordings()`'s long-documented "orphaned by a crash"
/// case (which nothing ever actually acted on before this task) to every local-file producer this
/// plan adds, not just voice recordings. Matches on `local_file_path` equality (via `canonicalPath`
/// above, not raw string equality — Fix round 1) against every currently-pending entry's payload —
/// a file with no entry whose `local_file_path` names it gains one; a file that already has one is
/// left alone.
///
/// Idempotent by construction: the entry this creates carries `local_file_path` set to the
/// (canonicalized) file it recovered, so a second sweep sees that file as already-referenced and
/// skips it — no separate bookkeeping (a "swept" marker, a moved/renamed file, …) is needed to
/// avoid double-creating entries for the same orphan. New entries default to `is_public: "false"`
/// and carry no `content`/`attributes` — there is no user-provided context left to recover for a
/// file whose original capture attempt never got that far.
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
    let referencedPaths = Set(await outbox.pending().compactMap { $0.payload["local_file_path"] }.map(canonicalPath))
    let candidates = recordings.pendingRecordings() + staging.pendingStaged()

    var created = 0
    for url in candidates {
        let path = canonicalPath(url.path)
        guard !referencedPaths.contains(path) else { continue }
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              now().timeIntervalSince(modified) >= orphanSweepGracePeriod else { continue }

        let payload = [
            "local_file_path": path,
            "mime_type": StagedFileStore.mimeType(forFileExtension: url.pathExtension),
            "is_public": "false",
        ]
        if (try? await outbox.enqueue(.file, payload: payload)) != nil {
            created += 1
        }
    }

    _ = await outbox.sweepOrphanClaims(now: now)
    return created
}
