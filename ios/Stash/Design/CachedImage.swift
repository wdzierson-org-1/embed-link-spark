import SwiftUI
import UIKit
import ImageIO
import StashKit

/// How a decoded image will be drawn — decides how many pixels are worth decoding.
enum ImageFit: Hashable, Sendable {
    /// Must COVER a box of this size (points) — `aspectRatio(contentMode: .fill)`.
    case fill(CGSize)
    /// Must fit INSIDE a box of this size (points) — `aspectRatio(contentMode: .fit)`.
    case fit(CGSize)
    /// Native photo heroes: a portrait image is drawn contained in `portrait`, anything else
    /// covers `landscape` (`ImageHeroZone`'s own tall-vs-standard switch).
    case hero(portrait: CGSize, landscape: CGSize)

    /// Longest-side pixel budget for a `width × height` source drawn at `scale`, never larger than
    /// the source itself (ImageIO never upscales a thumbnail anyway).
    func maxPixelSize(sourceWidth width: CGFloat, sourceHeight height: CGFloat, scale: CGFloat) -> Int {
        guard width > 0, height > 0 else { return 1 }
        let factor: CGFloat
        switch self {
        case .fill(let box):
            factor = max(box.width * scale / width, box.height * scale / height)
        case .fit(let box):
            factor = min(box.width * scale / width, box.height * scale / height)
        case .hero(let portrait, let landscape):
            return (isPortraitAspect(width: width, height: height) ? ImageFit.fit(portrait) : ImageFit.fill(landscape))
                .maxPixelSize(sourceWidth: width, sourceHeight: height, scale: scale)
        }
        let longest = max(width, height)
        return max(1, Int(min(longest, (longest * factor).rounded(.up))))
    }

    fileprivate var keyComponent: String {
        func size(_ s: CGSize) -> String { "\(Int(s.width.rounded()))x\(Int(s.height.rounded()))" }
        switch self {
        case .fill(let box): return "fill:\(size(box))"
        case .fit(let box): return "fit:\(size(box))"
        case .hero(let portrait, let landscape): return "hero:\(size(portrait)):\(size(landscape))"
        }
    }
}

/// One decode: the same URL drawn at two different sizes is two cache entries.
struct ImageRequest: Hashable, Sendable {
    let url: URL
    let fit: ImageFit
    let scale: CGFloat

    var cacheKey: String { "\(url.absoluteString)|\(fit.keyComponent)|@\(Int(scale))x" }
}

