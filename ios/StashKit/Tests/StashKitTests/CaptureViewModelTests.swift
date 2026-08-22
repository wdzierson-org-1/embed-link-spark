import XCTest
@testable import StashKit

/// Records every POST call (unlike `StubPoster`, which only keeps the last one) so tests can
/// assert exactly how many `add-*` calls a routing decision produced. Responds with `noteJSON`
/// for "add-note" and `itemJSON` for everything else, reusing Tasks 2-3's fixtures.
final class RecordingPoster: JSONPosting, @unchecked Sendable {
    var calls: [(path: String, body: [String: Any])] = []
    var shouldFail = false
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        calls.append((path, body))
        if shouldFail { throw CaptureError.badStatus(500) }
        return path == "add-note" ? noteJSON : itemJSON
    }
}

@MainActor
final class CaptureViewModelTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "capture-vm-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeViewModel(poster: RecordingPoster) -> CaptureViewModel {
        CaptureViewModel(
            userId: UUID(),
            api: CaptureAPI(poster: poster),
            outbox: Outbox(directory: dir),
            upload: { _, _, _ in },
            accessToken: { "jwt" }
        )
    }

    func testURLTextRoutesToAddURL() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "check this out https://example.com cool"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url"])
        XCTAssertEqual(poster.calls[0].body["url"] as? String, "https://example.com")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "check this out cool")
    }

    func testPlainTextRoutesToAddNote() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "buy milk"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-note"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "buy milk")
    }

    func testOneFileWithTextRoutesToAddFileWithContent() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "my screenshot"
        vm.attachments = [CaptureAttachment(data: Data([0x01, 0x02]), fileExtension: "png",
                                            mimeType: "image/png", kind: .photo)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-file"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "my screenshot")
    }

    // Task 5 (single-object model, Global Constraints): collections are retired — N attachments
    // always save as N items, never one item plus a separate note-only item. The typed note (if
    // any) rides `content` on the FIRST unit only; this replaces the old
    // `testThreeFilesWithTextRoutesToThreeAddFilePlusOneAddNote` expectation of a fourth,
    // separate `add-note` call.
    func testMultiFileWithTextPutsNoteOnFirstOnly() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "batch upload"
        vm.attachments = (0..<3).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 3, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-file", "add-file", "add-file"],
                       "no separate add-note call — the note rides the first add-file's content")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "batch upload")
        XCTAssertNil(poster.calls[1].body["content"])
        XCTAssertNil(poster.calls[2].body["content"])
    }

    // A URL detected in the typed text is always its own capture unit (add-url) and always comes
    // first when present, whether or not files are attached too — the note (URL substring
    // stripped out) rides its content; any attachments become individual add-file units with no
    // content of their own, same "note on first only" rule as the no-URL multi-file case above.
    func testURLPlusFilesNoteGoesToURLFirst() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "check this out https://example.com cool"
        vm.attachments = (0..<2).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 3, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url", "add-file", "add-file"])
        XCTAssertEqual(poster.calls[0].body["url"] as? String, "https://example.com")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "check this out cool")
        XCTAssertNil(poster.calls[1].body["content"])
        XCTAssertNil(poster.calls[2].body["content"])
    }

    // Rider (Task 6, from Task 5's review): T5 generalized "a URL is always its own unit and
    // always comes first" to every attachment count, including exactly one — previously,
    // `attachments.count == 1` short-circuited before any URL check ran at all, so a single
    // attached file + URL-bearing text used to merge the raw text (URL included) into the file's
    // `content` instead of splitting into two units. Only the 2-attachment case had a dedicated
    // test; this closes that gap for the 1-attachment case specifically. Pins existing behavior —
    // no production code changed for this test.
    func testSingleAttachmentWithURLTextMakesTwoUnitsNoteOnURL() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "check this https://example.com"
        vm.attachments = [CaptureAttachment(data: Data([0x01]), fileExtension: "png",
                                            mimeType: "image/png", kind: .photo)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url", "add-file"])
        XCTAssertEqual(poster.calls[0].body["url"] as? String, "https://example.com")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "check this")
        XCTAssertNil(poster.calls[1].body["content"], "the note already rode the URL unit")
    }

    // `pendingLocation` (Task 6 wires the UI that sets it) threads into EVERY unit's attributes,
    // alongside that unit's own per-attachment media facts (fileName/durationS captured at pick
    // time by the composer) — each file keeps its own media blob, not a shared one.
    func testAttributesThreadToEveryUnit() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.pendingLocation = CapturedLocation(label: "Testville", source: "device-geolocation")
        vm.attachments = [
            CaptureAttachment(data: Data([0x01]), fileExtension: "jpg", mimeType: "image/jpeg",
                              kind: .photo, fileName: "one.jpg", durationS: nil),
            CaptureAttachment(data: Data([0x02]), fileExtension: "mp4", mimeType: "video/mp4",
                              kind: .file, fileName: "two.mp4", durationS: 9.5),
        ]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 0))
        let fileCalls = poster.calls.filter { $0.path == "add-file" }
        XCTAssertEqual(fileCalls.count, 2)

        for call in fileCalls {
            let location = (call.body["attributes"] as? [String: Any])?["location"] as? [String: Any]
            XCTAssertEqual(location?["label"] as? String, "Testville")
        }

        let media0 = (fileCalls[0].body["attributes"] as? [String: Any])?["media"] as? [String: Any]
        XCTAssertEqual(media0?["file_name"] as? String, "one.jpg")
        XCTAssertNil(media0?["duration_s"])

        let media1 = (fileCalls[1].body["attributes"] as? [String: Any])?["media"] as? [String: Any]
        XCTAssertEqual(media1?["file_name"] as? String, "two.mp4")
        XCTAssertEqual(media1?["duration_s"] as? Double, 9.5)
    }

    func testFailureEnqueuesToOutboxAndReturnsQueued() async {
        let poster = RecordingPoster(); poster.shouldFail = true
        let vm = makeViewModel(poster: poster)
        vm.text = "offline note"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        let box = Outbox(directory: dir)
        let pending = await box.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["content"], "offline note")
    }

    // Fix round (review Important finding): oversized/upload-failed attachments were being
    // dropped print-only, with no way for the caller to know data was lost. Every drop must now
    // be counted and surfaced via `CaptureOutcome`.

    func testOversizedDocAloneIsRejectedWithNoNetworkCalls() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.attachments = [CaptureAttachment(data: Data(count: 21 * 1024 * 1024), fileExtension: "pdf",
                                            mimeType: "application/pdf", kind: .file)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .rejected(dropped: 1))
        XCTAssertTrue(poster.calls.isEmpty, "An oversized reject must never reach the network")
    }

    func testThreeAttachmentsWithOneOversizedSavesTwoAndDropsOne() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        let smallPhotos = (0..<2).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }
        let oversizedDoc = CaptureAttachment(data: Data(count: 21 * 1024 * 1024), fileExtension: "pdf",
                                             mimeType: "application/pdf", kind: .file)
        vm.attachments = smallPhotos + [oversizedDoc]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 1))
        XCTAssertEqual(poster.calls.filter { $0.path == "add-file" }.count, 2)
    }

    // MARK: - Voice notes (Task 6)
    //
    // `submitVoiceNote` is a separate, single-unit submit path, distinct from `submit()`'s
    // attachment routing: the recording's bytes are already durably on local disk (written by
    // `AVAudioRecorder` via `RecordingStore`, before this is ever called) — unlike a
    // `CaptureAttachment`'s in-memory `Data`, nothing is lost by queuing on ANY failure, so
    // (per the brief) there's no `UnqueueableFailure`-style distinction here: every failure mode
    // queues, never drops.

    func testSubmitVoiceNoteSuccessUploadsAndDeletesLocalFile() async throws {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-file"])
        XCTAssertEqual(poster.calls[0].body["mime_type"] as? String, "audio/mp4")
        XCTAssertEqual(poster.calls[0].body["file_size"] as? Int, 3)
        XCTAssertNil(poster.calls[0].body["content"], "voice notes never attach the composer's text as content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "the local recording must be deleted once its bytes are durably uploaded and registered")
    }

    func testSubmitVoiceNoteFailureRetainsFileAndEnqueuesOutboxEntryReferencingIt() async throws {
        let poster = RecordingPoster(); poster.shouldFail = true
        let vm = makeViewModel(poster: poster)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x0A, 0x0B]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "a failed submit must never delete the only copy of the recording")
        let box = Outbox(directory: dir)
        let pending = await box.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["local_file_path"], fileURL.path,
                       "the queued entry must point at exactly the file that's still on disk")
        XCTAssertEqual(pending[0].payload["mime_type"], "audio/mp4")
    }

    // Task 5: voice notes gain the same `attributes` threading as `submit()`'s file units —
    // `pendingLocation` plus a `media` blob built from the recorder-elapsed duration the sheet
    // passes in (there's no picked file here to read a `fileName`/`durationS` off of).
    func testVoiceNoteCarriesMediaAttributes() async throws {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.pendingLocation = CapturedLocation(label: "Testville", source: "device-geolocation")
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL, durationS: 12.5)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        let body = try XCTUnwrap(poster.calls.first?.body["attributes"] as? [String: Any])
        let location = try XCTUnwrap(body["location"] as? [String: Any])
        XCTAssertEqual(location["label"] as? String, "Testville")
        let media = try XCTUnwrap(body["media"] as? [String: Any])
        XCTAssertEqual(media["duration_s"] as? Double, 12.5)
    }

    // MARK: - Location resolution wait (Task 6)
    //
    // `awaitPendingLocation(timeout:)` bridges to the app's `LocationCapture` via a closure
    // injected at init — StashKit itself never imports CoreLocation, so it has no idea what
    // ".resolving" means, only "the app may still be working on a location and here's how long to
    // wait for it." NO hook at all (every OTHER test in this file, which never injects one, plus
    // `makeViewModel` below) is a true no-op that never touches `pendingLocation` — that's what
    // lets every attributes-threading test above set `pendingLocation` directly and trust it stays
    // put. Once a hook IS wired, its result unconditionally REPLACES `pendingLocation`, nil
    // included — a pin the user turned off (or that failed) must be able to clear a location a
    // previous toggle-on cycle left behind, not just skip setting a new one.

    func testNoHookIsANoOpAndNeverTouchesAnExistingValue() async {
        let vm = makeViewModel(poster: RecordingPoster())   // no awaitPendingLocation hook injected
        vm.pendingLocation = CapturedLocation(label: "AlreadySet", source: "device-geolocation")
        await vm.awaitPendingLocation(timeout: 2.5)
        XCTAssertEqual(vm.pendingLocation?.label, "AlreadySet",
                       "with no hook wired, awaitPendingLocation must never touch pendingLocation")
    }

    func testHookResultReplacesPendingLocationEvenOverwritingADirectlySetValue() async {
        let vm = CaptureViewModel(
            userId: UUID(), api: CaptureAPI(poster: RecordingPoster()), outbox: Outbox(directory: dir),
            upload: { _, _, _ in }, accessToken: { "jwt" },
            awaitPendingLocation: { _ in CapturedLocation(label: "Resolved", source: "device-geolocation") }
        )
        vm.pendingLocation = CapturedLocation(label: "Stale", source: "device-geolocation")
        await vm.awaitPendingLocation(timeout: 2.5)
        XCTAssertEqual(vm.pendingLocation?.label, "Resolved")
    }

    // The regression this contract exists to prevent: `LocationCapture.awaitResolution` returns
    // `nil` for an `.off`/`.failed` pin (Task 6, app target) — e.g. the user resolved a location on
    // an earlier save, then explicitly turned the pin back off before this one. A hook that's
    // wired but resolves `nil` must CLEAR `pendingLocation`, not leave the earlier save's location
    // attached to a batch the user never asked to tag.
    func testHookReturningNilClearsAPreviouslySetPendingLocation() async {
        let vm = CaptureViewModel(
            userId: UUID(), api: CaptureAPI(poster: RecordingPoster()), outbox: Outbox(directory: dir),
            upload: { _, _, _ in }, accessToken: { "jwt" },
            awaitPendingLocation: { _ in nil }   // simulates an .off/.failed pin
        )
        vm.pendingLocation = CapturedLocation(label: "FromAnEarlierSave", source: "device-geolocation")
        await vm.awaitPendingLocation(timeout: 2.5)
        XCTAssertNil(vm.pendingLocation, "a wired hook resolving nil must clear a stale pendingLocation")
    }

    func testSubmitCallsAwaitPendingLocationBeforeSnapshottingAttributes() async {
        let poster = RecordingPoster()
        let vm = CaptureViewModel(
            userId: UUID(), api: CaptureAPI(poster: poster), outbox: Outbox(directory: dir),
            upload: { _, _, _ in }, accessToken: { "jwt" },
            awaitPendingLocation: { _ in CapturedLocation(label: "JustResolved", source: "device-geolocation") }
        )
        vm.text = "note while pin resolves"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        let location = (poster.calls[0].body["attributes"] as? [String: Any])?["location"] as? [String: Any]
        XCTAssertEqual(location?["label"] as? String, "JustResolved")
    }

    // Pins the literal "≤2.5s" budget (Global Constraints) at the `submit()` call site itself,
    // rather than just proving the hook is called at all (the test above) — the hook only returns
    // a location when it's handed exactly the documented timeout, so a future edit that changes
    // (or drops) that argument fails this test even though the wiring still "works".
    func testSubmitAwaitsExactlyTheDocumentedTimeoutBudget() async {
        let poster = RecordingPoster()
        let vm = CaptureViewModel(
            userId: UUID(), api: CaptureAPI(poster: poster), outbox: Outbox(directory: dir),
            upload: { _, _, _ in }, accessToken: { "jwt" },
            awaitPendingLocation: { timeout in
                timeout == 2.5 ? CapturedLocation(label: "SawExpectedTimeout", source: "device-geolocation") : nil
            }
        )
        vm.text = "note"

        _ = await vm.submit()

        let location = (poster.calls[0].body["attributes"] as? [String: Any])?["location"] as? [String: Any]
        XCTAssertEqual(location?["label"] as? String, "SawExpectedTimeout",
                       "submit() must await with the documented ≤2.5s budget")
    }

    func testSubmitVoiceNoteCallsAwaitPendingLocationBeforeSnapshottingAttributes() async throws {
        let poster = RecordingPoster()
        let vm = CaptureViewModel(
            userId: UUID(), api: CaptureAPI(poster: poster), outbox: Outbox(directory: dir),
            upload: { _, _, _ in }, accessToken: { "jwt" },
            awaitPendingLocation: { _ in CapturedLocation(label: "VoiceResolved", source: "device-geolocation") }
        )
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        let location = (poster.calls[0].body["attributes"] as? [String: Any])?["location"] as? [String: Any]
        XCTAssertEqual(location?["label"] as? String, "VoiceResolved")
    }

    // End-to-end proof of the same regression `testHookReturningNilClearsAPreviouslySetPendingLocation`
    // covers at the unit level, through the actual `submit()` path a real save takes: a location
    // left over from an earlier batch (pin was on, then explicitly turned off before THIS save)
    // must not silently ride along — the sent body must carry no `attributes.location` at all
    // (media is absent too here, so `attributes` itself must be entirely absent — Task 3's
    // never-send-`{}` contract).
    func testSubmitDoesNotAttachAStaleLocationOnceTheHookResolvesNil() async {
        let poster = RecordingPoster()
        let vm = CaptureViewModel(
            userId: UUID(), api: CaptureAPI(poster: poster), outbox: Outbox(directory: dir),
            upload: { _, _, _ in }, accessToken: { "jwt" },
            awaitPendingLocation: { _ in nil }   // simulates the pin now being .off
        )
        vm.pendingLocation = CapturedLocation(label: "FromAnEarlierSave", source: "device-geolocation")
        vm.text = "a fresh note with the pin off"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertNil(poster.calls[0].body["attributes"],
                     "the stale location must be cleared, not silently attached to this batch")
    }
}
