import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Plan 15: the single image policy every iOS image capture goes through before upload — composer
/// photos and camera shots (`prepare(_:)`, `Data`-based, the composer already holds the bytes) and
/// share-extension images (`StagedFileStore.stagePreparedImage(from:)`, file-based).
///
/// Policy (plan Global Constraints, "Image preparation"):
/// - longest edge ≤ `maxLongestEdge` (2560 px), never upscaled;
/// - re-encoded as JPEG at `jpegQuality` (0.82), EXIF orientation applied to the pixels;
/// - every other piece of source metadata (GPS, device make/model, capture dates) is dropped —
///   the output is written from a bare `CGImage`, which carries none of it;
/// - transparency is composited onto white (JPEG has no alpha; left to the encoder, transparent
///   pixels come out platform-dependent — black on some ImageIO versions);
/// - two passthroughs keep the ORIGINAL pixels untouched: any GIF (re-encoding would drop the
///   animation) and a JPEG that is already ≤ 2560 px AND ≤ `passthroughJPEGMaxBytes` (2 MiB).
///   Plan 15 review: a passthrough JPEG that carries GPS gets it removed losslessly
///   (`CGImageDestinationCopyImageSource` + `kCGImageMetadataShouldExcludeGPS` — pixels,
///   orientation and every other tag untouched), because `stash-media` URLs are public. ImageIO
///   can't rewrite GIF metadata losslessly ("not supported for lossless metadata modification"),
///   so a GIF is kept exactly as-is — GPS in a GIF is rare (XMP only).
///
/// Decoding (plan 15 review, measured — see task-2-report.md): ImageIO's thumbnail generator
/// decodes the whole source for PNG/TIFF and for a JPEG whose DCT reduction can't reach the
/// target, so a very large source can cost several hundred MB — fatal under the share extension's
/// ~120 MB ceiling. `decodeStrategy` therefore routes a camera RAW to its embedded preview, and a
/// JPEG/PNG/TIFF over `largeImagePixelThreshold` to a subsampled decode
/// (`kCGImageSourceSubsampleFactor`, bounded to `subsampledDecodePixelBudget` pixels; orientation
/// applied by hand) — at the price of an output a little under 2560 px for such huge sources.
/// HEIC stays on the thumbnail path (its tiled decoder doesn't grow with image size).
///
/// ImageIO/CoreGraphics only (no UIKit) so the whole policy runs under `swift test` on the macOS
/// host exactly as it does in the app and the extension.
public enum ImagePreparation {
    public static let maxLongestEdge = 2560
    public static let jpegQuality: CGFloat = 0.82
    public static let passthroughJPEGMaxBytes = 2 * 1024 * 1024
    /// Above this many source pixels, a JPEG/PNG/TIFF is decoded subsampled (see type doc).
    public static let largeImagePixelThreshold = 50_000_000
    /// Most pixels a subsampled decode may produce (8 MP ≈ 32 MB of RGBA).
    static let subsampledDecodePixelBudget = 8 * 1024 * 1024
    /// A RAW's embedded preview is used when at least this long (or already the target size);
    /// a smaller one (a tiny EXIF thumbnail) would be a visible quality loss.
    static let minimumUsablePreviewEdge = 1024

    /// Bytes ready to stage/upload, plus how to label them.
    public struct PreparedImage: Sendable, Equatable {
        public let data: Data
        public let mimeType: String
        public let fileExtension: String
        /// `false` for the two passthrough cases (the pixels ARE the original's; a GPS strip is
        /// lossless and doesn't count as a re-encode).
        public let wasReencoded: Bool
    }

    /// What `plan(...)` decided for one image — exposed so the byte/pixel thresholds are testable
    /// without building multi-megabyte fixtures.
    public enum Plan: Equatable, Sendable {
        case passthrough(mimeType: String, fileExtension: String)
        case reencode(longestEdge: Int)
    }

    /// How a re-encoded image is decoded — see the type doc.
    public enum DecodeStrategy: Equatable, Sendable {
        /// ImageIO's thumbnail generator from the full image (orientation applied by ImageIO).
        case thumbnail
        /// A camera RAW: its embedded preview when usable, else the full decode.
        case embeddedPreview
        /// A huge JPEG/PNG/TIFF: decoded at 1/`factor` scale, then oriented and sized by hand.
        case subsampled(factor: Int)
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

