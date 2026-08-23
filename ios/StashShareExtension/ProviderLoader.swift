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
    ///
    /// - Returns: the loaded objects, plus `droppedCount` — `providers.count - objects.count` —
    ///   for every provider that did NOT become a `SharedObject` (Fix round 1, Important review
    ///   finding): an unsupported UTI, a `loadItem`/`loadFileRepresentation` failure, or a staging
    ///   throw all look identical to the user (nothing renders for that attachment) unless the
    ///   caller surfaces the count. `ShareComposeView` shows a one-line "N item(s) couldn't be
    ///   read" whenever this is non-zero — parity with the composer's own dropped-attachment
    ///   surfacing (`CaptureOutcome`'s `dropped` counts).
    func load(from extensionContext: NSExtensionContext?) async -> (objects: [SharedObject], droppedCount: Int) {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        var objects: [SharedObject] = []
        for provider in providers {
            if let object = await loadOne(provider) {
                objects.append(object)
            }
        }
        return (ShareIntake.reorderURLFirst(objects), providers.count - objects.count)
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
            return await loadFile(provider, typeIdentifier: UTType.image.identifier, isImage: true,
                                  shouldProbeDuration: false, fallbackExtension: "jpg")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.movie.identifier, isImage: false,
                                  shouldProbeDuration: true, fallbackExtension: "mov")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.audio.identifier, isImage: false,
                                  shouldProbeDuration: true, fallbackExtension: "m4a")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.pdf.identifier, isImage: false,
                                  shouldProbeDuration: false, fallbackExtension: "pdf")
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
    ///
    /// - Parameter fallbackExtension: used ONLY when the provider's own temp `URL` has no extension
    ///   at all (rare in practice — the system-handed temp file for a real share almost always
    ///   already carries a sensible one). Fix round 1 (Critical review finding): this used to fall
    ///   back to `UTType(typeIdentifier)?.preferredFilenameExtension` — but `typeIdentifier` here is
    ///   the ABSTRACT category constant (`public.image`/`.movie`/`.audio`) `loadOne` matched on, and
    ///   that property returns `nil` for an abstract type (verified empirically), silently
    ///   collapsing to `"bin"` regardless of category. A category-specific literal fallback, passed
    ///   in by the caller that already knows which branch matched, has no such failure mode.
    private func loadFile(_ provider: NSItemProvider, typeIdentifier: String, isImage: Bool,
                          shouldProbeDuration: Bool, fallbackExtension: String) async -> SharedObject? {
        let fileName = provider.suggestedName

        let staged: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? fallbackExtension : url.pathExtension
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if isImage, fileSize > maxImageDirectStageBytes {
                    continuation.resume(returning: try? staging.stageDownscaledImage(from: url, maxDimension: 4096, quality: 0.85))
                } else {
                    continuation.resume(returning: try? staging.stage(from: url, fileExtension: ext))
                }
            }
        }
        guard let staged else { return nil }

        // Derived from the STAGED file's own extension via StashKit's shared map — NEVER from the
        // abstract category `typeIdentifier` (Fix round 1, Critical review finding: reviewer
        // verified `UTType(typeIdentifier)?.preferredMIMEType` returns `nil` for
        // `public.image`/`.movie`/`.audio` on this toolchain — only a concrete type like
        // `com.adobe.pdf` resolves — so every non-JPEG shared file was silently mislabeled
        // `application/octet-stream`, sending it down add-file's 'document' branch server-side with
        // no analyze-image/transcribe-audio enrichment). This also naturally covers a downscaled
        // image (always re-encoded as `.jpg` by `StagedFileStore`'s own contract) with no separate
        // special case, since `.jpg` is itself a concrete, correctly-mapped extension.
        let mimeType = StagedFileStore.mimeType(forFileExtension: staged.pathExtension)
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
