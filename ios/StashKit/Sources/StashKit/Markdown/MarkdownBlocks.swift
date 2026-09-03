import Foundation

/// One block of AI-generated (or user-pasted) markdown text, coarse enough for a SwiftUI renderer
/// to lay out block-by-block while leaving inline emphasis (`**bold**`, `*italic*`, links) intact
/// for `AttributedString(markdown:)` to pick up per-block. This is deliberately not a full
/// CommonMark implementation — it recognizes the handful of block types AI summaries actually
/// produce (paragraphs, headings, bullet/numbered lists, blockquotes, fenced code) and falls back
/// to `.paragraph` for anything else, so unrecognized syntax degrades to plain text rather than
/// disappearing or crashing.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, String)
    case bullets([String])
    case numbered([String])
    case quote(String)
    case code(String)
}

/// Parses AI-summary-shaped markdown into `[MarkdownBlock]` and heuristically detects whether a
/// blob of text is worth parsing as markdown at all (vs. rendering as plain text).
public enum MarkdownBlocks {
    /// Line-based state machine — a single forward pass over the input's lines, each line
    /// classified once by cheap prefix/character scans (no regex, so no backtracking hazard on
    /// pathological input; see `MarkdownBlocksTests.testLargeInputParsesQuickly`).
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = normalizedLines(text)

        var paragraphLines: [String] = []
        var bulletItems: [String] = []
        var numberedItems: [String] = []
        var quoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }
        func flushBullets() {
            guard !bulletItems.isEmpty else { return }
            blocks.append(.bullets(bulletItems))
            bulletItems.removeAll()
        }
        func flushNumbered() {
            guard !numberedItems.isEmpty else { return }
            blocks.append(.numbered(numberedItems))
            numberedItems.removeAll()
        }
        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.quote(quoteLines.joined(separator: " ")))
            quoteLines.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushNumbered()
            flushQuote()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushAll()
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 } // consume closing fence, if present
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = headingMatch(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, heading.content))
                index += 1
                continue
            }

            if let item = bulletMatch(trimmed) {
                flushParagraph()
                flushNumbered()
                flushQuote()
                bulletItems.append(item)
                index += 1
                continue
            }

            if let item = numberedMatch(trimmed) {
                flushParagraph()
                flushBullets()
                flushQuote()
                numberedItems.append(item)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                flushNumbered()
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                quoteLines.append(content)
                index += 1
                continue
            }

            flushBullets()
            flushNumbered()
            flushQuote()
            paragraphLines.append(trimmed)
            index += 1
        }

        flushAll()
        return blocks
    }

    /// Faithful port of the web heuristic (`src/components/EditItemContentSection.tsx:27-41`):
    /// `/(^|\n)#{1,6}\s|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|(^|\n)\s*[-*]\s/`. Kept as a single
    /// precompiled `NSRegularExpression` (not re-parsed per call) — this only ever runs once per
    /// render, on a full blob, so it doesn't need the line-based approach `parse` uses.
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return markdownHeuristic.firstMatch(in: text, range: range) != nil
    }

    private static let markdownHeuristic: NSRegularExpression = {
        // swiftlint:disable:next force_try — pattern is a fixed literal, verified at compile time by tests.
        try! NSRegularExpression(pattern: #"(^|\n)#{1,6}\s|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)|(^|\n)\s*[-*]\s"#)
    }()

    // MARK: - Line classification

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func headingMatch(_ trimmed: String) -> (level: Int, content: String)? {
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#", level < 6 {
            level += 1
            index = trimmed.index(after: index)
        }
        guard level > 0, index < trimmed.endIndex, trimmed[index] == " " else { return nil }
        let content = trimmed[trimmed.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (level, content)
    }

    private static let bulletMarkers = ["- ", "* ", "\u{2022} "] // "- ", "* ", "• "

    private static func bulletMatch(_ trimmed: String) -> String? {
        for marker in bulletMarkers where trimmed.hasPrefix(marker) {
            let content = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : content
        }
        return nil
    }

    private static func numberedMatch(_ trimmed: String) -> String? {
        var index = trimmed.startIndex
        var digitCount = 0
        while index < trimmed.endIndex, trimmed[index].isASCII, trimmed[index].isNumber {
            index = trimmed.index(after: index)
            digitCount += 1
        }
        guard digitCount > 0, index < trimmed.endIndex, trimmed[index] == "." else { return nil }
        let afterDot = trimmed.index(after: index)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        let content = trimmed[trimmed.index(after: afterDot)...].trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : content
    }
}
