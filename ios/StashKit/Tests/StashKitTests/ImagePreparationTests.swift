import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import StashKit

/// Plan 15 image policy — see `ImagePreparation`'s doc comment. Fixtures are built with ImageIO
/// (StashKit has no UIKit), and outputs are decoded back to check pixels, sizes, and metadata.
final class ImagePreparationTests: XCTestCase {
    private let red: (CGFloat, CGFloat, CGFloat) = (1, 0, 0)
    private let blue: (CGFloat, CGFloat, CGFloat) = (0, 0, 1)

    // MARK: - Size cap

    func testDownscalesLongestEdgeTo2560AndReencodesAsJPEG() throws {
        let source = try encodeImages([makeSplitImage(width: 3000, height: 1200, left: red, right: blue)], as: .png)

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        XCTAssertTrue(prepared.wasReencoded)
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.fileExtension, "jpg")
        let output = try XCTUnwrap(decodeImage(prepared.data))
        XCTAssertEqual(output.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(max(output.width, output.height), 2560, "longest edge must be capped at exactly 2560")
        XCTAssertEqual(output.width, 2560)
        XCTAssertEqual(output.height, 1024, "aspect ratio preserved (3000x1200 → 2560x1024)")
    }

    func testNeverUpscalesASmallNonJPEG() throws {
        let source = try encodeImages([makeSplitImage(width: 300, height: 120, left: red, right: blue)], as: .png)

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        XCTAssertTrue(prepared.wasReencoded, "a PNG is always re-encoded to JPEG, whatever its size")
        let output = try XCTUnwrap(decodeImage(prepared.data))
        XCTAssertEqual(output.width, 300)
        XCTAssertEqual(output.height, 120)
    }

    // MARK: - Orientation

    /// Stored 2600x100, left half red / right half blue, EXIF orientation 6 ("rotate 90° CW to
    /// display"). Displayed, the stored left edge becomes the TOP: 100 wide x 2600 tall, top half
    /// red, bottom half blue — then capped to 2560 tall. The output must carry that rotation in
    /// its pixels (it has no orientation tag left to rely on).
    func testAppliesEXIFOrientationToThePixels() throws {
        let stored = try makeSplitImage(width: 2600, height: 100, left: red, right: blue)
        let source = try encodeImages([stored], as: .jpeg, properties: [kCGImagePropertyOrientation: 6])

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        let output = try XCTUnwrap(decodeImage(prepared.data))
        XCTAssertLessThan(output.width, output.height, "portrait after applying orientation 6")
        XCTAssertEqual(output.height, 2560)
        let orientation = (output.properties[kCGImagePropertyOrientation] as? Int) ?? 1
        XCTAssertEqual(orientation, 1, "no orientation left for a viewer to apply twice")
        assertColor(pixel(output.image, x: output.image.width / 2, y: 100), (255, 0, 0), "top must be red")
        assertColor(pixel(output.image, x: output.image.width / 2, y: output.image.height - 100), (0, 0, 255),
                    "bottom must be blue")
    }

    // MARK: - Passthroughs

