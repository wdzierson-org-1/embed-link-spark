import Foundation

/// Validation and metadata invalidation for an explicitly committed source address.
public enum LinkAddressEdit {
    /// Web parity: trim surrounding whitespace, supply HTTPS for a bare hostname, and
    /// accept only HTTP(S) addresses with a dotted host. The rest of the address is retained.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let hasScheme = trimmed.range(of: "^[a-z][a-z0-9+.-]*:", options: [.regularExpression, .caseInsensitive]) != nil
        guard var components = URLComponents(string: hasScheme ? trimmed : "https://\(trimmed)"),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.user == nil, components.password == nil,
              let host = components.host, host.contains("."), !host.contains("\\") else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        if components.path.isEmpty { components.path = "/" }
        return components.url?.absoluteString
    }

    public static func applying(_ address: String, to item: Item) -> Item {
        var next = item
        next.url = address
        next.attributes = item.attributes.invalidatingLinkAddress()
        return next
    }

    /// Merge only the queued location, if any, onto the server's current metadata before
    /// invalidating facts about the old address. Never replay a captured attributes blob.
    public static func preparing(_ patch: ItemPatch, currentAttributes: ItemAttributes) -> ItemPatch {
        guard patch.url != nil else { return patch }
        var attributes = currentAttributes
        if let locationEdit = patch.attributes { attributes.location = locationEdit.location }
        var prepared = patch
        prepared.attributes = attributes.invalidatingLinkAddress()
        return prepared
    }
}

public extension ItemAttributes {
    func invalidatingLinkAddress() -> ItemAttributes {
        var next = self
        // All link facts describe the old address (flavor, canonical URL, provider/video IDs,
        // author, duration, embed URL). Other attribute namespaces belong to the saved item.
        next.link = nil
        next.extra.removeValue(forKey: "link") // Includes a malformed forward-compatible blob.
        if case .object(var enrichment) = next.extra["enrichment"] {
            enrichment.removeValue(forKey: "evidence")
            next.extra["enrichment"] = .object(enrichment)
        }
        return next
    }
}