    /// Pure decision — see `DecodeStrategy`. The subsample factor is the smallest of 2/4/8 that
    /// brings the decode within `subsampledDecodePixelBudget`.
    public static func decodeStrategy(typeIdentifier: String?, pixelWidth: Int, pixelHeight: Int) -> DecodeStrategy {
        guard let type = typeIdentifier.flatMap({ UTType($0) }) else { return .thumbnail }
        if type.conforms(to: .rawImage) { return .embeddedPreview }
        guard pixelWidth * pixelHeight > largeImagePixelThreshold,
              type.conforms(to: .jpeg) || type.conforms(to: .png) || type.conforms(to: .tiff) else { return .thumbnail }
        let factor = [2, 4, 8].first { (pixelWidth / $0) * (pixelHeight / $0) <= subsampledDecodePixelBudget } ?? 8
        return .subsampled(factor: factor)
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
                guard hasGPS(source) else {
                    return PreparedImage(data: data, mimeType: mimeType, fileExtension: fileExtension, wasReencoded: false)
                }
                let output = NSMutableData()
                if let type = CGImageSourceGetType(source),
                   let destination = CGImageDestinationCreateWithData(output, type, CGImageSourceGetCount(source), nil),
                   copyWithoutGPS(source, into: destination) {
                    return PreparedImage(data: output as Data, mimeType: mimeType, fileExtension: fileExtension,
                                         wasReencoded: false)
                }
                // No lossless rewrite: a GIF stays exactly as it is; a JPEG is re-encoded below
                // (which drops all metadata) rather than published with its location.
                if fileExtension == "gif" {
                    return PreparedImage(data: data, mimeType: mimeType, fileExtension: fileExtension, wasReencoded: false)
                }
                return reencoded(source, longestEdge: maxLongestEdge)
            case .reencode(let longestEdge):
                return reencoded(source, longestEdge: longestEdge)
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

    /// Never cache the full decode on the source — only the bounded output is ever kept.
    static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    /// `nil` when the source isn't a readable image (no type / no images).
    static func plan(for source: CGImageSource, byteCount: Int) -> Plan? {
        guard let type = CGImageSourceGetType(source) as String?, CGImageSourceGetCount(source) > 0 else { return nil }
        let (width, height, _) = headerInfo(source)
        return plan(typeIdentifier: type, pixelWidth: width, pixelHeight: height, byteCount: byteCount)
    }

    /// Re-encodes `source` per the policy (bounded decode, orientation, alpha → white, no metadata).
    private static func reencoded(_ source: CGImageSource, longestEdge: Int) -> PreparedImage? {
        guard let image = renderedImage(from: source, longestEdge: longestEdge) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil),
              encodeJPEG(image, into: destination) else { return nil }
        return PreparedImage(data: output as Data, mimeType: "image/jpeg", fileExtension: "jpg", wasReencoded: true)
    }

    /// Decodes per `decodeStrategy` to at most `longestEdge` px, EXIF orientation applied, as an
    /// opaque 8-bit image (alpha → white; grayscale/CMYK/16-bit/HDR → sRGB 8-bit).
    static func renderedImage(from source: CGImageSource, longestEdge: Int) -> CGImage? {
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let (width, height, orientation) = headerInfo(source)
        switch decodeStrategy(typeIdentifier: CGImageSourceGetType(source) as String?, pixelWidth: width, pixelHeight: height) {
        case .thumbnail:
            return thumbnail(source, index: index, longestEdge: longestEdge, alwaysFromFullImage: true)
                .flatMap(flattenedIfNeeded)
        case .embeddedPreview:
            if let preview = thumbnail(source, index: index, longestEdge: longestEdge, alwaysFromFullImage: false),
               max(preview.width, preview.height) >= min(longestEdge, minimumUsablePreviewEdge) {
                return flattenedIfNeeded(preview)
            }
            return thumbnail(source, index: index, longestEdge: longestEdge, alwaysFromFullImage: true)
                .flatMap(flattenedIfNeeded)
        case .subsampled(let factor):
            let options: [CFString: Any] = [kCGImageSourceSubsampleFactor: factor, kCGImageSourceShouldCache: false]
            guard let decoded = CGImageSourceCreateImageAtIndex(source, index, options as CFDictionary) else { return nil }
            return oriented(decoded, exifOrientation: orientation, longestEdge: longestEdge)
        }
    }

