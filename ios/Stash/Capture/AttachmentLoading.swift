import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import PhotosUI
import StashKit
import SwiftUI
import UniformTypeIdentifiers

/// A chip standing in for a pick that is still loading (plan 15 6D, M7): the attachments row shows
/// a spinner in its place until the bytes and thumbnail are ready, and its × abandons the pick.
struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
}

/// A pick that is ready for the composer: `CaptureViewModel`'s bytes and metadata, plus the chip
/// thumbnail, decoded once at the chip's own pixel size (`nil` for non-images, or an image ImageIO
/// can't read — the chip then shows the file icon and name).
struct LoadedAttachment: Sendable {
    let attachment: CaptureAttachment
    let thumbnail: UIImage?
}

/// Why a pick didn't attach. Every failure reaches the user as one toast per pick batch
/// (`toastMessage(for:noun:)`) — a pick is never dropped silently.
enum AttachmentLoadFailure: Error, Equatable {
    /// Over `CaptureAttachment.byteLimit` — refused from the file size, before reading the bytes.
    case tooLarge(name: String, limitMB: Int)
    /// The transfer or the read failed (a revoked security scope, an iCloud download that
    /// failed, bytes the photo picker couldn't deliver…). `name` is `nil` for photo picks.
    case unreadable(name: String?)

    /// One toast for a batch's failures, or `nil` when there were none. `noun` names what was
    /// picked ("photo" / "file").
    static func toastMessage(for failures: [AttachmentLoadFailure], noun: String) -> String? {
        guard let first = failures.first else { return nil }
        guard failures.count == 1 else {
            let allTooLarge = failures.allSatisfy { if case .tooLarge = $0 { true } else { false } }
            return "Couldn't add \(failures.count) \(noun)s" + (allTooLarge ? " — over the size limit" : "")
        }
        switch first {
        case .tooLarge(let name, let limitMB):
            return "Couldn't add “\(name)” — it's over the \(limitMB) MB limit"
        case .unreadable(let name?):
            return "Couldn't add “\(name)”"
        case .unreadable(nil):
            return "Couldn't add that \(noun)"
        }
    }
}

typealias AttachmentLoadResult = Result<LoadedAttachment, AttachmentLoadFailure>

/// Loads composer picks OFF the main actor (plan 15 6D, M7). The heavy, synchronous parts —
/// reading a picked file (a video can be 100 MB), encoding a camera JPEG, decoding a thumbnail —
/// always run inside `Task.detached`, so typing, scrolling and the Save button never wait on them.
/// Only the asynchronous calls (the photo picker's out-of-process transfer, AVFoundation's
/// duration probe) are awaited directly.
enum ComposerAttachmentLoader {
    /// PhotosPicker: ONE transfer per photo — the system's file copy of the asset, which also
    /// carries the asset's original filename (`attributes.media.file_name`). Only when that
    /// transfer fails does this fall back to the plain `Data` transfer (the bytes, no filename),
    /// so a photo that can't be delivered as a file still attaches.
    static func photo(_ item: PhotosPickerItem, chipPixels: Int) async -> AttachmentLoadResult {
        let fallbackType = item.supportedContentTypes.first
        if let picked = try? await item.loadTransferable(type: PickedPhotoFile.self) {
            return await Task.detached(priority: .userInitiated) { () -> AttachmentLoadResult in
                defer { try? FileManager.default.removeItem(at: picked.url) }
                guard let data = try? Data(contentsOf: picked.url) else { return .failure(.unreadable(name: nil)) }
                let type = UTType(filenameExtension: picked.url.pathExtension) ?? fallbackType
                return .success(photoAttachment(data: data, type: type, fileName: picked.originalName,
                                                chipPixels: chipPixels))
            }.value
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return .failure(.unreadable(name: nil))
        }
        return await Task.detached(priority: .userInitiated) { () -> AttachmentLoadResult in
            .success(photoAttachment(data: data, type: fallbackType, fileName: nil, chipPixels: chipPixels))
        }.value
    }

