import Foundation

public enum RoutedMessage: Equatable, Sendable {
    case saveURL(url: String, note: String)
    case saveNote(String)
    case ask
}

/// Shared by `classifyMessage`'s URL branch and the capture composer's `detectFirstURL` below —
/// single source of truth for "what counts as a URL" between the two call sites.
let urlDetectionPattern = "https?://[^\\s]+"

/// Strips trailing sentence punctuation a URL regex match tends to capture (e.g. the "." in
/// "check this out https://x.com."). Shared by `classifyMessage` and `CaptureViewModel`.
func stripTrailingPunctuation(_ url: String) -> String {
    var url = url
    while let last = url.last, ".,!?;)]".contains(last) {
        url.removeLast()
    }
    return url
}

// Port of src/utils/moleRouting.ts — keep rules few and predictable.
public func classifyMessage(_ raw: String) -> RoutedMessage {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check for prefix: remember/save/note (case-insensitive)
    if let match = try? Regex("^(?i)(remember|save|note):\\s*").firstMatch(in: text) {
        return .saveNote(String(text[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Check for URL
    if let match = try? Regex(urlDetectionPattern).firstMatch(in: text) {
        let url = stripTrailingPunctuation(String(text[match.range]))

        let note = text.replacingCharacters(in: match.range, with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return .saveURL(url: url, note: note)
    }

    return .ask
}

/// First `https?://` URL substring in `text`, raw (no trailing-punctuation cleanup) — nil if
/// none found. Used by the capture composer for both the URL chip (truncated for display, so a
/// stray trailing character is harmless) and as the routing signal for "does this text contain
/// a URL". Deliberately NOT built on top of `classifyMessage`: that function's
/// "remember:/save:/note:" prefix takes precedence over URL detection, which is right for its
/// chat-command use case but wrong for a composer with an explicit Save button — someone typing
/// "note: check this out https://x.com" into the composer still expects the URL to route to
/// add-url, not to be swallowed as a plain note.
public func detectFirstURL(in text: String) -> String? {
    (try? Regex(urlDetectionPattern).firstMatch(in: text)).map { String(text[$0.range]) }
}
