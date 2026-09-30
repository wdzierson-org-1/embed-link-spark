import XCTest
@testable import StashKit

final class ItemDisplayTests: XCTestCase {
    private func item(_ type: ItemType, title: String?, media: MediaAttributes? = nil) -> Item {
        Item(id: UUID(), type: type, title: title, content: nil, url: nil, filePath: nil,
             description: nil, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
             isPublic: false, createdAt: Date(), attributes: ItemAttributes(media: media))
    }

    // MARK: - Web titlePolicy.ts ports

    func testUuidObjectNameMatchesWebRegex() {
        XCTAssertTrue(ItemDisplay.isUuidObjectName("72322570-a4bc-4515-935c-ff384090f068.m4a"))
        XCTAssertTrue(ItemDisplay.isUuidObjectName("72322570-A4BC-4515-935C-FF384090F068.JPG"))
        XCTAssertTrue(ItemDisplay.isUuidObjectName("  ce47f779-d541-461e-b534-f6da3af7e452.m4a \n"))
        XCTAssertFalse(ItemDisplay.isUuidObjectName("72322570-a4bc-4515-935c-ff384090f068"))        // no extension
        XCTAssertFalse(ItemDisplay.isUuidObjectName("72322570-a4bc-4515-935c-ff384090f068.tar.gz")) // two dots
        XCTAssertFalse(ItemDisplay.isUuidObjectName("72322570-a4bc-4515-935c-ff384090f06.m4a"))     // 11-char tail
        XCTAssertFalse(ItemDisplay.isUuidObjectName("7232257g-a4bc-4515-935c-ff384090f068.m4a"))    // non-hex
        XCTAssertFalse(ItemDisplay.isUuidObjectName("Meeting notes.m4a"))
    }

    func testStorageTimestampNameMatchesWebRegex() {
        XCTAssertTrue(ItemDisplay.isStorageTimestampName("1758945584318.jpg"))
        XCTAssertTrue(ItemDisplay.isStorageTimestampName("1758945584.PNG"))             // 10 digits
        XCTAssertTrue(ItemDisplay.isStorageTimestampName("12345678901234567.m4a"))       // 17 digits
        XCTAssertFalse(ItemDisplay.isStorageTimestampName("123456789.jpg"))              // 9 digits
        XCTAssertFalse(ItemDisplay.isStorageTimestampName("123456789012345678.jpg"))     // 18 digits
        XCTAssertFalse(ItemDisplay.isStorageTimestampName("1758945584318"))              // no extension
        XCTAssertFalse(ItemDisplay.isStorageTimestampName("1758945584318.j-g"))          // non-alnum ext
        XCTAssertFalse(ItemDisplay.isStorageTimestampName("Report 2026.pdf"))
    }

    // MARK: - displayTitle

