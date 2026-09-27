import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import StashKit

// MARK: - Recorded requests

/// One `multipart/form-data` part, parsed back out of a request body.
struct MultipartPart {
    let headers: [String: String]
    let data: Data

    var name: String? { dispositionParameter("name") }
    var filename: String? { dispositionParameter("filename") }
    var contentType: String? { headers["content-type"] }

    private func dispositionParameter(_ key: String) -> String? {
        guard let disposition = headers["content-disposition"] else { return nil }
        for piece in disposition.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let prefix = "\(key)=\""
            if piece.hasPrefix(prefix), piece.hasSuffix("\"") {
                return String(piece.dropFirst(prefix.count).dropLast())
            }
        }
        return nil
    }
}

/// Splits a multipart body on `boundary` (test-only parser; strict CRLF framing).
func parseMultipart(_ body: Data, boundary: String) -> [MultipartPart] {
    let delimiter = Data("--\(boundary)".utf8)
    let crlf = Data("\r\n".utf8)
    let headerEnd = Data("\r\n\r\n".utf8)
    var parts: [MultipartPart] = []
    var cursor = body.startIndex
    guard let first = body.range(of: delimiter, in: cursor..<body.endIndex) else { return [] }
    cursor = first.upperBound
    while cursor < body.endIndex {
        // "--" right after a delimiter closes the body.
        if body[cursor...].starts(with: Data("--".utf8)) { break }
        guard body[cursor...].starts(with: crlf) else { break }
        let partStart = cursor + crlf.count
        guard let next = body.range(of: crlf + delimiter, in: partStart..<body.endIndex),
              let headersRange = body.range(of: headerEnd, in: partStart..<next.lowerBound) else { break }
        let headerText = String(decoding: body[partStart..<headersRange.lowerBound], as: UTF8.self)
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        parts.append(MultipartPart(headers: headers, data: Data(body[headersRange.upperBound..<next.lowerBound])))
        cursor = next.upperBound
    }
    return parts
}

/// A request as the stub transport saw it — body read from the body file AT CALL TIME.
struct TransportCall {
    let request: URLRequest
    let body: Data

    var url: URL { request.url! }
    var isCapture: Bool { url.path.hasSuffix("/functions/v1/capture") }
    var isStorage: Bool { url.path.contains("/storage/v1/object/stash-media/") }
    /// `<uid>/<name>.<ext>` for a storage upload.
    var storagePath: String? {
        guard let range = url.path.range(of: "/storage/v1/object/stash-media/") else { return nil }
        return String(url.path[range.upperBound...])
    }
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    var boundary: String? {
        guard let type = header("Content-Type"), type.hasPrefix("multipart/form-data"),
              let range = type.range(of: "boundary=") else { return nil }
        return String(type[range.upperBound...])
    }
    var isMultipart: Bool { boundary != nil }
    var parts: [MultipartPart] { boundary.map { parseMultipart(body, boundary: $0) } ?? [] }
    var filePart: MultipartPart? { parts.first { $0.name == "file" } }
    /// The capture `meta` — the JSON body, or the multipart `meta` part.
    var meta: [String: Any] {
        let json = isMultipart ? parts.first { $0.name == "meta" }?.data : body
        return json.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    }
    var kind: String? { meta["kind"] as? String }
    var captureId: String? { meta["capture_id"] as? String }
    var attributes: [String: Any]? { meta["attributes"] as? [String: Any] }
}

// MARK: - Fake capture server

/// A `CaptureTransporting` that behaves like the plan-15 `capture` endpoint + Storage: it keeps
/// "receipts" by capture id (a repeat answers `duplicate: true` with the SAME item and creates
/// nothing), stores upserted objects, and can be scripted per request to fail in specific ways —
/// including "applied server-side, but the response never arrived" (a lost response).
final class FakeCaptureServer: CaptureTransporting, @unchecked Sendable {
    enum Behavior {
        /// Normal processing.
        case normal
        /// Answer with this status + body WITHOUT applying anything.
        case respond(Int, String)
        /// Throw before the server sees anything (offline).
        case fail(Error)
        /// Apply normally, then throw instead of answering (lost response).
        case applyThenFail(Error)
    }

    private let lock = NSLock()
    private var _calls: [TransportCall] = []
    private var _rows: [String: [String: Any]] = [:]      // capture_id → item row
    private var _objects: [String: Data] = [:]            // storage path → bytes
    /// Consumed in order, one per capture request; empty → `.normal`.
    var captureBehaviors: [Behavior] = []
    /// Consumed in order, one per storage upload; empty → `.normal`.
    var storageBehaviors: [Behavior] = []
    /// Runs at the start of every request (after it's recorded) — tests use it to observe or
    /// mutate on-disk state at the exact moment a request goes out.
    var onRequest: ((TransportCall) async -> Void)?

    var calls: [TransportCall] { lock.withLock { _calls } }
    var captures: [TransportCall] { calls.filter(\.isCapture) }
    var storageUploads: [TransportCall] { calls.filter(\.isStorage) }
    /// Items the server has actually created (one per distinct capture id).
    var createdItemCount: Int { lock.withLock { _rows.count } }
    var objects: [String: Data] { lock.withLock { _objects } }

