import Foundation

/// Port of src/utils/chatCitations.ts's `bakeCitationLinks` — the model cites saved items two
/// ways: titles as markdown links targeting the citation number (`[Beyond the Basics](#3)`) and
/// bare bracket markers (`[3]`). This rewrites both into stable item links
/// (`[Beyond the Basics](stash://item/<uuid>)`) using each source's citation number (`ChatSource.n`,
/// the wire's `n` field — never array order, which drifts from the marker numbers whenever an
/// answer skips one: citing `[2]` and `[5]` leaves `sources` with two entries whose `n` are 2 and
/// 5, not 1 and 2).
///
/// Unlike the web (which persists the baked text so links keep working when history reloads
/// without the `sources` array around — chatCitations.ts's own doc comment), iOS calls this fresh
/// on every render from the still-live `message.content`/`message.sources` pair, so there's no
/// need to port `extractLinkedItemIds`/`itemIdFromHref` separately: the ids this pass actually
/// linked are collected as it goes and returned directly as `linkedSourceIDs`.
public enum ChatCitations {
    public static let itemLinkPrefix = "stash://item/"

    /// Single left-to-right scan per pass (not `NSRegularExpression`) — mirrors
    /// `bakeCitationLinks`'s two `.replace()` calls in the same order (linked titles, then bare
    /// markers), but as plain character-index walks so the JS regexes' lookaround (`(?<!\[)`,
    /// `(?!\()`) becomes ordinary "peek at the neighboring character" checks instead of relying on
    /// ICU regex semantics matching JS's exactly.
    public static func link(answer: String, sources: [ChatSource]) -> (text: String, linkedSourceIDs: Set<UUID>) {
        var byN: [Int: UUID] = [:]
        for source in sources {
            if let n = source.n { byN[n] = source.id }
        }
        guard !byN.isEmpty else { return (answer, []) }

        var linkedIDs = Set<UUID>()
        let afterTitles = linkTitles(in: answer, byN: byN, linkedIDs: &linkedIDs)
        let afterMarkers = linkBareMarkers(in: afterTitles, byN: byN, linkedIDs: &linkedIDs)
        return (afterMarkers, linkedIDs)
    }

    /// `](#3)` → `](stash://item/<uuid>)`, i.e. the href half of `[Title](#3)` — the `[Title`
    /// text before it is untouched.
    private static func linkTitles(in text: String, byN: [Int: UUID], linkedIDs: inout Set<UUID>) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "]", i + 2 < chars.count, chars[i + 1] == "(", chars[i + 2] == "#",
               let (n, afterDigits) = readNumber(chars, from: i + 3), afterDigits < chars.count, chars[afterDigits] == ")",
               let id = byN[n] {
                result += "](\(itemLinkPrefix)\(id.uuidString))"
                linkedIDs.insert(id)
                i = afterDigits + 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Bare `[3]` → `[[3]](stash://item/<uuid>)`, skipping ones already wrapped in an outer `[`
    /// (`(?<!\[)`, e.g. the inner `[1]` of an already-baked `[[1]](...)`) or already followed by
    /// `(` (`(?!\()`, i.e. already link text).
    private static func linkBareMarkers(in text: String, byN: [Int: UUID], linkedIDs: inout Set<UUID>) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "[", i == 0 || chars[i - 1] != "[",
               let (n, afterDigits) = readNumber(chars, from: i + 1), afterDigits < chars.count, chars[afterDigits] == "]",
               afterDigits + 1 >= chars.count || chars[afterDigits + 1] != "(",
               let id = byN[n] {
                result += "[[\(n)]](\(itemLinkPrefix)\(id.uuidString))"
                linkedIDs.insert(id)
                i = afterDigits + 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Reads a run of ASCII digits starting at `start`; nil if `start` isn't a digit (covers the
    /// malformed-marker case, e.g. `[abc]`, same as the JS regexes' `\d+` requiring at least one
    /// digit).
    private static func readNumber(_ chars: [Character], from start: Int) -> (value: Int, end: Int)? {
        var end = start
        while end < chars.count, chars[end].isASCII, chars[end].isNumber {
            end += 1
        }
        guard end > start, let value = Int(String(chars[start..<end])) else { return nil }
        return (value, end)
    }
}
