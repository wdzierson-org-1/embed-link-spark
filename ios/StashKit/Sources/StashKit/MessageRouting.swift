import Foundation

public enum RoutedMessage: Equatable, Sendable {
    case saveURL(url: String, note: String)
    case saveNote(String)
    case ask
}

// Port of src/utils/moleRouting.ts — keep rules few and predictable.
public func classifyMessage(_ raw: String) -> RoutedMessage {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check for prefix: remember/save/note (case-insensitive)
    if let match = try? Regex("^(?i)(remember|save|note):\\s*").firstMatch(in: text) {
        return .saveNote(String(text[match.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Check for URL
    if let match = try? Regex("https?://[^\\s]+").firstMatch(in: text) {
        let matchedText = String(text[match.range])
        var url = matchedText

        // Strip trailing punctuation from URL
        while let last = url.last, ".,!?;)]".contains(last) {
            url.removeLast()
        }

        let note = text.replacingCharacters(in: match.range, with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return .saveURL(url: url, note: note)
    }

    return .ask
}