    func upload(_ request: URLRequest, fromFile bodyFile: URL) async throws -> (status: Int, body: Data) {
        let call = TransportCall(request: request, body: (try? Data(contentsOf: bodyFile)) ?? Data())
        lock.withLock { _calls.append(call) }
        await onRequest?(call)
        let behavior: Behavior = lock.withLock {
            if call.isStorage { return storageBehaviors.isEmpty ? .normal : storageBehaviors.removeFirst() }
            return captureBehaviors.isEmpty ? .normal : captureBehaviors.removeFirst()
        }
        switch behavior {
        case .normal:
            return apply(call)
        case .respond(let status, let body):
            return (status, Data(body.utf8))
        case .fail(let error):
            throw error
        case .applyThenFail(let error):
            _ = apply(call)
            throw error
        }
    }

    private func apply(_ call: TransportCall) -> (status: Int, body: Data) {
        if call.isStorage, let path = call.storagePath {
            lock.withLock { _objects[path] = call.body }
            return (200, Data(#"{"Key":"stash-media/\#(path)"}"#.utf8))
        }
        let meta = call.meta
        guard let captureId = meta["capture_id"] as? String, let kind = meta["kind"] as? String else {
            return (400, Data(#"{"error":"capture_id is required"}"#.utf8))
        }
        let (row, duplicate): ([String: Any], Bool) = lock.withLock {
            if let existing = _rows[captureId] { return (existing, true) }
            let row = Self.row(kind: kind, meta: meta)
            _rows[captureId] = row
            return (row, false)
        }
        let body = try! JSONSerialization.data(withJSONObject: ["item": row, "duplicate": duplicate])
        return (200, body)
    }

    static func row(kind: String, meta: [String: Any]) -> [String: Any] {
        let mime = meta["mime_type"] as? String
        let type: String
        switch kind {
        case "note": type = "text"
        case "url": type = "link"
        default:
            if mime?.hasPrefix("image/") == true { type = "image" }
            else if mime?.hasPrefix("audio/") == true { type = "audio" }
            else if mime?.hasPrefix("video/") == true { type = "video" }
            else { type = "document" }
        }
        return [
            "id": UUID().uuidString.lowercased(), "type": type, "title": "t",
            "content": meta["content"] ?? NSNull(), "url": meta["url"] ?? NSNull(),
            "file_path": meta["file_path"] ?? NSNull(), "description": NSNull(), "summary": NSNull(),
            "created_at": "2026-09-27T10:00:00+00:00", "mime_type": mime ?? NSNull(),
            "is_public": meta["is_public"] ?? false, "supplemental_note": NSNull(),
        ]
    }
}

/// `.subscriptionRequired` 403, exactly as the server sends it.
let subscriptionRequiredBody = #"{"error":"subscription_required"}"#
let captureInProgressBody = #"{"error":"capture_in_progress"}"#

// MARK: - Images

enum TestImageFailure: Error { case context, image, destination, finalize }

/// A CGImage whose left half is `left` and right half `right` (RGBA; `nil` = fully transparent).
func makeSplitImage(width: Int, height: Int, left: (CGFloat, CGFloat, CGFloat)?, right: (CGFloat, CGFloat, CGFloat)?,
                    alpha: Bool = false) throws -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: info) else { throw TestImageFailure.context }
    if let left {
        context.setFillColor(red: left.0, green: left.1, blue: left.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    }
    if let right {
        context.setFillColor(red: right.0, green: right.1, blue: right.2, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    }
    guard let image = context.makeImage() else { throw TestImageFailure.image }
    return image
}

/// Encodes `image` (or several frames) as `type`, with optional per-image properties.
func encodeImages(_ images: [CGImage], as type: UTType, properties: [CFString: Any]? = nil) throws -> Data {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, images.count, nil) else {
        throw TestImageFailure.destination
    }
    for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary?) }
    guard CGImageDestinationFinalize(destination) else { throw TestImageFailure.finalize }
    return output as Data
}

struct DecodedImageInfo {
    let typeIdentifier: String?
    let width: Int
    let height: Int
    let properties: [CFString: Any]
    let image: CGImage
}

func decodeImage(_ data: Data) -> DecodedImageInfo? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    return DecodedImageInfo(typeIdentifier: CGImageSourceGetType(source) as String?,
                            width: (properties[kCGImagePropertyPixelWidth] as? Int) ?? image.width,
                            height: (properties[kCGImagePropertyPixelHeight] as? Int) ?? image.height,
                            properties: properties, image: image)
}

/// RGB at (`x`, `y`), `y` measured from the TOP of the image.
func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
    buffer.withUnsafeMutableBytes { raw in
        let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    // Bitmap memory is top-row-first.
    let index = (y * image.width + x) * 4
    return (Int(buffer[index]), Int(buffer[index + 1]), Int(buffer[index + 2]))
}

func assertColor(_ actual: (r: Int, g: Int, b: Int), _ expected: (Int, Int, Int), tolerance: Int = 24,
                 _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    let ok = abs(actual.r - expected.0) <= tolerance && abs(actual.g - expected.1) <= tolerance
        && abs(actual.b - expected.2) <= tolerance
    XCTAssertTrue(ok, "\(message): got \(actual), expected ≈\(expected)", file: file, line: line)
}