    /// `fileImporter`: the security-scoped file is read inside a detached task (and refused from
    /// its size alone when it's over `CaptureAttachment.byteLimit`); audio and video get their
    /// duration probed (`attributes.media.duration_s`) while the scope is still open.
    static func file(at url: URL, chipPixels: Int) async -> AttachmentLoadResult {
        await Task.detached(priority: .userInitiated) { () -> AttachmentLoadResult in
            // `false` for a URL that needs no scope (e.g. inside the app's own container) — the
            // read below decides whether the file is actually readable.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let name = url.lastPathComponent
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
            let type = UTType(filenameExtension: ext)
            let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
            let kind: CaptureAttachment.Kind = (type?.conforms(to: .image) ?? false) ? .photo : .file
            let limit = CaptureAttachment.byteLimit(kind: kind, mimeType: mimeType)
            if let limit, let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > limit {
                return .failure(.tooLarge(name: name, limitMB: limit / 1_048_576))
            }

            CaptureTestHooks.simulateSlowAttachmentLoad()
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable(name: name)) }
            if let limit, data.count > limit {   // the size attribute was missing or stale
                return .failure(.tooLarge(name: name, limitMB: limit / 1_048_576))
            }
            let durationS = (type?.conforms(to: .audiovisualContent) ?? false) ? await probeDuration(url: url) : nil
            let attachment = CaptureAttachment(data: data, fileExtension: ext, mimeType: mimeType, kind: kind,
                                               fileName: name, durationS: durationS)
            let thumbnail = kind == .photo ? AttachmentThumbnail.make(from: data, chipPixels: chipPixels) : nil
            return .success(LoadedAttachment(attachment: attachment, thumbnail: thumbnail))
        }.value
    }

    /// The camera: the JPEG encode (a few hundred ms for a 12 MP shot) runs off the main thread.
    /// A fresh capture has no source filename (`fileName` stays nil). `jpegData` records the
    /// image's orientation as EXIF; `ImagePreparation` applies it (and resizes) at save time, and
    /// the thumbnail applies it here.
    static func cameraPhoto(_ image: UIImage, chipPixels: Int) async -> AttachmentLoadResult {
        await Task.detached(priority: .userInitiated) { () -> AttachmentLoadResult in
            guard let data = image.jpegData(compressionQuality: 0.9) else { return .failure(.unreadable(name: nil)) }
            return .success(photoAttachment(data: data, fileExtension: "jpg", mimeType: "image/jpeg", fileName: nil,
                                            chipPixels: chipPixels))
        }.value
    }

    /// Detached tasks only — decodes the thumbnail.
    private static func photoAttachment(data: Data, type: UTType?, fileName: String?, chipPixels: Int) -> LoadedAttachment {
        photoAttachment(data: data, fileExtension: type?.preferredFilenameExtension ?? "jpg",
                        mimeType: type?.preferredMIMEType ?? "image/jpeg", fileName: fileName, chipPixels: chipPixels)
    }

    private static func photoAttachment(data: Data, fileExtension: String, mimeType: String, fileName: String?,
                                        chipPixels: Int) -> LoadedAttachment {
        CaptureTestHooks.simulateSlowAttachmentLoad()
        let attachment = CaptureAttachment(data: data, fileExtension: fileExtension, mimeType: mimeType,
                                           kind: .photo, fileName: fileName)
        return LoadedAttachment(attachment: attachment,
                                thumbnail: AttachmentThumbnail.make(from: data, chipPixels: chipPixels))
    }

    /// `AVAsset` duration probe for a picked audio/video file (Task 5) — any failure (a corrupt
    /// file, an asset AVFoundation can't parse) is a graceful `nil`, never a failed attach;
    /// `durationS` is optional everywhere downstream for exactly this reason.
    private static func probeDuration(url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

/// Chip thumbnails (M7, snappiness #5): decoded ONCE per pick, off the main thread, at the chip's
/// pixel size — never a full-resolution `UIImage(data:)` (~48 MB decoded per 12 MP photo) redone
/// every time the attachments row re-renders. EXIF orientation applied.
enum AttachmentThumbnail {
    /// The chip is a square the image fills edge to edge (`.aspectRatio(contentMode: .fill)`), so
    /// the image's SHORT edge must cover `chipPixels`; ImageIO's max pixel size bounds the LONG
    /// edge, hence the aspect scale-up — capped at 4× so a panorama can't balloon. Unknown
    /// dimensions get 2×.
    static func maxPixelSize(chipPixels: Int, pixelWidth: Int, pixelHeight: Int) -> Int {
        let long = max(pixelWidth, pixelHeight), short = min(pixelWidth, pixelHeight)
        guard short > 0 else { return chipPixels * 2 }
        let needed = Int((Double(chipPixels) * Double(long) / Double(short)).rounded(.up))
        return min(max(needed, chipPixels), chipPixels * 4)
    }

    static func make(from data: Data, chipPixels: Int) -> UIImage? {
        autoreleasepool { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) > 0 else { return nil }
            let index = CGImageSourceGetPrimaryImageIndex(source)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            // A camera RAW carries an embedded preview — use it rather than developing the RAW
            // (slow, and hundreds of MB) for a chip. Everything else decodes from the image itself,
            // so a small EXIF thumbnail can't make the chip blurry.
            let isRAW = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }?.conforms(to: .rawImage) ?? false
            let decodeFrom = isRAW ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways
            let options: [CFString: Any] = [
                decodeFrom: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(chipPixels: chipPixels, pixelWidth: width,
                                                                  pixelHeight: height),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary).map { UIImage(cgImage: $0) }
        }
    }
}

/// PhotosPicker's file-based transfer (`FileRepresentation`). The delivered file is only valid
/// inside the importing closure, so it's copied out (a clone on APFS — no bytes read) to a
/// temporary file the loader reads off the main thread and then deletes. `.image` (not `.item`):
/// a Live Photo then delivers its still image rather than its bundle.
private struct PickedPhotoFile: Transferable, Sendable {
    let url: URL
    /// The asset's original filename, e.g. "IMG_1234.HEIC".
    let originalName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let copy = URL.temporaryDirectory.appending(path: UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy, originalName: received.file.lastPathComponent)
        }
    }
}