    /// Writes `image` as a quality-0.82 JPEG with NO properties dictionary beyond the quality —
    /// nothing from the source (GPS, TIFF make/model, EXIF dates) can reach the output because a
    /// `CGImage` carries no metadata of its own. Returns `false` if ImageIO couldn't finalize.
    static func encodeJPEG(_ image: CGImage, into destination: CGImageDestination) -> Bool {
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Whether the primary image carries GPS — the EXIF GPS dictionary or XMP `exif:GPS…` tags.
    static func hasGPS(_ source: CGImageSource) -> Bool {
        let index = CGImageSourceGetPrimaryImageIndex(source)
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
           properties[kCGImagePropertyGPSDictionary] != nil {
            return true
        }
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil) else { return false }
        return CGImageMetadataCopyTagWithPath(metadata, nil, "exif:GPSLatitude" as CFString) != nil
            || CGImageMetadataCopyTagWithPath(metadata, nil, "exif:GPSLongitude" as CFString) != nil
    }

    /// Losslessly copies `source` into `destination` (same type) minus every GPS tag, EXIF and XMP
    /// alike. The source's own metadata is passed explicitly: without it ImageIO drops ALL
    /// metadata, orientation included, and a sideways-stored photo would display sideways. This
    /// call finalizes `destination`. `false` when the format can't be rewritten losslessly (GIF).
    static func copyWithoutGPS(_ source: CGImageSource, into destination: CGImageDestination) -> Bool {
        var options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil) {
            options[kCGImageDestinationMetadata] = metadata
        }
        return CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil)
    }

    // MARK: - Private helpers

    private static func headerInfo(_ source: CGImageSource) -> (width: Int, height: Int, orientation: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil)
            as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (width, height, orientation)
    }

    private static func thumbnail(_ source: CGImageSource, index: Int, longestEdge: Int,
                                  alwaysFromFullImage: Bool) -> CGImage? {
        let options: [CFString: Any] = [
            alwaysFromFullImage ? kCGImageSourceCreateThumbnailFromImageAlways
                                : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    /// Draws `image` (stored pixels, before orientation) upright per EXIF `exifOrientation` 1–8,
    /// scaled to at most `longestEdge`, onto an opaque white 8-bit canvas — the subsampled path's
    /// equivalent of `kCGImageSourceCreateThumbnailWithTransform` + `flattenedIfNeeded`.
    static func oriented(_ image: CGImage, exifOrientation: Int, longestEdge: Int) -> CGImage? {
        let swapsAxes = (5...8).contains(exifOrientation)
        let uprightWidth = CGFloat(swapsAxes ? image.height : image.width)
        let uprightHeight = CGFloat(swapsAxes ? image.width : image.height)
        let scale = min(1, CGFloat(longestEdge) / max(uprightWidth, uprightHeight))
        let width = max(1, Int((uprightWidth * scale).rounded()))
        let height = max(1, Int((uprightHeight * scale).rounded()))
        guard let context = opaqueContext(width: width, height: height, like: image) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(canvas)
        context.interpolationQuality = .high

        // The classic EXIF → drawing transform (bottom-left origin): rotate into place, then
        // mirror for the "mirrored" orientations (2, 4, 5, 7).
        let w = CGFloat(width), h = CGFloat(height)
        var transform = CGAffineTransform.identity
        switch exifOrientation {
        case 3, 4: transform = transform.translatedBy(x: w, y: h).rotated(by: .pi)
        case 5, 8: transform = transform.translatedBy(x: w, y: 0).rotated(by: .pi / 2)
        case 6, 7: transform = transform.translatedBy(x: 0, y: h).rotated(by: -.pi / 2)
        default: break
        }
        switch exifOrientation {
        case 2, 4: transform = transform.translatedBy(x: w, y: 0).scaledBy(x: -1, y: 1)
        case 5, 7: transform = transform.translatedBy(x: h, y: 0).scaledBy(x: -1, y: 1)
        default: break
        }
        context.concatenate(transform)
        context.draw(image, in: swapsAxes ? CGRect(x: 0, y: 0, width: h, height: w) : canvas)
        return context.makeImage()
    }

    private static func flattenedIfNeeded(_ image: CGImage) -> CGImage? {
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        guard hasAlpha || !isPlainRGB(image.colorSpace) || image.bitsPerComponent != 8 else { return image }
        guard let context = opaqueContext(width: image.width, height: image.height, like: image) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// An opaque 8-bit RGB context: the source's own color space when it's plain SDR RGB (sRGB,
    /// Display P3, …), else sRGB.
    private static func opaqueContext(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let space = isPlainRGB(image.colorSpace) ? (image.colorSpace ?? sRGB) : sRGB
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    private static func isPlainRGB(_ space: CGColorSpace?) -> Bool {
        space.map { $0.model == .rgb && !CGColorSpaceUsesExtendedRange($0) && !CGColorSpaceUsesITUR_2100TF($0) } ?? false
    }
}
