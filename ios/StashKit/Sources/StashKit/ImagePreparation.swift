import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Plan 15: the single image policy every iOS image capture goes through before upload — composer
/// photos and camera shots (`prepare(_:)`, `Data`-based, the composer already holds the bytes) and
/// share-extension images (`StagedFileStore.stagePreparedImage(from:)`, file-based, bounded memory).
///
/// Policy (plan Global Constraints, "Image preparation"):
/// - longest edge ≤ `maxLongestEdge` (2560 px), never upscaled;
/// - re-encoded as JPEG at `jpegQuality` (0.82), EXIF orientation applied to the pixels;
/// - every other piece of source metadata (GPS, device make/model, capture dates) is dropped —
///   the output is written from a bare `CGImage`, which carries none of it;
/// - transparency is composited onto white (JPEG has no alpha; left to the encoder, transparent
///   pixels come out platform-dependent — black on some ImageIO versions);
/// - two passthroughs keep the ORIGINAL bytes untouched: any GIF (re-encoding would drop the
///   animation) and a JPEG that is already ≤ 2560 px AND ≤ `passthroughJPEGMaxBytes` (2 MiB) —
///   re-encoding that would only cost quality and time.
///
/// ImageIO/CoreGraphics only (no UIKit) so the whole policy runs under `swift test` on the macOS
/// host exactly as it does in the app and the extension. `kCGImageSourceCreateThumbnailAtIndex`
/// with `ThumbnailFromImageAlways` decodes straight to the target size, so peak memory is bounded
/// by the OUTPUT (≈ 2560² × 4 bytes), not by the source photo's own resolution.
public enum ImagePreparation {
    public static let maxLongestEdge = 2560
    public static let jpegQuality: CGFloat = 0.82
    public static let passthroughJPEGMaxBytes = 2 * 1024 * 1024

    /// Bytes ready to stage/upload, plus how to label them.
    public struct PreparedImage: Sendable, Equatable {
        public let data: Data
        public let mimeType: String
        public let fileExtension: String
        /// `false` for the two passthrough cases (the bytes ARE the original).
        public let wasReencoded: Bool
    }

    /// What `plan(...)` decided for one image — exposed so the byte/pixel thresholds are testable
    /// without building multi-megabyte fixtures.
    public enum Plan: Equatable, Sendable {
        case passthrough(mimeType: String, fileExtension: String)
        case reencode(longestEdge: Int)
    }

    /// Pure decision. `typeIdentifier` is ImageIO's `CGImageSourceGetType` (e.g. `public.jpeg`,
    /// `com.compuserve.gif`, `public.heic`); pixel sizes are the RAW (pre-orientation) header
    /// values — rotation never changes the longest edge.
    public static func plan(typeIdentifier: String?, pixelWidth: Int, pixelHeight: Int, byteCount: Int) -> Plan {
        let type = typeIdentifier.flatMap { UTType($0) }
        if let type, type.conforms(to: .gif) {
            return .passthrough(mimeType: "image/gif", fileExtension: "gif")
        }
        let longest = max(pixelWidth, pixelHeight)
        if let type, type.conforms(to: .jpeg),
           longest > 0, longest <= maxLongestEdge, byteCount <= passthroughJPEGMaxBytes {
            return .passthrough(mimeType: "image/jpeg", fileExtension: "jpg")
        }
        // Unknown dimensions (a header ImageIO couldn't size) still get the cap — the thumbnail
        // generator never upscales, so asking for 2560 on a smaller image returns it at its own size.
        return .reencode(longestEdge: longest > 0 ? min(longest, maxLongestEdge) : maxLongestEdge)
    }

    /// `Data`-based preparation for the composer. `nil` when ImageIO can't read the bytes as an
    /// image at all (or can't re-encode them) — the caller keeps the original bytes in that case
    /// rather than dropping the attachment.
    public static func prepare(_ data: Data) -> PreparedImage? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                  let plan = plan(for: source, byteCount: data.count) else { return nil }
            switch plan {
            case .passthrough(let mimeType, let fileExtension):
                return PreparedImage(data: data, mimeType: mimeType, fileExtension: fileExtension, wasReencoded: false)
            case .reencode(let longestEdge):
                guard let image = renderedImage(from: source, longestEdge: longestEdge) else { return nil }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
                guard encodeJPEG(image, into: destination) else { return nil }
                return PreparedImage(data: output as Data, mimeType: "image/jpeg", fileExtension: "jpg", wasReencoded: true)
            }
        }
    }

    /// The original filename to record in `attributes.media.file_name` (and to send as the
    /// capture's `file_name`): unchanged for a passthrough, extension swapped (or appended) to
    /// `.jpg` when the bytes were re-encoded — "IMG_1234.HEIC" → "IMG_1234.jpg", "IMG_1234" →
    /// "IMG_1234.jpg". `nil`/empty in → `nil` out (a camera shot has no source name).
    public static func fileName(_ original: String?, reencoded: Bool) -> String? {
        guard let original, !original.isEmpty else { return nil }
        guard reencoded else { return original }
        let base = (original as NSString).deletingPathExtension
        return (base.isEmpty ? original : base) + ".jpg"
    }

    // MARK: - Shared ImageIO plumbing (also used by `StagedFileStore.stagePreparedImage`)

    /// Never cache the full decode on the source — only the bounded thumbnail is ever decoded.
    static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    /// `nil` when the source isn't a readable image (no type / no images).
    static func plan(for source: CGImageSource, byteCount: Int) -> Plan? {
        guard let type = CGImageSourceGetType(source) as String?, CGImageSourceGetCount(source) > 0 else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        return plan(typeIdentifier: type, pixelWidth: width, pixelHeight: height, byteCount: byteCount)
    }

    /// Bounded decode at `longestEdge`, EXIF orientation applied, then flattened to opaque 8-bit
    /// RGB when needed (alpha → white; grayscale/CMYK/16-bit/HDR → sRGB 8-bit).
    static func renderedImage(from source: CGImageSource, longestEdge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { return nil }
        return flattenedIfNeeded(thumbnail)
    }

    /// Writes `image` as a quality-0.82 JPEG with NO properties dictionary beyond the quality —
    /// nothing from the source (GPS, TIFF make/model, EXIF dates) can reach the output because a
    /// `CGImage` carries no metadata of its own. Returns `false` if ImageIO couldn't finalize.
    static func encodeJPEG(_ image: CGImage, into destination: CGImageDestination) -> Bool {
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func flattenedIfNeeded(_ image: CGImage) -> CGImage? {
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let space = image.colorSpace
        let isPlainRGB = space.map { $0.model == .rgb && !CGColorSpaceUsesExtendedRange($0) && !CGColorSpaceUsesITUR_2100TF($0) } ?? false
        guard hasAlpha || !isPlainRGB || image.bitsPerComponent != 8 else { return image }

        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let targetSpace = isPlainRGB ? (space ?? sRGB) : sRGB
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: targetSpace,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ?? CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                         bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
