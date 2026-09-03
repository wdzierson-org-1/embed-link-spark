import Foundation

/// Reads back the trailing paragraph's plain text from `content` if (and only if) it parses as
/// TipTap JSON — nil for plain text, malformed JSON, or an empty document. Used by the rich-notes
/// append idempotence guard (Plan 8 final wave, item C / minor 6): `ItemDetailView.flushNotes()`
/// only applies a `SaveGeneration`-guarded save response when it's still the latest one, so a
/// response dropped because a newer save (e.g. a racing field autosave) won can leave a rich
/// append that DID land server-side without ever updating local `item.content` — a later flush
/// would otherwise re-append the exact same draft onto the stale local content, duplicating the
/// paragraph. If a realtime/`adopt` refresh has since folded that server-side append back into
/// `item.content` (the common case, given the two saves are usually only milliseconds apart),
/// this lets the caller recognize "already there" and skip re-saving instead of trusting the
/// draft's local "still pending" state alone. Not a complete fix — if the refresh hasn't landed
/// yet, this returns the OLD trailing paragraph and the duplicate can still happen once — but it
/// closes the common case with no extra round trip.
public func tipTapLastParagraphText(_ content: String?) -> String? {
    guard let content, content.hasPrefix("{"),
          let data = content.data(using: .utf8),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          root["type"] as? String == "doc",
          let children = root["content"] as? [[String: Any]],
          let last = children.last,
          let inline = last["content"] as? [[String: Any]]
    else { return nil }
    return inline.compactMap { $0["text"] as? String }.joined()
}

public func appendNoteParagraph(to content: String?, note: String) -> String {
    guard let content, !content.isEmpty else { return note }
    guard content.hasPrefix("{"),
          let data = content.data(using: .utf8),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          root["type"] as? String == "doc"
    else { return content + "\n\n" + note }

    var children = root["content"] as? [[String: Any]] ?? []
    children.append(["type": "paragraph", "content": [["type": "text", "text": note]]])
    root["content"] = children
    guard let out = try? JSONSerialization.data(withJSONObject: root),
          let string = String(data: out, encoding: .utf8) else { return content + "\n\n" + note }
    return string
}
