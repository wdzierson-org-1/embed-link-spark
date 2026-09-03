import Foundation

/// Port of src/utils/chatCitations.ts's `bakeCitationLinks`/`extractLinkedItemIds` — the model
/// cites saved items two ways: titles as markdown links targeting the citation number
/// (`[Beyond the Basics](#3)`) and bare bracket markers (`[3]`). This rewrites both into stable
/// item links using each source's citation number (`ChatSource.n`, the wire's `n` field — never
/// array order, which drifts from the marker numbers whenever an answer skips one: citing `[2]`
/// and `[5]` leaves `sources` with two entries whose `n` are 2 and 5, not 1 and 2).
///
/// Fix round 1 (task-4-report.md): `ChatStore` now bakes and persists this exact text before
/// saving, matching the web (`ChatMole.tsx:357-361` — `persistMessage('assistant', baked, …)`), so
/// the two platforms share one `messages.content` convention and a reload never needs the
/// `sources` array to keep a citation clickable. That's why `itemLinkPrefix` had to become the
/// web's own `#item=` (was iOS-only `stash://item/` in round 1) — verified against
/// `AttributedString(markdown:)`: `[Title](#item=<uuid>)` parses as a real link with
/// `.fragment == "item=<uuid>"`, `.scheme == nil` (see ChatCitationsTests). `legacyItemLinkPrefix`
/// stays recognized (never written) for any row round 1 baked with the old scheme before this fix.
public enum ChatCitations {
    public static let itemLinkPrefix = "#item="
    /// Read-only back-compat: round 1 of this task briefly baked `stash://item/<uuid>` before the
    /// cross-platform convention was corrected to match the web's `#item=`. No code writes this
    /// anymore; `itemID(from:)` and `linkedSourceIDs` still recognize it so nothing already baked
    /// that way goes dead.
    public static let legacyItemLinkPrefix = "stash://item/"

    /// Single left-to-right scan per pass (not `NSRegularExpression`) — mirrors
    /// `bakeCitationLinks`'s two `.replace()` calls in the same order (linked titles, then bare
    /// markers), but as plain character-index walks so the JS regexes' lookaround (`(?<!\[)`,
    /// `(?!\()`) becomes ordinary "peek at the neighboring character" checks instead of relying on
    /// ICU regex semantics matching JS's exactly.
    ///
    /// `linkedSourceIDs` is derived by re-scanning the RESULT for item-link hrefs (`itemID(from:)`
    /// applied to every link found), not by tracking only what THIS call freshly baked — so it
    /// also reports ids that arrived already-linked (idempotence: calling `link` again on
    /// already-baked text, e.g. a reloaded persisted answer, still reports the same
    /// `linkedSourceIDs` even though nothing gets re-baked). This is what lets `ChatBubble`'s
    /// per-source chip filter work correctly on both a fresh answer and a reloaded one.
    public static func link(answer: String, sources: [ChatSource]) -> (text: String, linkedSourceIDs: Set<UUID>) {
        var byN: [Int: UUID] = [:]
        for source in sources {
            if let n = source.n { byN[n] = source.id }
        }
        let baked: String
        if byN.isEmpty {
            baked = answer
        } else {
            baked = linkBareMarkers(in: linkTitles(in: answer, byN: byN), byN: byN)
        }
        return (baked, linkedItemIDs(in: baked))
    }

