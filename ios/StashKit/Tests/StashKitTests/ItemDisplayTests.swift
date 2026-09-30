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
