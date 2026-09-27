import Foundation

/// Display-only presentation rules for library cards (plan 15, Task 3). Nothing here is ever
/// written back to the row — these only decide what a card SHOWS.
public enum ItemDisplay {
    /// Voice note vs. long recording — mirrors web `audioSubtype` (`src/components/cards/
    /// CardBits.tsx`): enrichment's `attributes.media.kind` wins when it is one of the two known
    /// values; without it, under ten minutes reads as a voice note.
    public enum AudioKind: String, Sendable {
        case voiceNote = "voice_note"
        case recording
    }

    /// Recording length at/over which an audio item without `media.kind` reads as a recording.
    public static let recordingThresholdSeconds: Double = 600

    public static func audioKind(for item: Item) -> AudioKind {
        if case .string(let kind)? = item.attributes.media?.extra["kind"],
           let known = AudioKind(rawValue: kind) {
            return known
        }
        let duration = item.attributes.media?.durationS ?? 0
        return duration >= recordingThresholdSeconds ? .recording : .voiceNote
    }

    /// Screenshot vs. plain photo — mirrors web `isScreenshotItem`: enrichment's
    /// `media.kind == "screenshot"`, or the vision-written title's own words.
    public static func isScreenshot(_ item: Item) -> Bool {
        if case .string("screenshot")? = item.attributes.media?.extra["kind"] { return true }
        return item.title?.hasPrefix("Screenshot of") ?? false
    }

    /// The card's title. The trimmed title when it means something; "Untitled" when empty; and a
    /// type label ("Voice note", "Recording", "Photo", "Screenshot", "Video", "File") when the title
    /// is only a storage object name — a UUID (`72322570-….m4a`, iOS share/Voice Memos) or a
    /// millisecond timestamp (`1727040000000.jpg`, older uploads) — which carries no meaning to a
    /// person scanning their library. Ports `isUuidObjectName`/`isStorageTimestampName` from
    /// `src/utils/titlePolicy.ts`; the detail sheet keeps showing (and editing) the raw title.
    public static func displayTitle(for item: Item) -> String {
        let trimmed = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return "Untitled" }
        if isUuidObjectName(trimmed) || isStorageTimestampName(trimmed) { return typeLabel(for: item) }
        return trimmed
    }

    /// Human label for an item's type, used when its title is only an object name.
    public static func typeLabel(for item: Item) -> String {
        switch item.type {
        case .audio: return audioKind(for: item) == .recording ? "Recording" : "Voice note"
        case .image: return isScreenshot(item) ? "Screenshot" : "Photo"
        case .video: return "Video"
        default: return "File"
        }
    }

    /// Port of web `isStorageTimestampName`: `/^\d{10,17}\.[a-z0-9]+$/i` on the trimmed name.
    public static func isStorageTimestampName(_ name: String) -> Bool {
        guard let (stem, ext) = splitSingleExtension(name) else { return false }
        return (10...17).contains(stem.count) && stem.allSatisfy { $0.isASCII && $0.isNumber }
            && isAlphanumericExtension(ext)
    }

    /// Port of web `isUuidObjectName`:
    /// `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]+$/i` on the trimmed name.
    public static func isUuidObjectName(_ name: String) -> Bool {
        guard let (stem, ext) = splitSingleExtension(name) else { return false }
        let groups = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isHexDigit } } && isAlphanumericExtension(ext)
    }

    /// `stem.ext` with exactly one dot and both halves non-empty (every character class in the two
    /// web regexes excludes `.`, so a second dot can never match either of them).
    private static func splitSingleExtension(_ name: String) -> (Substring, Substring)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    private static func isAlphanumericExtension(_ ext: Substring) -> Bool {
        ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
