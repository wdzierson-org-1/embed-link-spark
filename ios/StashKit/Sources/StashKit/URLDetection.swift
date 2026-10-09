import Foundation

// "What counts as a URL" for the capture composer (`CaptureViewModel.route()` and
// `CaptureComposerView`'s URL chip).
//
// Formerly `MessageRouting.swift`, which also held the Ask tab's chat-as-capture router
// (`classifyMessage` — a URL or a `remember:/save:/note:` prefix turned a question into a save).
// Plan 15 removed that router: Ask is retrieval-only on every platform (`docs/ui-changes.md`,
// 2026-08-27 "Mole is retrieval-only"), so only the composer's URL helpers remain here.

/// Single source of truth for URL detection between `detectFirstURL` and its callers.
let urlDetectionPattern = "https?://[^\\s]+"

/// Strips trailing sentence punctuation a URL regex match tends to capture (e.g. the "." in
/// "check this out https://x.com."). Used by `CaptureViewModel`.
func stripTrailingPunctuation(_ url: String) -> String {
    var url = url
    while let last = url.last, ".,!?;)]".contains(last) {
        url.removeLast()
    }
    return url
}

/// First `https?://` URL substring in `text`, raw (no trailing-punctuation cleanup) — nil if
/// none found. Used by the capture composer for both the URL chip (truncated for display, so a
/// stray trailing character is harmless) and as the routing signal for "does this text contain
/// a URL" (someone typing "note: check this out https://x.com" into the composer expects the URL
/// to route to add-url, not to be swallowed as a plain note).
public func detectFirstURL(in text: String) -> String? {
    (try? Regex(urlDetectionPattern).firstMatch(in: text)).map { String(text[$0.range]) }
}

/// A share provider can label a URL as plain text (YouTube does this). Promote it only when
/// the WHOLE value is one HTTP(S) URL; a note or quote containing a link remains text.
/// Preserve the original query and fragment, which can identify a video, variant, or timestamp.
/// Keep this narrow classification aligned with the capture API's `singleHttpUrl` guard.
public func detectWholeWebURL(in text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }),
          trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "\\<>\"`")) == nil,
          let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = components.host, !host.isEmpty,
          (components.user ?? "").isEmpty, (components.password ?? "").isEmpty,
          components.url != nil else { return nil }
    return trimmed
}