    func testSmallJPEGPassesThroughByteForByte() throws {
        let source = try encodeImages([makeSplitImage(width: 800, height: 600, left: red, right: blue)], as: .jpeg,
                                      properties: [kCGImageDestinationLossyCompressionQuality: 0.9])
        XCTAssertLessThan(source.count, ImagePreparation.passthroughJPEGMaxBytes)

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        XCTAssertFalse(prepared.wasReencoded)
        XCTAssertEqual(prepared.data, source, "a ≤2560px, ≤2MiB JPEG must be kept untouched")
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.fileExtension, "jpg")
    }

    func testAnimatedGIFPassesThroughByteForByte() throws {
        let frames = [try makeSplitImage(width: 40, height: 40, left: red, right: blue),
                      try makeSplitImage(width: 40, height: 40, left: blue, right: red)]
        let source = try encodeImages(frames, as: .gif)

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        XCTAssertFalse(prepared.wasReencoded)
        XCTAssertEqual(prepared.data, source, "re-encoding a GIF would drop its animation")
        XCTAssertEqual(prepared.mimeType, "image/gif")
        XCTAssertEqual(prepared.fileExtension, "gif")
    }

    /// The byte and pixel thresholds, via the pure decision (no multi-megabyte fixtures).
    func testPlanThresholds() {
        let jpeg = UTType.jpeg.identifier
        let twoMiB = ImagePreparation.passthroughJPEGMaxBytes
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: jpeg, pixelWidth: 2560, pixelHeight: 1920, byteCount: twoMiB),
                       .passthrough(mimeType: "image/jpeg", fileExtension: "jpg"), "both limits are inclusive")
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: jpeg, pixelWidth: 2000, pixelHeight: 1500, byteCount: twoMiB + 1),
                       .reencode(longestEdge: 2000), "a JPEG over 2 MiB is re-encoded at its own size")
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: jpeg, pixelWidth: 4032, pixelHeight: 3024, byteCount: 1_000),
                       .reencode(longestEdge: 2560))
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: jpeg, pixelWidth: 1000, pixelHeight: 2561, byteCount: 1_000),
                       .reencode(longestEdge: 2560))
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: UTType.heic.identifier, pixelWidth: 800, pixelHeight: 600, byteCount: 1_000),
                       .reencode(longestEdge: 800), "HEIC is always converted (browsers/vision APIs can't read it)")
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: UTType.gif.identifier, pixelWidth: 5000, pixelHeight: 5000, byteCount: 50_000_000),
                       .passthrough(mimeType: "image/gif", fileExtension: "gif"), "GIFs pass through at any size")
        XCTAssertEqual(ImagePreparation.plan(typeIdentifier: jpeg, pixelWidth: 0, pixelHeight: 0, byteCount: 10),
                       .reencode(longestEdge: 2560), "unknown dimensions still get the cap")
    }

    // MARK: - Alpha

    func testTransparencyIsCompositedOntoWhite() throws {
        // Left half opaque red, right half fully transparent.
        let source = try encodeImages([makeSplitImage(width: 64, height: 64, left: red, right: nil, alpha: true)], as: .png)

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        let output = try XCTUnwrap(decodeImage(prepared.data))
        assertColor(pixel(output.image, x: 60, y: 32), (255, 255, 255), "transparent pixels must become white")
        assertColor(pixel(output.image, x: 4, y: 32), (255, 0, 0), "opaque pixels keep their color")

        // The flattening is ours, not the JPEG encoder's (macOS ImageIO happens to whiten
        // transparency when encoding; other ImageIO versions blacken it): the rendered image handed
        // to the encoder must already be opaque, with white where the source was transparent.
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(source as CFData, nil))
        let rendered = try XCTUnwrap(ImagePreparation.renderedImage(from: imageSource, longestEdge: 64))
        XCTAssertTrue([.none, .noneSkipLast, .noneSkipFirst].contains(rendered.alphaInfo), "rendered image must be opaque")
        assertColor(pixel(rendered, x: 60, y: 32), (255, 255, 255), "flattened onto white before encoding")
    }

    // MARK: - Metadata

    func testReencodedOutputDropsGPSDeviceAndCaptureMetadata() throws {
        // Wider than 2560 so it's re-encoded (a small JPEG would pass through untouched).
        let source = try encodeImages([makeSplitImage(width: 2600, height: 100, left: red, right: blue)], as: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 122.0, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 17 Pro"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:27 10:00:00",
                                             kCGImagePropertyExifLensModel: "back camera"],
        ])
        let input = try XCTUnwrap(decodeImage(source))
        XCTAssertNotNil(input.properties[kCGImagePropertyGPSDictionary], "fixture must actually carry GPS")

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        let output = try XCTUnwrap(decodeImage(prepared.data))
        XCTAssertNil(output.properties[kCGImagePropertyGPSDictionary], "GPS must be stripped")
        let tiff = output.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake], "device make must be stripped")
        XCTAssertNil(tiff?[kCGImagePropertyTIFFModel], "device model must be stripped")
        let exif = output.properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal], "capture date must be stripped")
        XCTAssertNil(exif?[kCGImagePropertyExifLensModel])
    }

    // MARK: - HEIC (when this host can encode one)

    func testHEICIsConvertedToJPEG() throws {
        let image = try makeSplitImage(width: 400, height: 300, left: red, right: blue)
        guard let heic = try? encodeImages([image], as: .heic) else {
            throw XCTSkip("this host has no HEIC encoder")
        }

        let prepared = try XCTUnwrap(ImagePreparation.prepare(heic))

        XCTAssertTrue(prepared.wasReencoded)
        XCTAssertEqual(decodeImage(prepared.data)?.typeIdentifier, UTType.jpeg.identifier)
    }

    // MARK: - Failure + naming

    func testUnreadableBytesReturnNil() {
        XCTAssertNil(ImagePreparation.prepare(Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(ImagePreparation.prepare(Data()))
    }

    func testFileNameSwapsExtensionOnlyWhenReencoded() {
        XCTAssertEqual(ImagePreparation.fileName("IMG_1234.HEIC", reencoded: true), "IMG_1234.jpg")
        XCTAssertEqual(ImagePreparation.fileName("IMG_1234", reencoded: true), "IMG_1234.jpg")
        XCTAssertEqual(ImagePreparation.fileName("scan.v2.png", reencoded: true), "scan.v2.jpg")
        XCTAssertEqual(ImagePreparation.fileName("IMG_1234.JPG", reencoded: false), "IMG_1234.JPG")
        XCTAssertNil(ImagePreparation.fileName(nil, reencoded: true))
        XCTAssertNil(ImagePreparation.fileName("", reencoded: true))
    }
}
