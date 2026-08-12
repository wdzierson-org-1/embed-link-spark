import Foundation

/// Joins a composer's already-typed prefix with a live dictation interim result. Used by the Ask
/// composer (`AskView`) so that starting/restarting dictation never wipes text the user already
/// typed (or a previous dictation pass already produced) — the prefix is captured once when
/// listening starts, and every interim update re-merges against that same, unchanging prefix.
///
/// - Empty `prefix` (nothing typed yet) returns `interim` verbatim — the common case, dictating
///   into an empty composer.
/// - Otherwise, exactly one separating space goes between `prefix` and `interim` — never doubled
///   when `prefix` already ends in whitespace (e.g. the user typed "note: " before tapping mic).
public func mergeDictation(prefix: String, interim: String) -> String {
    guard !prefix.isEmpty else { return interim }
    if let last = prefix.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
        return prefix + interim
    }
    return prefix + " " + interim
}
