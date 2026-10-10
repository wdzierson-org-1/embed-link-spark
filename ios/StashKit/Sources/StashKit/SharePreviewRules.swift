import Foundation

/// Display-only evidence for the share card; never serialized into a capture.
public struct SharePreviewText: Equatable, Sendable {
    public let title: String?
    public let summary: String?
    public init(title: String?, summary: String?) { self.title = title; self.summary = summary }
}

public enum SharePreviewRules {
    public static func clean(_ text: String?, limit: Int = 160) -> String? {
        guard let text, limit > 0 else { return nil }
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            .filter { !$0.isEmpty }.joined(separator: " ")
        let value = String(words.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Preview is optional: reject local addresses, credentials and IP literals. This
    /// is not a DNS security boundary; the server remains responsible for its fetches.
    public static func publicWebURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.user == nil, url.password == nil,
              url.port == nil || url.port == (scheme == "https" ? 443 : 80),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.contains(":"), host.contains("."),
              let suffix = host.split(separator: ".").last,
              suffix.contains(where: { $0.isLetter }),
              !["local", "localhost", "internal", "home", "lan", "test", "invalid", "onion"].contains(String(suffix))
        else { return nil }
        return url
    }

    public static func recognizedText(_ lines: [String], document: Bool = false) -> SharePreviewText? {
        guard let line = lines.lazy.compactMap({ clean($0, limit: 100) }).first(where: { $0.count >= 3 }) else { return nil }
        return SharePreviewText(title: "“\(line)”", summary: document ? "Text found on first page" : "Text found in image")
    }

    public static func title(supplied: String?, enriched: String?, fallback: String?) -> String? {
        clean(supplied) ?? clean(enriched) ?? clean(fallback)
    }
}