    func testDisplayTitleKeepsMeaningfulTitles() {
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.link, title: "  Omarchy  ")), "Omarchy")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.document, title: "Q3 plan.pdf")), "Q3 plan.pdf")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.text, title: nil)), "Untitled")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.text, title: "   ")), "Untitled")
    }

    func testDisplayTitleReplacesObjectNamesWithTypeLabels() {
        let uuidName = "ce47f779-d541-461e-b534-f6da3af7e452.m4a"
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.audio, title: uuidName)), "Voice note")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.image, title: "1758945584318.jpg")), "Photo")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.video, title: "1758945584318.mov")), "Video")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.document, title: uuidName)), "File")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.link, title: uuidName)), "File")
    }

    func testDisplayTitleFollowsAudioAndScreenshotSubtypes() {
        let uuidName = "ce47f779-d541-461e-b534-f6da3af7e452.m4a"
        let recording = item(.audio, title: uuidName, media: MediaAttributes(extra: ["kind": .string("recording")]))
        XCTAssertEqual(ItemDisplay.displayTitle(for: recording), "Recording")
        let longNoKind = item(.audio, title: uuidName, media: MediaAttributes(durationS: 900))
        XCTAssertEqual(ItemDisplay.displayTitle(for: longNoKind), "Recording")
        let screenshot = item(.image, title: "1758945584318.png", media: MediaAttributes(extra: ["kind": .string("screenshot")]))
        XCTAssertEqual(ItemDisplay.displayTitle(for: screenshot), "Screenshot")
    }

    /// Plan 16 (M-6, coordinator's decision): an EMPTY title on an audio, image, video or file item
    /// reads as the item's type label, exactly as an object name does — clearing a voice note's
    /// title in the detail sheet writes "" and the card still reads "Voice note". Every other type
    /// keeps "Untitled".
    func testAnEmptyMediaOrFileTitleReadsAsItsTypeLabel() {
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.audio, title: "")), "Voice note")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.audio, title: nil)), "Voice note")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.audio, title: "  \n")), "Voice note")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.audio, title: "", media: MediaAttributes(durationS: 900))),
                       "Recording")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.image, title: "")), "Photo")
        let screenshot = item(.image, title: "", media: MediaAttributes(extra: ["kind": .string("screenshot")]))
        XCTAssertEqual(ItemDisplay.displayTitle(for: screenshot), "Screenshot")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.video, title: nil)), "Video")
        XCTAssertEqual(ItemDisplay.displayTitle(for: item(.document, title: "")), "File")
        for type in [ItemType.text, .link, .collection, .unknown] {
            XCTAssertEqual(ItemDisplay.displayTitle(for: item(type, title: "")), "Untitled", "\(type)")
            XCTAssertEqual(ItemDisplay.displayTitle(for: item(type, title: nil)), "Untitled", "\(type)")
        }
    }

    // MARK: - Detail title field (plan 16)

    /// Will's device screenshot: a voice note's detail sheet was titled with its raw storage object
    /// name (`f200ad94-32d7-4b39-bcfc-313b…`). The title field now holds an object name as EMPTY;
    /// every other stored title — a real file name included — is the user's and is shown as stored.
    func testEditableRowEmptiesOnlyObjectNameTitles() {
        func shown(_ title: String?) -> String? { ItemDisplay.editableRow(item(.audio, title: title)).title }
        XCTAssertEqual(shown("f200ad94-32d7-4b39-bcfc-313b5e0a9c41.m4a"), "")
        XCTAssertEqual(shown(" 1758945584318.jpg\n"), "")
        XCTAssertEqual(shown("Standup notes"), "Standup notes")
        XCTAssertEqual(shown("Q3 plan.pdf"), "Q3 plan.pdf")
        XCTAssertNil(shown(nil))
        XCTAssertEqual(shown(""), "")
    }

    /// The empty field's placeholder is what the card shows once the field is left empty: an empty
    /// title on an audio, image, video or file item reads as its type label (M-6, subtypes
    /// included), so the placeholder never flips to "Untitled" when the user clears a title they
    /// typed. Other types keep "Untitled"; an object name keeps the card's label on any type.
    func testTitlePlaceholderIsWhatTheCardShowsForAnEmptyTitle() {
        let uuidName = "ce47f779-d541-461e-b534-f6da3af7e452.m4a"
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.audio, title: uuidName)), "Voice note")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.image, title: "1758945584318.jpg")), "Photo")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.video, title: uuidName)), "Video")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.document, title: uuidName)), "File")
        let recording = item(.audio, title: uuidName, media: MediaAttributes(durationS: 900))
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: recording), "Recording")
        let screenshot = item(.image, title: "1758945584318.png", media: MediaAttributes(extra: ["kind": .string("screenshot")]))
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: screenshot), "Screenshot")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.audio, title: nil)), "Voice note")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.audio, title: "Standup")), "Voice note",
                       "Cleared, a voice note's typed title reads as \"Voice note\"")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.image, title: "Screenshot of a receipt")), "Photo",
                       "Cleared, the vision title's \"Screenshot of\" is gone: the card will read \"Photo\"")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.link, title: "Omarchy")), "Untitled")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.text, title: nil)), "Untitled")
        XCTAssertEqual(ItemDisplay.titlePlaceholder(for: item(.link, title: uuidName)), "File",
                       "An object name reads as the card's label on any type")
    }

    /// Only the title changes, and only for an object name; a real title — a file name included —
    /// is the user's and is shown (and diffed) as stored.
    func testEditableRowChangesOnlyAnObjectNameTitle() {
        let server = item(.audio, title: "f200ad94-32d7-4b39-bcfc-313b5e0a9c41.m4a")
        var expected = server
        expected.title = ""
        XCTAssertEqual(ItemDisplay.editableRow(server), expected)
        let named = item(.audio, title: "Standup")
        XCTAssertEqual(ItemDisplay.editableRow(named), named)
    }

    // MARK: - Subtypes (web CardBits.tsx parity)

    func testAudioKindPrefersMediaKindOverDuration() {
        let shortRecording = item(.audio, title: nil,
                                  media: MediaAttributes(durationS: 30, extra: ["kind": .string("recording")]))
        XCTAssertEqual(ItemDisplay.audioKind(for: shortRecording), .recording)
        let longVoiceNote = item(.audio, title: nil,
                                 media: MediaAttributes(durationS: 1200, extra: ["kind": .string("voice_note")]))
        XCTAssertEqual(ItemDisplay.audioKind(for: longVoiceNote), .voiceNote)
        // Unknown/absent kind → duration heuristic (≥ 10 minutes = recording).
        let unknownKind = item(.audio, title: nil, media: MediaAttributes(durationS: 600, extra: ["kind": .string("podcast")]))
        XCTAssertEqual(ItemDisplay.audioKind(for: unknownKind), .recording)
        XCTAssertEqual(ItemDisplay.audioKind(for: item(.audio, title: nil, media: MediaAttributes(durationS: 599))), .voiceNote)
        XCTAssertEqual(ItemDisplay.audioKind(for: item(.audio, title: nil)), .voiceNote)
    }

    func testScreenshotReadsMediaKindOrVisionTitle() {
        XCTAssertTrue(ItemDisplay.isScreenshot(item(.image, title: "Anything",
                                                     media: MediaAttributes(extra: ["kind": .string("screenshot")]))))
        XCTAssertTrue(ItemDisplay.isScreenshot(item(.image, title: "Screenshot of a settings page")))
        XCTAssertFalse(ItemDisplay.isScreenshot(item(.image, title: "Image of a cat")))
    }

    // MARK: - Empty Transcript tab (plan 15 wrap)

    /// A job that ended `failed` must not read as "in progress" forever: `no_speech` gets its own
    /// sentence, every other failure (or none named) the plain one; pending/processing/done and rows
    /// with no job status keep the in-progress copy.
    func testEmptyTranscriptTextFollowsTheJobStatus() {
        func audio(_ status: String?, error: String? = nil) -> Item {
            guard let status else { return item(.audio, title: "Memo", media: MediaAttributes(durationS: 12)) }
            var transcript: [String: JSONValue] = ["status": .string(status),
                                                   "updated_at": .string("2026-09-29T18:40:59.335Z")]
            if let error { transcript["error"] = .string(error) }
            return item(.audio, title: "Memo", media: MediaAttributes(extra: ["transcript": .object(transcript)]))
        }
        XCTAssertEqual(ItemDisplay.emptyTranscriptText(for: audio("failed", error: "no_speech")),
                       "No speech was detected in this recording.")
        for code in ["transcription_failed", "download_failed", "no_audio_track", "unsupported_container"] {
            XCTAssertEqual(ItemDisplay.emptyTranscriptText(for: audio("failed", error: code)),
                           "Couldn't transcribe this recording.", code)
        }
        XCTAssertEqual(ItemDisplay.emptyTranscriptText(for: audio("failed")), "Couldn't transcribe this recording.")
        for status in ["pending", "processing", "done", "thinking"] {
            XCTAssertNil(ItemDisplay.transcriptFailureText(for: audio(status)), status)
            XCTAssertEqual(ItemDisplay.emptyTranscriptText(for: audio(status)), "Transcription in progress…", status)
        }
        XCTAssertNil(ItemDisplay.transcriptFailureText(for: audio(nil)), "legacy row: no job status")
        XCTAssertEqual(ItemDisplay.emptyTranscriptText(for: audio(nil)), "Transcription in progress…")
        XCTAssertEqual(ItemDisplay.transcriptFailureText(for: audio("failed", error: "no_speech")),
                       "No speech was detected in this recording.")
    }
}
