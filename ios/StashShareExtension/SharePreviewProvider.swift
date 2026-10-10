import CoreGraphics
import Foundation
import ImageIO
import Network
import Observation
import StashKit
import UniformTypeIdentifiers
import Vision

/// Optional, display-only evidence. It never creates a save, uploads to storage,
/// refreshes authentication, or feeds guessed text into the capture payload.
@MainActor @Observable
final class SharePreviewProvider {
    private(set) var title: String?
    private(set) var summary: String?

    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var stopWorkers: (() -> Void)?
    @ObservationIgnored private var suppliedTitle: String?
    @ObservationIgnored private var fallbackTitle: String?
    @ObservationIgnored private var evidenceRank = 0

    func load(objects: [SharedObject], items: [NSExtensionItem]) async {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        cancel()
        let id = UUID()
        generation = id
        evidenceRank = 0
        suppliedTitle = items.lazy.compactMap { SharePreviewRules.clean($0.attributedTitle?.string) }.first
        let input = PreviewInput(objects.first)
        fallbackTitle = input.fallback
        title = SharePreviewRules.title(supplied: suppliedTitle, enriched: nil, fallback: fallbackTitle)
        summary = nil

        // This is the already-persisted token, never auth.session's refreshing getter.
        let session = StashClient.shared.auth.currentSession
        let token = session?.isExpired == false ? session?.accessToken : nil
        let bitmap = Task.detached(priority: .utility) { PreviewBitmap.make(input) }
        let local = Task.detached(priority: .utility) {
            guard let image = await bitmap.value, !Task.isCancelled else { return nil as SharePreviewText? }
            return await image.recognizeText(document: input.isPDF)
        }
        let remote = Task.detached(priority: .utility) {
            guard let token, !Task.isCancelled, ContinuousClock.now < deadline,
                  await PreviewNetworkProbe().isEligible() else { return nil as SharePreviewText? }
            let endpoint: String
            let body: [String: String]
            if let url = input.link, let publicURL = SharePreviewRules.publicWebURL(url) {
                endpoint = "extract-link-metadata"
                // fastOnly is added as a Bool below; no userId or itemId is sent.
                body = ["url": publicURL.absoluteString]
            } else if input.isImage, let image = await bitmap.value, !Task.isCancelled,
                      ContinuousClock.now < deadline, let data = image.jpeg() {
                endpoint = "analyze-image"
                // Existing chip-time mode: a small data URL, no storage or item writes.
                body = ["imageUrl": "data:image/jpeg;base64," + data.base64EncodedString()]
            } else { return nil }
            return await PreviewRemote.fetch(endpoint: endpoint, body: body, token: token, deadline: deadline)
        }
        stopWorkers = { bitmap.cancel(); local.cancel(); remote.cancel() }
        let localObserver = Task { [weak self] in
            if let text = await local.value, !Task.isCancelled {
                self?.apply(text, rank: 1, id: id, deadline: deadline)
            }
        }
        let remoteObserver = Task { [weak self] in
            if let text = await remote.value, !Task.isCancelled {
                self?.apply(text, rank: 2, id: id, deadline: deadline)
            }
        }
        tasks = [localObserver, remoteObserver]
        let observers = tasks
        // withDeadline drops late work rather than waiting for a non-cooperative
        // decoder/Vision request. The result gate independently rejects late callbacks.
        await withTaskCancellationHandler {
            await withDeadline(max(.zero, ContinuousClock.now.duration(to: deadline)), fallback: ()) {
                for observer in observers { await observer.value }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(generation: id) }
        }
        cancel(generation: id)
    }

    func cancel() {
        generation = nil
        tasks.forEach { $0.cancel() }
        tasks = []
        stopWorkers?()
        stopWorkers = nil
    }

    private func cancel(generation id: UUID) {
        guard generation == id else { return }
        cancel()
    }

    private func apply(_ text: SharePreviewText, rank: Int, id: UUID, deadline: ContinuousClock.Instant) {
        guard generation == id, ContinuousClock.now < deadline, rank >= evidenceRank else { return }
        evidenceRank = rank
        title = SharePreviewRules.title(supplied: suppliedTitle, enriched: text.title, fallback: fallbackTitle)
        if let value = SharePreviewRules.clean(text.summary, limit: 240) { summary = value }
    }
}

private struct PreviewInput: Sendable {
    let link: String?
    let file: URL?
    let isPDF: Bool
    let isImage: Bool
    let fallback: String?

