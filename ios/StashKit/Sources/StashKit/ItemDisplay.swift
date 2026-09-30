import Foundation

/// Display-only presentation rules for library cards (plan 15, Task 3) and the detail sheet's
/// title field (plan 16) and empty Transcript tab. Nothing here is ever written back to the row —
/// these only decide what the UI SHOWS (and, for the title field, what counts as an edit).
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
    /// is only a storage object name (`isObjectName`), which carries no meaning to a person
    /// scanning their library. The detail sheet shows such a title as an empty field with this same
    /// label as its placeholder (`editableRow`/`titlePlaceholder`).
    public static func displayTitle(for item: Item) -> String {
        let trimmed = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return "Untitled" }
        if isObjectName(trimmed) { return typeLabel(for: item) }
        return trimmed
    }

    /// Whether a stored title is only a storage object name — a UUID (`72322570-….m4a`, iOS share/
    /// Voice Memos) or a millisecond timestamp (`1727040000000.jpg`, older uploads). Ports
    /// `isUuidObjectName`/`isStorageTimestampName` from `src/utils/titlePolicy.ts`. The server's own
    /// `isPlaceholderTitle` is wider (any file-name-shaped title) and is what lets its jobs replace
    /// such a title with an AI one; this narrower rule is only about what reads as meaningless.
    public static func isObjectName(_ title: String?) -> Bool {
        guard let title else { return false }
        return isUuidObjectName(title) || isStorageTimestampName(title)
    }

    // MARK: - Detail title field (plan 16)
    //
    // Will's device screenshot: a voice note's detail sheet was titled with its raw object name
    // (`f200ad94-32d7-4b39-bcfc-313b…`) — the card's fallback didn't reach the sheet. The sheet's
    // title field now starts EMPTY for such a title, with the card's type label as its placeholder.
    // The sheet seeds its fields from `editableRow(server)` and diffs every save against
    // `editableRow(snapshot)`, so the empty field is not an edit: opening and closing the sheet
    // never writes a title (an empty one would turn the card's "Voice note" into "Untitled"; the
    // object name stays, for the server's jobs to replace with an AI title), typing one saves it,
    // and an AI title arriving while the sheet is open replaces the placeholder
    // (`mergePreservingDetail` sees no unsaved title).

    /// The detail title field's placeholder: the card's type label when the stored title is an
    /// object name — the empty field reads the way the card does — and "Untitled" otherwise.
    public static func titlePlaceholder(for item: Item) -> String {
        isObjectName(item.title) ? typeLabel(for: item) : "Untitled"
    }

    /// `server` as the detail sheet's fields show it: an object-name title reads as empty; every
    /// other title (a real file name included — it's the user's words) and every other column is
    /// untouched. The sheet's seed and its save baseline.
    public static func editableRow(_ server: Item) -> Item {
        guard isObjectName(server.title) else { return server }
        var row = server
        row.title = ""
        return row
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

    /// Why an audio/video item has no transcript when the server's transcription job
    /// (`attributes.media.transcript`, `TranscriptJobState`) ended `failed`: `no_speech` gets its
    /// own sentence, any other failure a plain one. `nil` while the job is pending or processing,
    /// once it's done, and on rows with no job status (legacy rows).
    public static func transcriptFailureText(for item: Item) -> String? {
        guard let job = TranscriptJobState(attributes: item.attributes), job.status == .failed else { return nil }
        return job.error == "no_speech" ? "No speech was detected in this recording."
                                        : "Couldn't transcribe this recording."
    }

    /// What the detail sheet's Transcript tab says while it has no transcript text. A failed job
    /// says why (plan 15 wrap — it used to read "in progress" forever); anything else is on its way.
    public static func emptyTranscriptText(for item: Item) -> String {
        transcriptFailureText(for: item) ?? "Transcription in progress…"
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
