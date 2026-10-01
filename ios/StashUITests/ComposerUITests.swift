import XCTest

/// Plan 15 Task 6D (Add-tab composer tune-up): voice memos keep recording through a screen lock or
/// an app switch and say when an interruption cut them short (H3); picks load off the main thread
/// behind a pending chip, and a pick that can't attach says so (M7).
///
/// Nothing here saves a capture — every test discards what it made (the recording is cancelled,
/// attachments are removed), so no rows are created. The recorder tests pass
/// `--uitest-voice-gate-open` because the lapsed `will+uitest` account's subscription gate would
/// otherwise disable the mic button (`testVoiceNoteSmoke` only gets in by racing that gate).
/// Microphone access must be pre-granted on the simulator
/// (`xcrun simctl privacy <udid> grant microphone it.gostash.stash`), as for `testVoiceNoteSmoke`.
///
/// A standalone file (`StashUITests.swift` belongs to another task), with its own sign-in helper —
/// the same recipe as `AskUITests.signIn`.
final class ComposerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Plan 16: the simulator-global Bold Text setting may have been left on by an interrupted
        // accessibility run (see `A11yScreenshotSupport`'s GLOBAL STATE note).
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    // MARK: - Voice memos (H3)

    /// The screen is kept awake exactly while recording, and an interruption — a synthetic
    /// `AVAudioSession.interruptionNotification` (`--uitest-voice-interrupt-after`), what a phone
    /// call or Siri delivers — finalizes the take and says where it was cut, with Save and
    /// Re-record still offered. Re-record starts a clean take.
    @MainActor
    func testRecordingKeepsTheScreenAwakeAndReportsAnInterruption() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-voice-gate-open", "--uitest-voice-probe",
                                               "--uitest-voice-interrupt-after=3"])
        openVoiceRecorder(app)

        let probe = element(app, "debug.idleTimer")
        XCTAssertTrue(waitForLabel(probe, "enabled", timeout: 5),
                      "Before recording the screen may auto-lock as usual (probe: \(probe.label))")

        element(app, "capture.voice.record").tap()
        XCTAssertTrue(element(app, "capture.voice.stop").waitForExistence(timeout: 5), "Recording didn't start")
        XCTAssertTrue(waitForLabel(probe, "disabled", timeout: 3),
                      "While recording the screen must stay awake (probe: \(probe.label))")

        let notice = element(app, "capture.voice.interrupted")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "An interruption should land on the preview with a notice")
        XCTAssertTrue(notice.label.hasPrefix("Recording was interrupted at "), "notice: \(notice.label)")
        let cutAt = try XCTUnwrap(clockSeconds(notice.label), "notice: \(notice.label)")
        XCTAssertTrue((2...5).contains(cutAt), "Interrupted ~3 s in, but the notice says: \(notice.label)")
        XCTAssertTrue(element(app, "capture.voice.save").exists, "Save is still offered after an interruption")
        XCTAssertTrue(element(app, "capture.voice.rerecord").exists, "Re-record is still offered after an interruption")
        XCTAssertTrue(waitForLabel(probe, "enabled", timeout: 3),
                      "An interruption must hand auto-lock back (probe: \(probe.label))")

        element(app, "capture.voice.rerecord").tap()
        XCTAssertTrue(element(app, "capture.voice.stop").waitForExistence(timeout: 5), "Re-record didn't start a new take")
        XCTAssertFalse(notice.exists, "A new take must not carry the previous take's notice")
        XCTAssertTrue(waitForLabel(probe, "disabled", timeout: 3), "The new take keeps the screen awake again")

        // Discard (Cancel deletes the file) — nothing is saved.
        element(app, "capture.voice.cancel").tap()
        XCTAssertTrue(element(app, "capture.voice.record").waitForNonExistence(timeout: 5), "Cancel should close the recorder")
    }

    /// `UIBackgroundModes: audio`: a recording keeps running while the app is in the background
    /// (Home here; a screen lock suspends the app the same way) and comes back still recording,
    /// with the time spent away on its clock. Stopping it afterwards is a normal stop — no notice.
    @MainActor
    func testRecordingKeepsRunningInTheBackground() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-voice-gate-open", "--uitest-voice-probe"])
        openVoiceRecorder(app)

        element(app, "capture.voice.record").tap()
        let stop = element(app, "capture.voice.stop")
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "Recording didn't start")

        XCUIDevice.shared.press(.home)
        sleep(12)
        app.activate()

        XCTAssertTrue(stop.waitForExistence(timeout: 10), "Expected the recording to still be running after 12 s away")
        XCTAssertFalse(element(app, "capture.voice.interrupted").exists, "Backgrounding must not interrupt the recording")
        let timer = element(app, "capture.voice.timer")
        let elapsed = try XCTUnwrap(clockSeconds(timer.label), "timer: \(timer.label)")
        XCTAssertGreaterThanOrEqual(elapsed, 12, "The recording should have run while the app was away (timer \(timer.label))")
        XCTAssertEqual(element(app, "debug.idleTimer").label, "disabled", "Still recording, so the screen stays awake")

        stop.tap()
        XCTAssertTrue(element(app, "capture.voice.save").waitForExistence(timeout: 5), "Stop should land on the preview")
        XCTAssertFalse(element(app, "capture.voice.interrupted").exists, "A user Stop is not an interruption")
        XCTAssertTrue(waitForLabel(element(app, "debug.idleTimer"), "enabled", timeout: 3), "Stop hands auto-lock back")

        element(app, "capture.voice.cancel").tap()   // discard — nothing is saved
        XCTAssertTrue(element(app, "capture.voice.record").waitForNonExistence(timeout: 5), "Cancel should close the recorder")
    }

    // MARK: - Attachments (M7)

    /// A picked photo shows a pending chip at once and loads off the main thread, so the editor
    /// takes typing WHILE the photo is still loading. `--uitest-slow-attachment-load` BLOCKS the
    /// loading thread for 6 s: if loading ever moved back onto the main thread, the composer would
    /// freeze for those 6 s, and the typing below would only land after the chip had resolved.
    @MainActor
    func testPickedPhotoLoadsBehindAPendingChipWhileTypingContinues() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-slow-attachment-load=6000"])

        pickFirstPhoto(app)
        let pending = element(app, "capture.attachment.pending")
        XCTAssertTrue(pending.waitForExistence(timeout: 10), "Expected a pending chip while the photo loads")

        let editor = element(app, "capture.editor")
        editor.tap()
        let typed = "typing while a photo loads"
        editor.typeText(typed)
        XCTAssertEqual(app.textViews["capture.editor"].value as? String, typed)
        XCTAssertTrue(pending.exists, "The photo must still be loading — typing was handled during the load, not after it")
        let gated = element(app, "capture.subscriptionGate").exists
        if !gated {
            XCTAssertFalse(app.buttons["capture.save"].isEnabled, "Save waits for the pending photo")
        }

        let thumbnail = element(app, "capture.attachment.thumbnail")
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 20), "The pending chip should turn into the photo's thumbnail")
        XCTAssertFalse(pending.exists, "No pending chip once the photo is attached")
        // The chip is labelled with the photo's original filename (`media.file_name`) — carried by
        // the single file transfer; the bytes-only fallback transfer has no name ("Photo").
        XCTAssertNotEqual(thumbnail.label, "Photo", "Expected the photo's original filename on its chip")
        XCTAssertTrue(thumbnail.label.contains("."), "Expected a filename with an extension, got '\(thumbnail.label)'")
        if !gated {
            XCTAssertTrue(app.buttons["capture.save"].isEnabled, "Save is live once the photo is attached")
        }

        element(app, "capture.attachment.remove").tap()   // tidy up — nothing is saved
        XCTAssertTrue(thumbnail.waitForNonExistence(timeout: 5), "Removing the attachment should drop its chip")
    }

    /// Files: an allowed pick attaches (named chip) and a pick over its kind's limit is refused
    /// from its size alone with a toast — never dropped silently. Driven through the composer's
    /// real file-import path: `--uitest-import-file` hands it sparse files exactly as the Files
    /// picker hands over its picks (minus the out-of-process picker UI).
    @MainActor
    func testImportedFilesAttachOrSayWhyNot() throws {
        let app = XCUIApplication()
        try signIn(app)
        // The imports are handed over on the composer's first appearance, and the refusal toast
        // lasts 3 s — so they ride a signed-in RELAUNCH (the Keychain session restores), clear of
        // the sign-in's iOS 26 "Save Password?" handling, which can take up to 12 s and used to
        // outlast the toast (plan 16). The allowed file's load is held 4 s, so the toast comes
        // after the launch has settled.
        app.terminate()
        app.launchArguments = ["--uitest-slow-attachment-load=4000",
                               "--uitest-import-file=clip.mov:30", "--uitest-import-file=lecture.mov:101"]
        app.launch()
        XCTAssertTrue(element(app, "capture.editor").waitForExistence(timeout: 20), "Expected the Add tab after relaunching")

        let toast = element(app, "capture.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "The 101 MB movie must be refused with a toast")
        XCTAssertEqual(toast.label, "Couldn't add “lecture.mov” — it's over the 100 MB limit")

        let chip = element(app, "capture.attachment.file")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "The 30 MB movie should attach")
        XCTAssertTrue(chip.label.contains("clip.mov"), "chip: \(chip.label)")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "capture.attachment.remove").count, 1,
                       "Only the allowed file attaches")
        XCTAssertFalse(element(app, "capture.attachment.pending").exists, "No pick left pending")

        element(app, "capture.attachment.remove").tap()   // tidy up — nothing is saved
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5), "Removing the attachment should drop its chip")
    }

    // MARK: - Helpers

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Seconds in the text's trailing clock — "00:13" → 13, "…interrupted at 1:05" → 65.
    private func clockSeconds(_ text: String) -> Int? {
        guard let clock = text.split(separator: " ").last else { return nil }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private func openVoiceRecorder(_ app: XCUIApplication) {
        let voice = element(app, "capture.voice")
        XCTAssertTrue(voice.waitForExistence(timeout: 15), "Expected the voice-note mic button on the Add tab")
        voice.tap()
        XCTAssertTrue(element(app, "capture.voice.record").waitForExistence(timeout: 10),
                      "The voice recorder sheet did not open")
    }

    /// The real PhotosPicker (out of process), against the simulator's photo library — the same
    /// recipe as `testComposerKeyboardAccessory`.
    private func pickFirstPhoto(_ app: XCUIApplication) {
        let picker = app.buttons["capture.photosPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "Photos button not found")
        picker.tap()
        let firstPhoto = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
        let photoCell = firstPhoto.waitForExistence(timeout: 10) ? firstPhoto : app.scrollViews.firstMatch.images.firstMatch
        XCTAssertTrue(photoCell.waitForExistence(timeout: 10), "Expected the system photo picker to show at least one photo")
        // A coordinate tap: on iOS 26.5 the out-of-process picker reported its first photo "not
        // hittable" to XCUITest (plan 16), and `tap()` refuses to tap such an element.
        photoCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let addButton = app.navigationBars.buttons["Add"]
        if addButton.waitForExistence(timeout: 5) { addButton.tap() }
    }

    /// `--uitest-reset-auth` forces the real sign-in screen (the Keychain session survives
    /// reinstalls on the Simulator) and marks the one-time onboarding panel as seen. Plan 16:
    /// declines iOS 26's "Save Password?" sheet with the canonical `A11yScreens` recipe (it would
    /// swallow the test's next tap).
    @MainActor
    private func signIn(_ app: XCUIApplication, extraLaunchArguments: [String] = []) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["STASH_TEST_EMAIL"], let password = environment["STASH_TEST_PASSWORD"],
              !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        app.launchArguments = ["--uitest-reset-auth"] + extraLaunchArguments
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        A11yScreens.tapUntilFocused(emailField)
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        A11yScreens.tapUntilFocused(passwordField)
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(element(app, "capture.editor").waitForExistence(timeout: 20), "Expected the Add tab after sign-in")
        A11yScreens.dismissSavePasswordPrompt(app)
    }
}