/// The app's one image loader (plan 15, "Images"): card heroes, the detail hero and the legacy
/// collection strip all go through it.
///
/// - **Memory:** an `NSCache` of already-DOWNSAMPLED images keyed by URL + draw size, so a card
///   scrolled back into view (or the View tab opened after a prefetch) draws its hero on the first
///   frame, synchronously — no placeholder flash.
/// - **Disk:** a dedicated `URLCache` (50 MB memory / 300 MB disk) in `Caches/StashImageCache`,
///   read and written explicitly: Supabase Storage answers `cache-control: no-cache`, which would
///   otherwise make every launch revalidate every hero over the network. A card hero is effectively
///   immutable (its object path never changes), so a stored copy is always good.
/// - **Decode:** ImageIO thumbnailing straight to the pixels the view will draw (orientation
///   applied), never a full-resolution `UIImage(data:)` of a 12-megapixel original — the difference
///   between ~1 MB and ~48 MB of decoded bitmap per photo.
/// - **Cancellation:** a view's load runs in that view's own task, so scrolling a card away cancels
///   its download; prefetches run detached (only the first page's heroes are prefetched) and a view
///   that asks for an image already being prefetched awaits that prefetch instead of re-fetching.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private let diskCache: URLCache
    private let session: URLSession
    private let lock = NSLock()
    private var prefetches: [String: Task<UIImage?, Never>] = [:]
    /// The most recent decode key per URL, so another size of the same image can stand in while
    /// the exact one decodes (see `anyCachedImage(for:)`).
    private var latestKeyByURL: [URL: String] = [:]

    init() {
        memory.totalCostLimit = 96 * 1024 * 1024
        memory.countLimit = 400
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StashImageCache", isDirectory: true)
        diskCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024,
                             directory: directory)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil               // `diskCache` is managed explicitly (see above)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    /// Synchronous memory hit — what lets a view draw a cached image in its first frame.
    func cachedImage(for request: ImageRequest) -> UIImage? {
        memory.object(forKey: request.cacheKey as NSString)
    }

    /// Any decoded size of `url` still in memory — e.g. the card's hero while the detail sheet's
    /// own decode is in flight. Same source, same aspect ratio: a stand-in that never shifts
    /// layout, replaced by the exact decode a moment later.
    func anyCachedImage(for url: URL) -> UIImage? {
        guard let key = lock.withLock({ latestKeyByURL[url] }) else { return nil }
        return memory.object(forKey: key as NSString)
    }

    /// Memory → in-flight prefetch → disk → network. `nil` = unavailable (the caller shows its
    /// fallback plate). Honors the calling task's cancellation.
    func image(for request: ImageRequest) async -> UIImage? {
        if let hit = cachedImage(for: request) { return hit }
        if let pending = lock.withLock({ prefetches[request.cacheKey] }) { return await pending.value }
        return await load(request)
    }

    /// Warms memory + disk for images about to be shown (first-page heroes).
    func prefetch(_ requests: [ImageRequest]) {
        for request in requests where cachedImage(for: request) == nil {
            lock.withLock {
                guard prefetches[request.cacheKey] == nil else { return }
                prefetches[request.cacheKey] = Task.detached(priority: .utility) { [self] in
                    let image = await load(request)
                    lock.withLock { prefetches[request.cacheKey] = nil }
                    return image
                }
            }
        }
    }

    /// Sign-out / account deletion: nothing from the previous account's library stays on device.
    func purge() {
        lock.withLock {
            prefetches.values.forEach { $0.cancel() }
            prefetches.removeAll()
            latestKeyByURL.removeAll()
        }
        memory.removeAllObjects()
        diskCache.removeAllCachedResponses()
    }

    private func load(_ request: ImageRequest) async -> UIImage? {
        let urlRequest = URLRequest(url: request.url)
        let data: Data
        if let cached = diskCache.cachedResponse(for: urlRequest) {
            data = cached.data
        } else {
            do {
                let (body, response) = try await session.data(for: urlRequest)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                data = body
                diskCache.storeCachedResponse(CachedURLResponse(response: response, data: body), for: urlRequest)
            } catch {
                return nil
            }
        }
        guard !Task.isCancelled, let image = Self.downsample(data, for: request) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
        memory.setObject(image, forKey: request.cacheKey as NSString, cost: cost)
        lock.withLock { latestKeyByURL[request.url] = request.cacheKey }
        return image
    }

    /// Decodes straight to the draw size (ImageIO thumbnail, EXIF orientation applied).
    static func downsample(_ data: Data, for request: ImageRequest) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber).map({ CGFloat($0.doubleValue) }),
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber).map({ CGFloat($0.doubleValue) })
        else { return nil }
        // EXIF orientations 5–8 are rotated 90°: the drawn width is the stored height.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: request.fit.maxPixelSize(sourceWidth: width, sourceHeight: height,
                                                                           scale: request.scale),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage, scale: request.scale, orientation: .up)
    }
}

enum CachedImagePhase {
    case empty
    case success(UIImage)
    case failure
}

/// `AsyncImage`'s shape (a phase-driven content closure) over `ImagePipeline`: draws a memory-
/// cached image in the very first frame, and never shows a result that belongs to a URL/size the
/// view has since moved on from.
struct CachedImage<Content: View>: View {
    let url: URL?
    let fit: ImageFit
    @ViewBuilder var content: (CachedImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var result: LoadedImage?

    private struct LoadedImage {
        let key: String
        let image: UIImage?
    }

    var body: some View {
        let request = url.map { ImageRequest(url: $0, fit: fit, scale: displayScale) }
        content(phase(for: request))
            .task(id: request?.cacheKey) {
                guard let request, ImagePipeline.shared.cachedImage(for: request) == nil else { return }
                let image = await ImagePipeline.shared.image(for: request)
                guard !Task.isCancelled else { return }
                result = LoadedImage(key: request.cacheKey, image: image)
            }
    }

    private func phase(for request: ImageRequest?) -> CachedImagePhase {
        guard let request else { return .failure }
        if let cached = ImagePipeline.shared.cachedImage(for: request) { return .success(cached) }
        if let result, result.key == request.cacheKey {
            return result.image.map(CachedImagePhase.success) ?? .failure
        }
        // Another size of the same image (e.g. the card's hero when the detail sheet opens) —
        // drawn now instead of a placeholder that would then jump to the image's aspect ratio.
        if let standIn = ImagePipeline.shared.anyCachedImage(for: request.url) { return .success(standIn) }
        return .empty
    }
}

/// The key window's geometry, read synchronously so a view's image request (and the app-scope
/// prefetch that has to produce the identical request) is known in the first frame.
@MainActor
enum ScreenMetrics {
    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    }

    static var windowWidth: CGFloat { keyWindow?.bounds.width ?? 393 }
    static var displayScale: CGFloat { keyWindow?.traitCollection.displayScale ?? 3 }
}

/// Detail-sheet hero box (`ItemDetailView.heroImage`): full sheet width inside the 20pt insets,
/// at most 384pt tall.
@MainActor
enum DetailHeroSizing {
    static var fit: ImageFit { .fit(CGSize(width: max(ScreenMetrics.windowWidth - 40, 1), height: 384)) }
}
