import Foundation

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
