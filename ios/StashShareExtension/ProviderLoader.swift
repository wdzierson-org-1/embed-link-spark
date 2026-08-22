import AVFoundation
import Foundation
import StashKit
import UniformTypeIdentifiers

/// Turns whatever the OS handed the extension (`NSExtensionContext.inputItems`) into StashKit's
/// own `[SharedObject]` — the ONE place in this target that touches `NSItemProvider` directly.
/// `ShareIntake` (StashKit, Task 6) deliberately never does: `NSItemProvider` loading is
/// callback-based and not `Sendable`, which would make that whole type impossible to exercise
/// under plain `swift test` if it lived there too (see `ShareIntake.swift`'s own header comment).
///
/// Extension-safe by construction: no `UIApplication.shared` or any other extension-unsafe API.
/// `public.url`/`public.plain-text` are read via `loadItem` (small, already-in-memory values the
/// system hands back directly); `public.image`/`public.movie`/`public.audio`/`com.adobe.pdf` are
/// STAGED — via `StagedFileStore.stage`/`stageDownscaledImage` — synchronously INSIDE
/// `loadFileRepresentation`'s own completion handler, never after it returns: that handler's `URL`
/// argument is a transient temp file the system reclaims the instant the handler returns, so
/// copying it anywhere else (even hopping onto a `Task` from within the handler) would race that
/// deletion. `StagedFileStore`'s own methods are plain synchronous, throwing `FileManager`/ImageIO
/// calls — never `async` — which is what makes calling them directly, inline, inside the handler
/// both possible and correct.
struct ProviderLoader {
    let staging: StagedFileStore

    /// Task 7 brief: images over this size are staged via `stageDownscaledImage` (bounded ImageIO
    /// decode) instead of a bare byte-for-byte `stage` copy — mirrors the composer's own 20 MB
    /// photo-upload threshold (`CaptureViewModel.validatedUploadData`), applied here at STAGE time
    /// instead of upload time since the extension's memory ceiling is much tighter.
    private let maxImageDirectStageBytes = 20 * 1024 * 1024

    /// Loads every attachment across every input item, in whatever order the OS/sending app
    /// provided them, then applies `ShareIntake.reorderURLFirst` (T6-review carry, adopted
    /// ordering decision) so a shared URL always ends up at index 0 regardless of that order —
    /// matching the composer's own URL-first deterministic rule, so `ShareIntake.submit`'s
    /// note-on-first-object rule always lands a share's note on the URL when one is present.
    func load(from extensionContext: NSExtensionContext?) async -> [SharedObject] {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        var objects: [SharedObject] = []
        for provider in providers {
            if let object = await loadOne(provider) {
                objects.append(object)
            }
        }
        return ShareIntake.reorderURLFirst(objects)
    }

    // MARK: - One provider

    /// Order matters: `public.file-url` conforms to `public.url` (a local file IS a URL), so a
    /// shared file's own provider would otherwise misroute into the URL/text branches below —
    /// excluding `isFileURL` on both is the standard fix (mirrors Apple's own share/action
    /// extension sample code doing the same "WebURL vs. File" disambiguation).
    private func loadOne(_ provider: NSItemProvider) async -> SharedObject? {
        let isFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !isFileURL {
            return await loadURL(provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !isFileURL {
            return await loadText(provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.image.identifier, isImage: true, shouldProbeDuration: false)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.movie.identifier, isImage: false, shouldProbeDuration: true)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.audio.identifier, isImage: false, shouldProbeDuration: true)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.pdf.identifier, isImage: false, shouldProbeDuration: false)
        }
        return nil   // an attachment type this share extension doesn't (yet) understand — dropped, not crashed on.
    }

    private func loadURL(_ provider: NSItemProvider) async -> SharedObject? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                guard let url = item as? URL else { continuation.resume(returning: nil); return }
                continuation.resume(returning: .url(url.absoluteString))
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> SharedObject? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                guard let text = item as? String, !text.isEmpty else { continuation.resume(returning: nil); return }
                continuation.resume(returning: .text(text))
            }
        }
    }

    /// Stages a file-backed provider. The size check (and the `stage` vs. `stageDownscaledImage`
    /// choice it drives) happens INSIDE the completion handler, on the transient temp `URL`'s own
    /// `.fileSizeKey` — a stat call, never a read — since that's the only point this file ever has
    /// a valid reference to it.
    private func loadFile(_ provider: NSItemProvider, typeIdentifier: String, isImage: Bool, shouldProbeDuration: Bool) async -> SharedObject? {
        let fileName = provider.suggestedName
        let providerMimeType = UTType(typeIdentifier)?.preferredMIMEType ?? "application/octet-stream"

        let staged: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty
                    ? (UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin")
                    : url.pathExtension
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if isImage, fileSize > maxImageDirectStageBytes {
                    continuation.resume(returning: try? staging.stageDownscaledImage(from: url, maxDimension: 4096, quality: 0.85))
                } else {
                    continuation.resume(returning: try? staging.stage(from: url, fileExtension: ext))
                }
            }
        }
        guard let staged else { return nil }

        // `stageDownscaledImage` always re-encodes as JPEG regardless of the source format
        // (`StagedFileStore`'s own contract) — the mime type must describe what's actually ON DISK
        // now, not the provider's original type. Checking the staged file's own extension (rather
        // than threading a separate "was this downscaled" flag through the closure above) is safe
        // either way: a NON-downscaled image keeps its original extension (so this is a no-op for
        // it), and a downscaled one is always ".jpg" — the two cases can't collide.
        let mimeType = (isImage && staged.pathExtension.lowercased() == "jpg") ? "image/jpeg" : providerMimeType
        let durationS = shouldProbeDuration ? await probeDuration(url: staged) : nil
        return .file(stagedURL: staged, mimeType: mimeType, fileName: fileName, durationS: durationS)
    }

    /// `AVAsset` duration probe run on the STAGED file (never the transient provider URL) — Task 7
    /// brief's explicit placement. Mirrors `CaptureComposerView.probeDuration` exactly, including
    /// its own disclosed deviation: `AVAsset` itself has no `init(url:)` — that initializer is
    /// declared on `AVURLAsset`, a concrete subclass.
    private func probeDuration(url: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
