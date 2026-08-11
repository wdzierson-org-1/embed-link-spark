import Foundation

/// Minimal read-only renderer for Novel/TipTap JSON stored in items.content.
/// Handles doc/paragraph/heading/bulletList/orderedList/listItem/text with
/// bold+italic marks; anything unrecognized falls back to its text content.
/// Non-JSON input (plain-text notes are valid platform-wide) passes through.
public func renderTipTap(_ raw: String?) -> AttributedString {
    guard let raw, !raw.isEmpty else { return AttributedString() }
    guard raw.hasPrefix("{"),
          let data = raw.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          root["type"] as? String == "doc"
    else { return AttributedString(raw) }

    var out = AttributedString()
    render(nodes: root["content"] as? [[String: Any]] ?? [], into: &out, listDepth: 0)
    while out.characters.last == "\n" { out.removeSubrange(out.index(beforeCharacter: out.endIndex)..<out.endIndex) }
    return out
}

private func render(nodes: [[String: Any]], into out: inout AttributedString, listDepth: Int) {
    for node in nodes {
        let type = node["type"] as? String
        let children = node["content"] as? [[String: Any]] ?? []
        switch type {
        case "text":
            var run = AttributedString(node["text"] as? String ?? "")
            let marks = (node["marks"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String }
            if marks.contains("bold") { run.inlinePresentationIntent = .stronglyEmphasized }
            if marks.contains("italic") {
                run.inlinePresentationIntent = marks.contains("bold")
                    ? [.stronglyEmphasized, .emphasized] : .emphasized
            }
            out += run
        case "heading":
            var heading = AttributedString()
            render(nodes: children, into: &heading, listDepth: listDepth)
            heading.inlinePresentationIntent = .stronglyEmphasized
            out += heading + AttributedString("\n\n")
        case "paragraph":
            render(nodes: children, into: &out, listDepth: listDepth)
            out += AttributedString(listDepth > 0 ? "\n" : "\n\n")
        case "bulletList", "orderedList":
            render(nodes: children, into: &out, listDepth: listDepth + 1)
            out += AttributedString("\n")
        case "listItem":
            out += AttributedString(String(repeating: "  ", count: max(0, listDepth - 1)) + "• ")
            render(nodes: children, into: &out, listDepth: listDepth)
        default:
            render(nodes: children, into: &out, listDepth: listDepth)
        }
    }
}
