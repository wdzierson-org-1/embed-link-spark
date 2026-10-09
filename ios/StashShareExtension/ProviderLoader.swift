import AVFoundation
import Foundation
import os
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
/// system hands back directly); everything file-backed is STAGED synchronously INSIDE
/// `loadFileRepresentation`'s own completion handler, never after it returns: that handler's `URL`
/// argument is a transient temp file the system reclaims the instant the handler returns, so
/// copying it anywhere else (even hopping onto a `Task` from within the handler) would race that
/// deletion. `StagedFileStore`'s own methods are plain synchronous, throwing `FileManager`/ImageIO
/// calls — never `async` — which is what makes calling them directly, inline, inside the handler
/// both possible and correct.
///
/// Plan 15: every image is staged through `StagedFileStore.stagePreparedImage` — resized to
/// ≤ 2560 px JPEG (orientation applied, metadata dropped; GIFs and small JPEGs kept as-is) while
/// the compose card is showing, so Save never waits on it and the upload is a fraction of the
/// original. Any other file type is accepted too (generic `public.data` staging — `add-file`
/// already routes documents), after the specific image/movie/audio/pdf branches.
struct ProviderLoader {
    let staging: StagedFileStore

    /// Loads every attachment across every input item, in whatever order the OS/sending app
    /// provided them, then applies `ShareIntake.reorderURLFirst` (T6-review carry, adopted
    /// ordering decision) so a shared URL always ends up at index 0 regardless of that order —
    /// matching the composer's own URL-first deterministic rule, so `ShareIntake.submit`'s
    /// note-on-first-object rule always lands a share's note on the URL when one is present.
    ///
    /// - Returns: the loaded objects, plus `droppedCount` — `providers.count - objects.count` —
    ///   for every provider that did NOT become a `SharedObject` (Fix round 1, Important review
    ///   finding): a provider with nothing loadable, a `loadItem`/`loadFileRepresentation`
    ///   failure, or a staging throw all look identical to the user (nothing renders for that
    ///   attachment) unless the caller surfaces the count. `ShareComposeView` shows a one-line
    ///   "N item(s) couldn't be read" whenever this is non-zero.
    func load(from items: [NSExtensionItem]) async -> (objects: [SharedObject], droppedCount: Int) {
        let providers = items.flatMap { $0.attachments ?? [] }

        var objects: [SharedObject] = []
        for (index, provider) in providers.enumerated() {
            // Plan 15 Task 4: the load phase (image preparation included) runs while the card is
            // showing, before Save — logged per provider so a slow one stands out.
            let started = ContinuousClock.now
            let object = await loadOne(provider)
            let elapsed = ContinuousClock.now - started
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            let offered = provider.registeredTypeIdentifiers.joined(separator: ",")
            Self.log.notice("load: provider \(index) (\(offered, privacy: .public)) → \(Self.kind(of: object), privacy: .public) in \(ms) ms")
            if let object {
                objects.append(object)
            }
        }
        return (ShareIntake.reorderURLFirst(objects), providers.count - objects.count)
    }

    private static let log = Logger(subsystem: "it.gostash.stash", category: "share")

    /// A log-safe label (never the URL, text, or file name — those are the user's).
    private static func kind(of object: SharedObject?) -> String {
        switch object {
        case .url: "url"
        case .text: "text"
        case .file(_, let mimeType, _, _): "file \(mimeType)"
        case nil: "dropped"
        }
    }

    // MARK: - One provider

    /// What kind of file branch matched — drives staging and the duration probe.
    private enum FileKind { case image, movie, audio, other }

