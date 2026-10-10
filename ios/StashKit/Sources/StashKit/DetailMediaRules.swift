import Foundation

public struct DetailVideoEmbed: Hashable, Sendable {
    public enum Provider: String, Sendable { case youtube, vimeo, loom, tiktok, instagram }
    public let provider: Provider
    public let url: URL
    public let originalURL: URL
    public let portrait: Bool
    public var aspectRatio: Double { portrait ? 9.0 / 16 : 16.0 / 9 }
    public var label: String {
        switch provider {
        case .youtube: "YouTube video"
        case .vimeo: "Vimeo video"
        case .loom: "Loom video"
        case .tiktok: "TikTok video"
        case .instagram: "Instagram video"
        }
    }
}

public enum DetailMediaSource: Hashable, Sendable {
    public enum FileKind: Sendable { case video, audio }
    case file(url: URL, kind: FileKind)
    case embed(DetailVideoEmbed)

    public var originalURL: URL {
        switch self { case .file(let url, _): url; case .embed(let embed): embed.originalURL }
    }
    public var label: String {
        switch self { case .file(_, let kind): kind == .audio ? "Audio" : "Video"; case .embed(let embed): embed.label }
    }
    public var portrait: Bool { if case .embed(let embed) = self { embed.portrait } else { false } }
    public var aspectRatio: Double { if case .embed(let embed) = self { embed.aspectRatio } else { 16.0 / 9 } }
    public var isAudio: Bool { if case .file(_, .audio) = self { true } else { false } }
}

public enum DetailMediaRules {
    /// Video-only subset of web utils/embeds.ts. Documents retain their existing detail UI.
    public static func source(for item: Item) -> DetailMediaSource? {
        if item.type == .video || item.type == .audio {
            guard let path = item.filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
            let url: URL
            if URLComponents(string: path)?.scheme != nil {
                guard let remote = webURL(path) else { return nil }
                url = remote
            } else {
                url = StashConfig.publicStorageURL(for: path)
            }
            return .file(url: url, kind: item.type == .audio ? .audio : .video)
        }
        guard item.type == .link else { return nil }
        let linkCanonical = text(item.attributes.link?.extra["canonical_url"])
        var evidenceCanonical: String?
        if case .object(let enrichment) = item.attributes.extra["enrichment"],
           case .object(let evidence) = enrichment["evidence"] {
            evidenceCanonical = text(evidence["canonical_url"])
        }
        // Keep the same precedence as the web: a saved share short link can be played using
        // its server-resolved canonical address, without rewriting the person's source URL.
        guard let address = linkCanonical ?? evidenceCanonical ?? item.url,
              let embed = embed(for: address) else { return nil }
        return .embed(DetailVideoEmbed(provider: embed.provider, url: embed.url,
            originalURL: item.url.flatMap(webURL) ?? embed.originalURL, portrait: embed.portrait))
    }

    public static func embed(for address: String) -> DetailVideoEmbed? {
        guard let original = webURL(address), let hostValue = original.host?.lowercased() else { return nil }
        let host = hostValue.hasPrefix("www.") ? String(hostValue.dropFirst(4)) : hostValue
        let segments = original.path.split(separator: "/").map(String.init)
        func make(_ provider: DetailVideoEmbed.Provider, _ address: String, portrait: Bool = false) -> DetailVideoEmbed? {
            guard let url = URL(string: address) else { return nil }
            return DetailVideoEmbed(provider: provider, url: url, originalURL: original, portrait: portrait)
        }

        // Domain boundaries matter: youtube.com.evil.test is never a YouTube player.
        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") {
            var id: String?
            if host == "youtu.be" { id = segments.first }
            else {
                id = URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
                if id == nil, let marker = segments.firstIndex(where: { ["embed", "shorts", "live"].contains($0) }),
                   segments.indices.contains(marker + 1) { id = segments[marker + 1] }
            }
            guard let id, matches(id, "^[A-Za-z0-9_-]{11}$") else { return nil }
            // Inline playback is the native addition; no player is given autoplay permission.
            return make(.youtube, "https://www.youtube-nocookie.com/embed/\(id)?rel=0&enablejsapi=1&playsinline=1",
                        portrait: host != "youtu.be" && segments.first == "shorts")
        }
        if host == "vimeo.com" || host == "player.vimeo.com" {
            guard let id = segments.first(where: { matches($0, "^[0-9]{6,}$") }) else { return nil }
            return make(.vimeo, "https://player.vimeo.com/video/\(id)")
        }
        if host == "loom.com" {
            guard segments.count >= 2, ["share", "embed"].contains(segments[0]),
                  matches(segments[1], "^[A-Fa-f0-9]{20,}$") else { return nil }
            return make(.loom, "https://www.loom.com/embed/\(segments[1])")
        }
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            guard let marker = segments.firstIndex(of: "video"), segments.indices.contains(marker + 1),
                  matches(segments[marker + 1], "^[0-9]{10,}$") else { return nil }
            return make(.tiktok, "https://www.tiktok.com/embed/v2/\(segments[marker + 1])", portrait: true)
        }
        if host == "instagram.com" {
            guard segments.count >= 2, ["reel", "reels", "p", "tv"].contains(segments[0]),
                  matches(segments[1], "^[A-Za-z0-9_-]{5,}$") else { return nil }
            let kind = segments[0] == "reels" ? "reel" : segments[0]
            return make(.instagram, "https://www.instagram.com/\(kind)/\(segments[1])/embed/", portrait: true)
        }
        return nil
    }

    private static func webURL(_ address: String) -> URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.port == nil || url.port == 80 || url.port == 443 else { return nil }
        return url
    }
    private static func text(_ value: JSONValue?) -> String? {
        guard case .string(let text) = value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