    init(_ object: SharedObject?) {
        switch object {
        case .url(let value):
            link = value; file = nil; isPDF = false; isImage = false
            fallback = URL(string: value)?.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? "Link"
        case .file(let url, let mime, let name, _):
            link = nil; file = url
            isPDF = mime == "application/pdf" || url.pathExtension.lowercased() == "pdf"
            isImage = mime.hasPrefix("image/")
            fallback = SharePreviewRules.clean(name) ?? (isPDF ? "PDF" : isImage ? "Image" : "File")
        case .text(let value):
            link = nil; file = nil; isPDF = false; isImage = false
            fallback = SharePreviewRules.clean(value, limit: 100)
        case nil:
            link = nil; file = nil; isPDF = false; isImage = false; fallback = nil
        }
    }
}

/// Immutable CGImage ownership; decodes and Vision run off the main actor.
private struct PreviewBitmap: @unchecked Sendable {
    let image: CGImage

    static func make(_ input: PreviewInput) -> PreviewBitmap? {
        guard !Task.isCancelled, let url = input.file, url.isFileURL,
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              bytes > 0, bytes <= 20 * 1_024 * 1_024 else { return nil }
        return autoreleasepool {
            if input.isPDF {
                guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
                let bounds = page.getBoxRect(.cropBox)
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
                let ratio = min(1, 1_024 / max(bounds.width, bounds.height))
                let width = max(1, Int(bounds.width * ratio)), height = max(1, Int(bounds.height * ratio))
                guard let context = context(width: width, height: height) else { return nil }
                let rect = CGRect(x: 0, y: 0, width: width, height: height)
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
                context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page)
                return context.makeImage().map { PreviewBitmap(image: $0) }
            }
            guard input.isImage,
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_024,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return PreviewBitmap(image: image)
        }
    }

    func recognizeText(document: Bool) async -> SharePreviewText? {
        let request = PreviewTextRequest()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            do {
                try VNImageRequestHandler(cgImage: image).perform([request.request])
                guard !Task.isCancelled else { return nil }
                let lines = request.request.results?.prefix(12).compactMap { observation -> String? in
                    guard let text = observation.topCandidates(1).first, text.confidence >= 0.5 else { return nil }
                    return text.string
                } ?? []
                return SharePreviewRules.recognizedText(lines, document: document)
            } catch { return nil }
        } onCancel: { request.request.cancel() }
    }

    func jpeg() -> Data? {
        guard !Task.isCancelled else { return nil }
        let ratio = min(1, 768 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * ratio)), height = max(1, Int(Double(image.height) * ratio))
        guard let context = Self.context(width: width, height: height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        context.draw(image, in: rect)
        guard let thumbnail = context.makeImage() else { return nil }
        for quality in [0.65, 0.4] {
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), bytes.length <= 150 * 1_024 { return bytes as Data }
        }
        return nil
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

/// VNRequest.cancel is designed to interrupt an in-progress perform call.
private final class PreviewTextRequest: @unchecked Sendable {
    let request: VNRecognizeTextRequest
    init() {
        request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015
    }
}

private final class PreviewNetworkProbe: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var finished = false

    func isEligible() async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let cancelled = lock.withLock {
                    if finished { return true }
                    self.continuation = continuation
                    return false
                }
                guard !cancelled else { continuation.resume(returning: false); return }
                monitor.pathUpdateHandler = { [weak self] path in
                    self?.finish(path.status == .satisfied && !path.isConstrained && !path.isExpensive)
                }
                monitor.start(queue: DispatchQueue.global(qos: .utility))
            }
        } onCancel: { self.finish(false) }
    }

    private func finish(_ value: Bool) {
        let continuation = lock.withLock {
            finished = true
            defer { self.continuation = nil }
            return self.continuation
        }
        monitor.cancel()
        continuation?.resume(returning: value)
    }
}

private enum PreviewRemote {
    private struct Response: Decodable { let success: Bool?; let title: String?; let description: String? }

    static func fetch(endpoint: String, body: [String: String], token: String,
                      deadline: ContinuousClock.Instant) async -> SharePreviewText? {
        guard !Task.isCancelled, ContinuousClock.now < deadline else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/\(endpoint)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 0.5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        var payload: [String: Any] = body
        if endpoint == "extract-link-metadata" { payload["fastOnly"] = true }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.expectedContentLength <= 64 * 1_024 else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 64 * 1_024, !Task.isCancelled, ContinuousClock.now < deadline else { return nil }
                data.append(byte)
            }
            let result = try JSONDecoder().decode(Response.self, from: data)
            guard result.success == true else { return nil }
            let title = SharePreviewRules.clean(result.title)
            let summary = SharePreviewRules.clean(result.description, limit: 240)
            guard title != nil || summary != nil else { return nil }
            return SharePreviewText(title: title, summary: summary)
        } catch { return nil }
    }
}
