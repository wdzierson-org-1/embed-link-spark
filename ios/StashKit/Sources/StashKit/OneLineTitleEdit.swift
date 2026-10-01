import Foundation

/// What the detail sheet's title field should hold after a change that put a line break into it
/// (plan 16, 2b review I-1). The title wraps — a vertical-axis field, a text view underneath — so
/// the keyboard's "done" reaches it as a line break, while a title is one line of text.
///
/// The change is classified by what it INSERTED: the new text between the longest common prefix
/// and suffix it shares with the old (grapheme by grapheme, so CRLF is one line break). Comparing
/// whole strings read two ordinary "done" presses as pastes: over a selected word (the text view
/// replaces the selection with the line break) the word became a space, and "done" that also
/// accepted an autocorrection ("Grocries" → "Groceries" plus the line break, in one change) left
/// a trailing space — both with the keyboard still up, and autosaved.
/// - Only a line break was inserted: a bare "done", with or without a selection. The title stays
///   as it was and editing ends.
/// - The insertion ends in its only line break: "done" accepting an autocorrection, or a paste
///   ending in a line break. The text stays, without that break, and editing ends.
/// - Anything else (a paste with line breaks inside it): every line break becomes a space, and
///   editing goes on.
public struct OneLineTitleEdit: Equatable, Sendable {
    /// What the field should hold.
    public var title: String?
    /// Whether the field should give up focus — "done" was pressed.
    public var endsEditing: Bool

    public init(title: String?, endsEditing: Bool) {
        self.title = title
        self.endsEditing = endsEditing
    }

    /// The edit for a change of the title from `old` to `new`, or nil when `new` holds no line
    /// break (nothing to do).
    public static func resolve(old: String?, new: String?) -> OneLineTitleEdit? {
        guard let new, new.contains(where: \.isNewline) else { return nil }
        let before = Array(old ?? "")
        let after = Array(new)
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        let inserted = after[prefix ..< after.count - suffix]

        if inserted.count == 1, inserted.first?.isNewline == true {
            return OneLineTitleEdit(title: old, endsEditing: true)
        }
        if let last = inserted.last, last.isNewline, !inserted.dropLast().contains(where: \.isNewline) {
            var kept = after
            kept.remove(at: after.count - suffix - 1)
            return OneLineTitleEdit(title: oneLine(kept), endsEditing: true)
        }
        return OneLineTitleEdit(title: oneLine(after), endsEditing: false)
    }

    /// `characters` as one line: every line break a space.
    private static func oneLine(_ characters: [Character]) -> String {
        String(characters.map { $0.isNewline ? " " : $0 })
    }
}
