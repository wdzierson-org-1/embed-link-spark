import Foundation

// github.com/<first-segment> paths that are product pages, not repos
private let GITHUB_NON_REPO_ROOTS: Set<String> = [
    "features", "pricing", "topics", "collections", "orgs", "settings",
    "marketplace", "sponsors", "about", "blog", "explore", "trending",
    "issues", "pulls", "notifications", "search", "login", "join", "apps",
    "enterprise", "customer-stories", "readme", "new", "codespaces",
]

/// Extracts the domain from a URL, removing the `www.` prefix if present.
/// Returns an empty string if the URL is nil or invalid.
public func domainOf(_ url: String?) -> String {
    guard let url = url else { return "" }
    guard let parsed = URL(string: url), let hostname = parsed.host else { return "" }
    let lowercasedHost = hostname.lowercased()
    return lowercasedHost.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
}

/// Extracts the owner and repo name from a GitHub or GitLab URL.
/// Returns nil if the URL is not a valid repo URL (e.g., it's a product page or not a GitHub/GitLab URL).
public func repoPath(_ url: String?) -> (owner: String, repo: String)? {
    guard let url = url else { return nil }
    guard let parsed = URL(string: url), let host = parsed.host else { return nil }

    // Check if it's a GitHub or GitLab URL
    let normalizedHost = host.lowercased()
    guard normalizedHost == "github.com" || normalizedHost == "gitlab.com" else { return nil }

    // Extract path segments
    let segments = parsed.path
        .split(separator: "/")
        .map(String.init)
        .filter { !$0.isEmpty }

    // Need at least 2 segments (owner/repo)
    guard segments.count >= 2 else { return nil }

    // Reject non-repo roots (applies to both GitHub and GitLab)
    if GITHUB_NON_REPO_ROOTS.contains(segments[0]) {
        return nil
    }

    return (owner: segments[0], repo: segments[1])
}

/// Formats a file size in bytes as a human-readable string.
/// Returns nil for nil, zero, negative, or non-finite values.
/// Bytes have 0 decimals, KB/MB/GB have 1 decimal.
public func formatFileSizeChip(_ bytes: Int?) -> String? {
    guard let bytes = bytes, bytes > 0 else { return nil }

    let sizes = ["B", "KB", "MB", "GB"]
    let bytesDouble = Double(bytes)
    let index = min(sizes.count - 1, Int(floor(log(bytesDouble) / log(1024))))

    let divisor = pow(1024.0, Double(index))
    let value = bytesDouble / divisor

    if index == 0 {
        // Bytes: no decimals
        return String(format: "%.0f B", value)
    } else {
        // KB and above: 1 decimal
        return String(format: "%.1f %@", value, sizes[index])
    }
}

/// Formats a duration in seconds as a human-readable string.
/// Returns nil for nil, zero, negative, or non-finite values.
/// Format: m:ss for durations < 1 hour, h:mm:ss for >= 1 hour
public func formatDurationChip(_ seconds: Double?) -> String? {
    guard let seconds = seconds, seconds.isFinite && seconds > 0 else { return nil }

    // `attributes.media.duration_s` is caller-writable JSON (any JWT holder can PATCH an item's
    // attributes blob), so a huge-but-finite value (e.g. 1e300) must fail soft here — `Int(_:)`'s
    // non-failable init traps for magnitudes outside Int's representable range, which previously
    // crash-looped the grid for that item. `Int(exactly:)` returns nil instead of trapping.
    guard let total = Int(exactly: round(seconds)) else { return nil }
    let minutes = total / 60
    let secs = total % 60

    if minutes >= 60 {
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%d:%02d:%02d", hours, mins, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Maps MIME types to file extension labels.
/// Returns nil for nil or empty MIME types.
/// Falls back to uppercased subtype (max 5 characters) for unknown types.
public func mimeExtensionLabel(_ mime: String?) -> String? {
    guard let mime = mime, !mime.isEmpty else { return nil }

    // Special case for audio/mp4
    if mime == "audio/mp4" {
        return "M4A"
    }

    // Extract subtype
    let parts = mime.split(separator: "/")
    guard parts.count >= 2 else { return nil }
    let subtype = String(parts[1])

    // Known mappings
    let known: [String: String] = [
        "jpeg": "JPG",
        "svg+xml": "SVG",
        "quicktime": "MOV",
        "x-m4a": "M4A",
        "mp4": "MP4",
        "mpeg": "MP3",
        "vnd.openxmlformats-officedocument.presentationml.presentation": "PPTX",
        "vnd.openxmlformats-officedocument.wordprocessingml.document": "DOCX",
        "vnd.openxmlformats-officedocument.spreadsheetml.sheet": "XLSX",
        "vnd.ms-powerpoint": "PPT",
        "vnd.ms-excel": "XLS",
        "msword": "DOC",
    ]

    // Check known mapping
    if let knownLabel = known[subtype] {
        return knownLabel
    }

    // Extract the "cleaned" subtype (after + and after last .)
    var cleaned = subtype
    if let plusIndex = cleaned.firstIndex(of: "+") {
        cleaned = String(cleaned[..<plusIndex])
    }

    let dotParts = cleaned.split(separator: ".")
    if let lastPart = dotParts.last {
        cleaned = String(lastPart)
    }

    // Check cleaned against known mappings
    if let knownLabel = known[cleaned] {
        return knownLabel
    }

    // Fallback: uppercase, max 5 chars
    return cleaned.uppercased().prefix(5).description
}

/// Determines if an image aspect ratio is portrait.
/// Portrait is defined as height > width * 1.05
public func isPortraitAspect(width: CGFloat, height: CGFloat) -> Bool {
    return height > width * 1.05
}
