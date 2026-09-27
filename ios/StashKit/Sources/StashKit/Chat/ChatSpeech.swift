import Foundation

/// Plan 15 (M3): what read-aloud actually speaks. Answers are markdown with baked citation links
/// (`[Title](#item=<uuid>)`, `[[1]](#item=<uuid>)`), so speaking `message.content` raw read out
/// brackets, "item equals" and 36-character UUIDs.
public enum ChatSpeech {
    /// Port of the web's `stripForSpeech` (src/components/ChatMole.tsx:56-62), same four steps in
    /// the same order with JavaScript's semantics kept exact (`\d` is ASCII-only, `\s` is JS's
    /// whitespace set, `.trim()` after the collapse):
    ///
    ///   1. `[text](href)` → `text`   2. `[n]` → ``   3. drop `* _ # \` >`   4. collapse whitespace, trim
    ///
    /// plus ONE iOS pre-pass, `[[n]](href)` → `` — a baked bare citation marker. The web's step 1
    /// can't match it (`[^\]]*` stops at the inner `]`) and step 2 then leaves `[](item=<uuid>)`,
    /// so the web itself still reads the UUID for every bare citation (verified with node against
    /// the web function; flagged for a web follow-up). For any text without that pattern the
    /// output is byte-identical to the web's.
    public static func speakableText(from markdown: String) -> String {
        var text = markdown
        text = replaceAll(bakedBareMarker, in: text, with: "")
        text = replaceAll(markdownLink, in: text, with: "$1")
        text = replaceAll(bareMarker, in: text, with: "")
        text = replaceAll(markupCharacters, in: text, with: "")
        text = replaceAll(whitespaceRun, in: text, with: " ")
        // After the collapse every whitespace run is a single U+0020, so trimming spaces is
        // exactly JS `.trim()` here.
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    private static let bakedBareMarker = regex(#"\[\[[0-9]+\]\]\([^)]*\)"#)
    private static let markdownLink = regex(#"\[([^\]]*)\]\([^)]*\)"#)
    private static let bareMarker = regex(#"\[([0-9]+)\]"#)
    private static let markupCharacters = regex("[*_#`>]")
    /// JavaScript's `\s` (ECMA-262 WhiteSpace + LineTerminator) spelled out — ICU's `\s` differs
    /// (it lacks U+000B and U+FEFF).
    private static let whitespaceRun = regex(#"[\t\n\u000B\f\r    -     　﻿]+"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Constant patterns — a failure here is a programming error caught by ChatSpeechTests.
        try! NSRegularExpression(pattern: pattern)
    }

    /// UTF-16 based (NSString ranges), so `\r\n` graphemes and non-BMP characters can't skew
    /// match offsets the way a Character-indexed walk would.
    private static func replaceAll(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                       withTemplate: template)
    }
}