    /// Order matters: `public.file-url` conforms to `public.url` (a local file IS a URL), so a
    /// shared file's own provider would otherwise misroute into the URL/text branches below —
    /// excluding `isFileURL` on both is the standard fix (mirrors Apple's own share/action
    /// extension sample code doing the same "WebURL vs. File" disambiguation). The specific
    /// image/movie/audio/pdf branches run before the generic one so those keep their tailored
    /// staging (image preparation, duration probe, category-correct fallback extension).
    private func loadOne(_ provider: NSItemProvider) async -> SharedObject? {
        let isFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), !isFileURL {
            if let object = await loadURL(provider) { return object }
            // Some senders advertise a URL but can only supply their plain-text representation.
            // Keep trying that representation instead of dropping the attachment.
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), !isFileURL {
            return await loadText(provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await loadFile(provider, typeIdentifier: preferredImageTypeIdentifier(for: provider),
                                  kind: .image, fallbackExtension: "jpg")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.movie.identifier, kind: .movie, fallbackExtension: "mov")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.audio.identifier, kind: .audio, fallbackExtension: "m4a")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await loadFile(provider, typeIdentifier: UTType.pdf.identifier, kind: .other, fallbackExtension: "pdf")
        }
        if let typeIdentifier = genericDataTypeIdentifier(for: provider) {
            let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin"
            return await loadFile(provider, typeIdentifier: typeIdentifier, kind: .other, fallbackExtension: fallbackExtension)
        }
        return nil   // nothing file-backed to stage — dropped (and counted), never crashed on.
    }

    /// Plan 15 review: which image representation to ask for. Asking for the abstract
    /// `public.image` can hand back a camera RAW (DNG etc.) even when the provider also offers a
    /// rendered JPEG/HEIC — a RAW+JPEG pair, or Photos' own rendition — and decoding a RAW is by far
    /// the most expensive thing this extension could do. So: the provider's first registered image
    /// type that is NOT a RAW, else `public.image` (a RAW-only share then takes
    /// `ImagePreparation`'s embedded-preview path).
    private func preferredImageTypeIdentifier(for provider: NSItemProvider) -> String {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) && !type.conforms(to: .rawImage)
        } ?? UTType.image.identifier
    }

    /// Plan 15: the type to request for a provider none of the specific branches claimed. Prefers
    /// the provider's own concrete registered type (the temp file then keeps its real extension,
    /// which is what the mime lookup below keys on) over the abstract `public.data`. URL-typed
    /// representations are skipped: `public.url`/`public.file-url` conform to `public.data`, but
    /// their "data" is the address, not the file's bytes.
    private func genericDataTypeIdentifier(for provider: NSItemProvider) -> String? {
        let concrete = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .url)
        }
        if let concrete { return concrete }
        return provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) ? UTType.data.identifier : nil
    }

    private func loadURL(_ provider: NSItemProvider) async -> SharedObject? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                // Foundation bridges NSURL to URL and NSString to String. Both are valid
                // provider representations; validate String values before treating them as URLs.
                let value = (item as? URL)?.absoluteString ?? (item as? String)
                guard let value, let url = detectWholeWebURL(in: value) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: .url(url))
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> SharedObject? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                // Whitespace-only text has nothing to save (the capture endpoint rejects a blank
                // note with a 400 that no retry could fix).
                guard let text = item as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: .text(text))
            }
        }
    }

    /// One staged file plus what its name should be recorded as.
    private struct Staged {
        let url: URL
        let fileName: String?
    }

    /// Stages a file-backed provider, synchronously inside `loadFileRepresentation`'s completion
    /// handler (the only point this file ever has a valid reference to the temp `URL`).
    ///
    /// Images go through `stagePreparedImage` (plan 15); one ImageIO can't read is staged as its
    /// original bytes instead of being dropped. The recorded name follows the bytes: a re-encoded
    /// image's name gets a `.jpg` extension (`ImagePreparation.fileName`).
    ///
    /// - Parameter fallbackExtension: used ONLY when the provider's own temp `URL` has no extension
    ///   at all (rare in practice). Fix round 1 (Critical review finding): this used to fall back
    ///   to `UTType(typeIdentifier)?.preferredFilenameExtension` — but for the abstract category
    ///   constants (`public.image`/`.movie`/`.audio`) that property is `nil` (verified
    ///   empirically), so the caller that already knows which branch matched passes a literal.
    private func loadFile(_ provider: NSItemProvider, typeIdentifier: String, kind: FileKind,
                          fallbackExtension: String) async -> SharedObject? {
        let suggestedName = provider.suggestedName

        let staged: Staged? = await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else { continuation.resume(returning: nil); return }
                let ext = url.pathExtension.isEmpty ? fallbackExtension : url.pathExtension
                if kind == .image, let prepared = try? staging.stagePreparedImage(from: url) {
                    continuation.resume(returning: Staged(
                        url: prepared.url,
                        fileName: ImagePreparation.fileName(suggestedName, reencoded: prepared.wasReencoded)))
                    return
                }
                continuation.resume(returning: (try? staging.stage(from: url, fileExtension: ext))
                    .map { Staged(url: $0, fileName: suggestedName) })
            }
        }
        guard let staged else { return nil }

        // Derived from the STAGED file's own extension via StashKit's shared map — NEVER from the
        // abstract category `typeIdentifier` (Fix round 1, Critical review finding: reviewer
        // verified `UTType(typeIdentifier)?.preferredMIMEType` returns `nil` for
        // `public.image`/`.movie`/`.audio` on this toolchain — only a concrete type like
        // `com.adobe.pdf` resolves). A prepared image lands on disk as `.jpg` (re-encoded, or a
        // passthrough JPEG) or `.gif`, so it needs no special case either.
        let mimeType = StagedFileStore.mimeType(forFileExtension: staged.url.pathExtension)
        let durationS = (kind == .movie || kind == .audio) ? await probeDuration(url: staged.url) : nil
        return .file(stagedURL: staged.url, mimeType: mimeType, fileName: staged.fileName, durationS: durationS)
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
