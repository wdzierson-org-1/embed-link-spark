import Foundation
import RegexBuilder

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
        let endIndex = text.index(text.startIndex, offsetBy: match.range.upperBound.utf16Offset(in: text))
        let noteText = String(text[endIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .saveNote(noteText)
    }

    // Check for URL
    if let match = try? Regex("https?://[^\\s]+").firstMatch(in: text) {
        let matchedText = String(text[match.range])
        var url = matchedText

        // Strip trailing punctuation from URL
        while let last = url.last, ".,!?;)]".contains(last) {
            url.removeLast()
        }

        // Remove the original matched text from the full text to get the note (only first occurrence)
        var mutableText = text
        let startIndex = mutableText.index(mutableText.startIndex, offsetBy: match.range.lowerBound.utf16Offset(in: mutableText))
        let endIndex = mutableText.index(mutableText.startIndex, offsetBy: match.range.upperBound.utf16Offset(in: mutableText))
        mutableText.replaceSubrange(startIndex..<endIndex, with: "")

        let note = mutableText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return .saveURL(url: url, note: note)
    }

    return .ask
}