    /// Strips `[Title](#N)` markers that never resolved into an item link — e.g. a reloaded
    /// message with no matching source (an older row persisted before this fix round baked raw
    /// `streamed` text, or a citation number that genuinely has no source) — down to plain `Title`
    /// text. Without this, the raw `(#N)` href is still valid, parseable markdown
    /// (`AttributedString(markdown:)` accepts any `#`-fragment URL), so it would reach
    /// `MarkdownBlocksView` as a violet, tappable-looking link that goes nowhere.
    ///
    /// Deliberately unconditional rather than gated on "only when `sources` is empty" (the
    /// originally-suggested trigger): a message can have SOME sources but still leave one citation
    /// number unresolved (unknown/out-of-range `[Title](#N)`), and stripping is a no-op wherever
    /// nothing needs it — a `[Title](#N)` that DID resolve is already `[Title](#item=<uuid>)` (or
    /// the legacy `stash://item/` form) by the time this runs, a different, unaffected pattern, so
    /// applying this unconditionally after every `link(...)` call is strictly safer than
    /// conditioning it on the caller's source count. `ChatBubble` calls this on every render.
    public static func stripUnresolvedMarkers(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "[", let titleEnd = chars[(i + 1)...].firstIndex(of: "]") {
                let afterTitle = titleEnd + 1
                if afterTitle + 2 < chars.count, chars[afterTitle] == "(", chars[afterTitle + 1] == "#",
                   let (_, afterDigits) = readNumber(chars, from: afterTitle + 2), afterDigits < chars.count, chars[afterDigits] == ")" {
                    result += String(chars[(i + 1)..<titleEnd])
                    i = afterDigits + 1
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Parses an item id back out of either href form this file bakes/recognizes: `#item=<uuid>`
    /// (current, cross-platform — a `URL`'s `.fragment`) or `stash://item/<uuid>` (legacy). Used
    /// both to compute `linkedSourceIDs` and by `AskView`'s `.environment(\.openURL, …)` handler,
    /// so the two stay in lockstep by construction — a link this file will style as tappable is
    /// exactly one this same function can route to `onCitationTap`.
    public static func itemID(from url: URL) -> UUID? {
        if let fragment = url.fragment, fragment.hasPrefix("item=") {
            return UUID(uuidString: String(fragment.dropFirst("item=".count)))
        }
        if url.scheme == "stash" {
            return UUID(uuidString: url.lastPathComponent)
        }
        return nil
    }

    /// `](#3)` → `](#item=<uuid>)`, i.e. the href half of `[Title](#3)` — the `[Title` text before
    /// it is untouched. `id.uuidString.lowercased()` (final wave, item A): `UUID.uuidString` is
    /// UPPERCASE, but the web's own `extractLinkedItemIds` matches hrefs with `/[0-9a-f-]+/` — an
    /// uppercase-baked id simply never matches that regex at all, so a note taken/answered on iOS
    /// and later reloaded on web rendered as a dead link. `itemID(from:)` below stays
    /// case-insensitive on READ (`UUID(uuidString:)` already accepts either case), so this is the
    /// only site that needed to change — bake lowercase, read either.
    private static func linkTitles(in text: String, byN: [Int: UUID]) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "]", i + 2 < chars.count, chars[i + 1] == "(", chars[i + 2] == "#",
               let (n, afterDigits) = readNumber(chars, from: i + 3), afterDigits < chars.count, chars[afterDigits] == ")",
               let id = byN[n] {
                result += "](\(itemLinkPrefix)\(id.uuidString.lowercased()))"
                i = afterDigits + 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Bare `[3]` → `[[3]](#item=<uuid>)`, skipping ones already wrapped in an outer `[`
    /// (`(?<!\[)`, e.g. the inner `[1]` of an already-baked `[[1]](...)`) or already followed by
    /// `(` (`(?!\()`, i.e. already link text). Lowercased for the same cross-platform reason
    /// `linkTitles` above is.
    private static func linkBareMarkers(in text: String, byN: [Int: UUID]) -> String {
        let chars = Array(text)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "[", i == 0 || chars[i - 1] != "[",
               let (n, afterDigits) = readNumber(chars, from: i + 1), afterDigits < chars.count, chars[afterDigits] == "]",
               afterDigits + 1 >= chars.count || chars[afterDigits + 1] != "(",
               let id = byN[n] {
                result += "[[\(n)]](\(itemLinkPrefix)\(id.uuidString.lowercased()))"
                i = afterDigits + 1
                continue
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    /// Every item id already linked in `text`, however it got there — freshly baked this call, or
    /// already baked before this call ever ran (a reloaded persisted answer, whose `content` is
    /// baked at persist time and needs no `sources` to stay clickable). Port of the web's
    /// `extractLinkedItemIds`, generalized to recognize both href forms.
    private static func linkedItemIDs(in text: String) -> Set<UUID> {
        var ids = Set<UUID>()
        for prefix in [itemLinkPrefix, legacyItemLinkPrefix] {
            var searchStart = text.startIndex
            while let prefixRange = text.range(of: prefix, range: searchStart..<text.endIndex) {
                let idStart = prefixRange.upperBound
                guard let closeParen = text[idStart...].firstIndex(of: ")") else { break }
                if let id = UUID(uuidString: String(text[idStart..<closeParen])) {
                    ids.insert(id)
                }
                searchStart = closeParen
            }
        }
        return ids
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
