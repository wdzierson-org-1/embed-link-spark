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

    // MARK: - Decode strategies (plan 15: memory-bounded decode)

    func testDecodeStrategyThresholds() {
        let strategy = ImagePreparation.decodeStrategy(typeIdentifier:pixelWidth:pixelHeight:)
        let jpeg = UTType.jpeg.identifier
        // Camera RAW → its embedded preview, whatever the size.
        XCTAssertEqual(strategy("com.adobe.raw-image", 400, 300), .embeddedPreview, "DNG → embedded preview")
        XCTAssertEqual(strategy("com.canon.cr2-raw-image", 6000, 4000), .embeddedPreview)
        // ≤ 2560 px: nothing to reduce.
        XCTAssertEqual(strategy(jpeg, 2560, 1920), .thumbnail)
        XCTAssertEqual(strategy(UTType.png.identifier, 1179, 2556), .thumbnail, "a phone screenshot")
        // Over 2560 but can't be halved without dropping under 1600 px: decodes as before.
        XCTAssertEqual(strategy(jpeg, 2561, 1920), .thumbnail)
        XCTAssertEqual(strategy(jpeg, 3199, 2400), .thumbnail)
        // The largest of 8/4/2 that keeps the long edge ≥ 1600.
        XCTAssertEqual(strategy(jpeg, 3200, 2400), .subsampled(factor: 2), "3200 / 2 = 1600 exactly")
        XCTAssertEqual(strategy(jpeg, 4032, 3024), .subsampled(factor: 2), "12 MP → 2016×1512")
        XCTAssertEqual(strategy(UTType.heic.identifier, 3024, 4032), .subsampled(factor: 2), "HEIC too, portrait too")
        XCTAssertEqual(strategy(UTType.heic.identifier, 8064, 6048), .subsampled(factor: 4), "48 MP → 2016 px")
        XCTAssertEqual(strategy(UTType.heif.identifier, 8064, 6048), .subsampled(factor: 4))
        XCTAssertEqual(strategy(UTType.png.identifier, 10000, 10000), .subsampled(factor: 4), "100 MP → 2500 px")
        XCTAssertEqual(strategy(UTType.tiff.identifier, 12800, 9600), .subsampled(factor: 8), "12800 / 8 = 1600 exactly")
        XCTAssertEqual(strategy(UTType.tiff.identifier, 12799, 9600), .subsampled(factor: 4))
        // Formats ImageIO doesn't document subsampling for keep the thumbnail path.
        XCTAssertEqual(strategy(UTType.webP.identifier, 4000, 3000), .thumbnail)
        XCTAssertEqual(strategy(nil, 20000, 20000), .thumbnail)
    }

    /// One end-to-end run per subsampled format — each carrying an EXIF orientation so the
    /// hand-applied rotation is exercised on real decoder output, not just in isolation.
    /// Stored: left half red, right half blue.
    func testSubsampledDecodeProducesAnUprightReducedImageForEachFormat() throws {
        struct Case { let type: UTType; let width: Int; let height: Int; let orientation: Int
                      let factor: Int; let expected: (width: Int, height: Int) }
        let cases = [
            // 6 = rotate 90° CW: stored-left (red) becomes the TOP.
            Case(type: .jpeg, width: 4000, height: 1000, orientation: 6, factor: 2, expected: (500, 2000)),
            Case(type: .heic, width: 3600, height: 1800, orientation: 6, factor: 2, expected: (900, 1800)),
            Case(type: .tiff, width: 6400, height: 800, orientation: 6, factor: 4, expected: (200, 1600)),
            Case(type: .png, width: 4000, height: 1000, orientation: 1, factor: 2, expected: (2000, 500)),
        ]
        for testCase in cases {
            let stored = try makeSplitImage(width: testCase.width, height: testCase.height, left: red, right: blue)
            guard let data = try? encodeImages([stored], as: testCase.type,
                                               properties: [kCGImagePropertyOrientation: testCase.orientation]) else {
                XCTAssertEqual(testCase.type, .heic, "only HEIC encoding may be unavailable on a host")
                continue
            }
            let label = testCase.type.identifier
            XCTAssertEqual(ImagePreparation.decodeStrategy(typeIdentifier: testCase.type.identifier,
                                                           pixelWidth: testCase.width, pixelHeight: testCase.height),
                           .subsampled(factor: testCase.factor), label)

            let prepared = try XCTUnwrap(ImagePreparation.prepare(data), label)

            let output = try XCTUnwrap(decodeImage(prepared.data), label)
            XCTAssertEqual(output.width, testCase.expected.width, "\(label) width")
            XCTAssertEqual(output.height, testCase.expected.height, "\(label) height")
            XCTAssertEqual((output.properties[kCGImagePropertyOrientation] as? Int) ?? 1, 1, "\(label): upright pixels")
            if testCase.orientation == 6 {
                assertColor(pixel(output.image, x: output.image.width / 2, y: 20), (255, 0, 0), "\(label): red on top")
                assertColor(pixel(output.image, x: output.image.width / 2, y: output.image.height - 20), (0, 0, 255),
                            "\(label): blue at the bottom")
            } else {
                assertColor(pixel(output.image, x: 20, y: output.image.height / 2), (255, 0, 0), "\(label): red left")
                assertColor(pixel(output.image, x: output.image.width - 20, y: output.image.height / 2), (0, 0, 255),
                            "\(label): blue right")
            }
        }
    }

    /// A reduced decode that's still over 2560 px is scaled down in the same draw: 6000×4000
    /// halves to 3000×2000, then lands at 2560×1707.
    func testSubsampledDecodeStillOverTheCapIsScaledToIt() throws {
        let source = try encodeImages([makeSplitImage(width: 6000, height: 4000, left: red, right: blue)], as: .jpeg)
        XCTAssertEqual(ImagePreparation.decodeStrategy(typeIdentifier: UTType.jpeg.identifier, pixelWidth: 6000, pixelHeight: 4000),
                       .subsampled(factor: 2))

        let output = try XCTUnwrap(decodeImage(try XCTUnwrap(ImagePreparation.prepare(source)).data))

        XCTAssertEqual(output.width, 2560)
        XCTAssertEqual(output.height, 1707)
    }

    /// The share extension's file-based path (`StagedFileStore.stagePreparedImage`) goes through
    /// the same reduced decode: a 12 MP-class JPEG stages at half resolution.
    func testFileBasedPreparationUsesTheSubsampledDecode() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "prep-file-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let source = dir.appending(path: "IMG_0001.JPG")
        try encodeImages([makeSplitImage(width: 4032, height: 3024, left: red, right: blue)], as: .jpeg).write(to: source)

        let staged = try store.stagePreparedImage(from: source)

        XCTAssertTrue(staged.wasReencoded)
        let output = try XCTUnwrap(decodeImage(try Data(contentsOf: staged.url)))
        XCTAssertEqual(output.width, 2016)
        XCTAssertEqual(output.height, 1512)
    }

    /// The subsampled path orients by hand; ImageIO's own `WithTransform` thumbnail is the oracle,
    /// for all 8 EXIF orientations (a lossless TIFF with four distinct quadrant colors).
    func testHandRolledOrientationMatchesImageIOForAllEightOrientations() throws {
        let width = 60, height = 30
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let quadrants: [(CGRect, (CGFloat, CGFloat, CGFloat))] = [
            (CGRect(x: 0, y: 15, width: 30, height: 15), (1, 0, 0)),     // top-left red
            (CGRect(x: 30, y: 15, width: 30, height: 15), (0, 1, 0)),    // top-right green
            (CGRect(x: 0, y: 0, width: 30, height: 15), (0, 0, 1)),      // bottom-left blue
            (CGRect(x: 30, y: 0, width: 30, height: 15), (1, 1, 0)),     // bottom-right yellow
        ]
        for (rect, color) in quadrants {
            context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
            context.fill(rect)
        }
        let stored = try XCTUnwrap(context.makeImage())

        for orientation in 1...8 {
            let tiff = try encodeImages([stored], as: .tiff, properties: [kCGImagePropertyOrientation: orientation])
            let source = try XCTUnwrap(CGImageSourceCreateWithData(tiff as CFData, nil))
            let oracle = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 60,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary))
            let raw = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let mine = try XCTUnwrap(ImagePreparation.oriented(raw, exifOrientation: orientation, longestEdge: 60))

            XCTAssertEqual(mine.width, oracle.width, "orientation \(orientation): width")
            XCTAssertEqual(mine.height, oracle.height, "orientation \(orientation): height")
            for (fx, fy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
                let x = Int(Double(mine.width) * fx), y = Int(Double(mine.height) * fy)
                let expected = pixel(oracle, x: x, y: y)
                assertColor(pixel(mine, x: x, y: y), (expected.r, expected.g, expected.b), tolerance: 8,
                            "orientation \(orientation) at (\(fx), \(fy))")
            }
        }
    }

    /// A synthetic 50.8 MP PNG goes through the subsampled decode at 1/4 scale (8200 / 4 = 2050,
    /// the largest factor keeping the long edge ≥ 1600): 2050×1550, colors intact.
    func testHugePNGIsPreparedThroughTheSubsampledDecode() throws {
        let width = 8200, height = 6200   // 50.84 MP
        let gray = CGColorSpaceCreateDeviceGray()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))   // left black, right white
        let png = try encodeImages([try XCTUnwrap(context.makeImage())], as: .png)
        XCTAssertEqual(ImagePreparation.decodeStrategy(typeIdentifier: UTType.png.identifier, pixelWidth: width, pixelHeight: height),
                       .subsampled(factor: 4))

        let prepared = try XCTUnwrap(ImagePreparation.prepare(png))

        XCTAssertTrue(prepared.wasReencoded)
        let output = try XCTUnwrap(decodeImage(prepared.data))
        XCTAssertEqual(output.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(output.width, 2050)
        XCTAssertEqual(output.height, 1550)
        assertColor(pixel(output.image, x: 200, y: 775), (0, 0, 0), "left half stays black")
        assertColor(pixel(output.image, x: 1850, y: 775), (255, 255, 255), "right half stays white")
    }

    // MARK: - GPS in passthroughs (plan 15 review: stash-media URLs are public)

    func testPassthroughJPEGLosesGPSLosslesslyAndKeepsOrientation() throws {
        let source = try encodeImages([makeSplitImage(width: 800, height: 600, left: red, right: blue)], as: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 40.7, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 74.0, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple"],
            kCGImagePropertyOrientation: 6,
        ])
        XCTAssertNotNil(decodeImage(source)?.properties[kCGImagePropertyGPSDictionary], "fixture must carry GPS")

        let prepared = try XCTUnwrap(ImagePreparation.prepare(source))

        XCTAssertFalse(prepared.wasReencoded, "a lossless metadata rewrite, not a re-encode")
        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        let output = try XCTUnwrap(decodeImage(prepared.data))
        XCTAssertNil(output.properties[kCGImagePropertyGPSDictionary], "EXIF GPS removed")
        let metadata = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(
            try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil)), 0, nil))
        XCTAssertNil(CGImageMetadataCopyTagWithPath(metadata, nil, "exif:GPSLatitude" as CFString), "XMP GPS removed")
        XCTAssertEqual(output.properties[kCGImagePropertyOrientation] as? Int, 6, "orientation kept — or it would display sideways")
        XCTAssertEqual((output.properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String,
                       "Apple", "everything but GPS is kept")
        XCTAssertEqual(storedPixels(prepared.data), storedPixels(source), "pixels untouched (lossless)")
    }

    /// ImageIO can't rewrite GIF metadata losslessly, so a GIF is kept exactly as it is (GPS in a
    /// GIF can only live in XMP — rare). Documented limitation.
    func testGIFWithGPSIsKeptAsIs() throws {
        let frames = [try makeSplitImage(width: 20, height: 20, left: red, right: blue),
                      try makeSplitImage(width: 20, height: 20, left: blue, right: red)]
        let gif = try encodeImages(frames, as: .gif, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 40.7, kCGImagePropertyGPSLatitudeRef: "N"]])

        let prepared = try XCTUnwrap(ImagePreparation.prepare(gif))

        XCTAssertEqual(prepared.data, gif)
        XCTAssertEqual(prepared.mimeType, "image/gif")
        XCTAssertFalse(prepared.wasReencoded)
    }

    /// Decoded stored pixels (no orientation applied) — for lossless comparisons.
    private func storedPixels(_ data: Data) -> [UInt8] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buffer
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
