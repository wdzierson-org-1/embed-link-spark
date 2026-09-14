import XCTest

/// Plan 14 Task 4b: drives the REVIEW account (`STASH_REVIEW_EMAIL`/`STASH_REVIEW_PASSWORD` —
/// never the fixture/test accounts `StashUITests.swift` owns) to seed realistic content and
/// capture the six 6.9" App Store screenshot frames. Its own file per Task 4's file-ownership
/// split: `StashUITests.swift` belongs to another agent this round.
///
/// Skipped entirely unless `STORE_SCREENSHOTS=1` is set in the test-runner environment — this
/// suite is deliberately NOT part of the standing UI suite run (it seeds permanent content on a
/// production account and takes several minutes; running it by accident would silently mutate
/// the review account every CI pass). Both tests below assume the app is already installed on
/// the target simulator (iPhone 17 Pro Max, `3F61D023-8A5F-4EB5-A0A3-83213A756EAA` per the plan)
/// and the status bar has already been overridden (`simctl status_bar override`, external to this
/// file — repeated here so the screenshots keep the fixed 9:41/100%/full-bars look regardless of
/// wall-clock time).
///
/// Screenshot mechanism: `SCREENSHOT_CHECKPOINT: <name>` markers on stderr, each held for several
/// seconds — same convention `StashUITests.swift` already uses throughout (`testCaptureSmoke`,
/// `testDetailSheets`, `testAskSmoke`, etc.). An external orchestrator (a plain shell loop tailing
/// this run's log, documented in `.superpowers/sdd/plan-14/task-4b-report.md`) runs `xcrun simctl
/// io <udid> screenshot docs/app-store/screenshots/1.0/0N-<slug>.png` the instant each marker
/// appears. This is deliberately NOT an in-process `XCUIScreen.main.screenshot()` write to a repo
/// path: the UI-test bundle runs inside the simulator's own process sandbox, which has no
/// reliable, documented way to write to an arbitrary host path outside its container, whereas
/// `simctl io screenshot` captures the device's exact native pixel buffer (1320×2868 for this
/// device — the exact ASC 6.9" requirement, no scaling needed) directly from the host `simctl`
/// process.
final class StoreScreenshotsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STORE_SCREENSHOTS"] == "1",
                          "Store-screenshot capture only runs when STORE_SCREENSHOTS=1 is set in the test runner environment")
    }

    // MARK: - Review credentials + REST helpers

    private func reviewCredentials() throws -> (email: String, password: String) {
        guard
            let email = ProcessInfo.processInfo.environment["STASH_REVIEW_EMAIL"],
            let password = ProcessInfo.processInfo.environment["STASH_REVIEW_PASSWORD"],
            !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_REVIEW_EMAIL / STASH_REVIEW_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing review credentials")
        }
        return (email, password)
    }

    /// Same production Supabase project URL + public anon key `StashConfig.swift` (StashKit)
    /// ships — not a secret (it ships in the committed web client too). Duplicated here rather
    /// than imported for the same reason `StashUITests.swift` duplicates its own copy: this
    /// bundle has no package dependency on StashKit (`project.yml`), only on the `Stash` app
    /// target, and drives it purely through the accessibility tree in a separate process.
    private static let baseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    private struct ScreenshotSeedError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func reviewAccessToken(email: String, password: String) async throws -> String {
        var request = URLRequest(
            url: Self.baseURL.appending(path: "/auth/v1/token")
                .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenshotSeedError(
                "review-account auth failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String
        else {
            throw ScreenshotSeedError("review-account auth response missing access_token")
        }
        return token
    }

    /// Polls `items?url=eq.<url>` until a row's `title` is both present and different from the
    /// bare URL itself — the signal that `add-url`'s server-side enrichment (real page title,
    /// og-image) has actually landed, not just that the row was created. Returns `false` on
    /// timeout rather than throwing, so the caller can assert with a clear message.
    private func pollLinkEnriched(url: String, email: String, password: String, timeout: TimeInterval) async throws -> Bool {
        let token = try await reviewAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.baseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [
                    URLQueryItem(name: "url", value: "eq.\(url)"),
                    URLQueryItem(name: "select", value: "title,url"),
                ]))
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let row = rows.first {
                let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty, title != url, title != row["url"] as? String {
                    return true
                }
            }
            try? await Task.sleep(for: .seconds(3))
        } while Date() < deadline
        return false
    }

    /// True if a `link` item with this exact `url` already exists — makes
    /// `testSeedReviewAccountContent` idempotent across reruns (e.g. after an earlier run seeded
    /// the 3 links + note but failed on the photo/voice steps): a rerun should never duplicate
    /// already-seeded links.
    private func linkAlreadyExists(url: String, email: String, password: String) async throws -> Bool {
        let token = try await reviewAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.baseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [
                    URLQueryItem(name: "url", value: "eq.\(url)"),
                    URLQueryItem(name: "select", value: "id"),
                ]))
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenshotSeedError("existence check failed for url '\(url)' (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return !rows.isEmpty
    }

    /// True if a `text` item whose `content` starts with this prefix already exists — same
    /// idempotency purpose as `linkAlreadyExists`, for the seeded short note.
    private func noteAlreadyExists(contentPrefix: String, email: String, password: String) async throws -> Bool {
        let token = try await reviewAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.baseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [
                    URLQueryItem(name: "content", value: "like.\(contentPrefix)*"),
                    URLQueryItem(name: "select", value: "id"),
                ]))
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenshotSeedError("existence check failed for note prefix '\(contentPrefix)' (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return !rows.isEmpty
    }

    // MARK: - Sign-in

    /// Unlike `StashUITests.signInAndReachLibrary`, this NEVER passes `--uitest-reset-auth`: the
    /// review account's Keychain session and its seeded library are meant to persist across runs
    /// of this suite (seeding is a one-time, idempotent-in-spirit operation; the screenshot pass
    /// re-launches against whatever is already there). If the app is already signed in (a prior
    /// launch in this same suite run, or a prior seeding pass on this simulator), this returns
    /// immediately once the tab bar is visible; otherwise it drives the real sign-in screen.
    @discardableResult
    private func signInAsReviewAndReachLibrary(_ app: XCUIApplication, email: String, password: String) -> Bool {
        app.launchArguments = []
        app.launch()

        if app.tabBars.buttons["View"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["View"].tap()
            return true
        }

        let emailField = app.textFields["signin.email"]
        guard emailField.waitForExistence(timeout: 10) else { return false }
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()

        // A fresh sign-in may show the once-per-install "How to easily stash" onboarding panel —
        // dismiss it via Skip and wait for it to actually finish animating out (not just for the
        // tap to register) so this helper works identically whether this is the review account's
        // first sign-in on this simulator or a later one.
        dismissOnboardingIfPresent(app)

        let viewTab = app.tabBars.buttons["View"]
        let reached = viewTab.waitForExistence(timeout: 15)
        if reached { viewTab.tap() }
        return reached
    }

    /// Defensive guard against the onboarding panel appearing (or still being mid-dismiss)
    /// between sign-in and the first composer interaction — confirmed live (task-4b's first
    /// seeding run) that a bare tap on "Skip" without waiting for the fullScreenCover's dismiss
    /// animation to finish left it still covering the Add tab by the time the very next step
    /// tried to type into `capture.editor`, failing with "Neither element nor any descendant has
    /// keyboard focus". Safe to call speculatively (short 2s existence check) at any point in
    /// either test below — a no-op when the panel isn't showing.
    private func dismissOnboardingIfPresent(_ app: XCUIApplication) {
        let skip = app.buttons["onboarding.skip"]
        guard skip.waitForExistence(timeout: 2) else { return }
        skip.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
        _ = XCTWaiter().wait(for: [gone], timeout: 10)
    }

    // MARK: - Seeding

    /// Seeds the review account through the app's OWN capture path (never a direct REST insert —
    /// the plan requires real enrichment: titles, og-images) with 3 links, 1 short note, 1 photo,
    /// and 1 voice note. STOPS (fails loudly, does not retry a workaround) if the account's
    /// capture is refused with `subscription_required` — per the plan-14 Task 4b instructions,
    /// that is a blocking condition to report, not something to route around.
    ///
    /// `@MainActor`: same reasoning `StashUITests.testEditSmoke`/`testLocationPinSmoke` document
    /// on their own `async throws` tests — XCTest only guarantees the main thread for a plain
    /// synchronous test; every `XCUIElement` call here (`tap()`, `typeText`, `waitForExistence`,
    /// `launch()`) is main-actor-isolated API, so without this the very first `app.launch()`
    /// throws `NSInternalInconsistencyException` off the main thread (confirmed live).
    @MainActor
    func testSeedReviewAccountContent() async throws {
        let (email, password) = try reviewCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAsReviewAndReachLibrary(app, email: email, password: password),
                      "Expected to reach the review account's library")

        // `.firstMatch` (not a bare identifier subscript, which requires EXACTLY one match and
        // throws "Multiple matching elements found" otherwise) — confirmed live, task-4b: some
        // assistant replies render as two `StaticText` views sharing the same
        // `ask.bubble.<N>` identifier (a main answer plus an appended follow-up-question
        // sentence), which made a plain subscript lookup ambiguous. Taking the first match is
        // safe here — every other identifier this helper resolves is genuinely unique — and
        // still returns a real, non-empty label for the streamed-answer stability poll either way.
        func anyElement(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }

        app.tabBars.buttons["Add"].tap()
        let editor = anyElement("capture.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "Expected the Add tab's composer")

        func captureText(_ text: String, label: String) {
            dismissOnboardingIfPresent(app)
            XCTAssertTrue(editor.waitForExistence(timeout: 10), "Composer editor not found before capturing \(label)")
            editor.tap()
            editor.typeText(text)

            let saveButton = app.buttons["capture.save"]
            XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button not found for \(label)")
            XCTAssertFalse(
                anyElement("capture.subscriptionGate").exists,
                "STOP: review account capture was refused (subscription_required) while capturing \(label) — do not work around this, report it")
            saveButton.tap()

            XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 15),
                          "Expected a success toast after saving \(label)")
            sleep(2)
        }

        // Idempotency (this seeding test is safe to rerun): skip a link/note that's already
        // present from an earlier run of this same test on this account — confirmed necessary
        // live (task-4b's first successful partial run seeded all 3 links + the note, then failed
        // on the photo step; a bare rerun would otherwise have quadrupled them).
        let links = [
            "https://www.nasa.gov",
            "https://www.nytimes.com/section/science",
            "https://en.wikipedia.org/wiki/Memory",
        ]
        for url in links {
            if try await linkAlreadyExists(url: url, email: email, password: password) {
                continue
            }
            captureText(url, label: "link \(url)")
        }

        let noteText = "Pick up the framed print from the shop on Valencia — closes at 6."
        if try await noteAlreadyExists(contentPrefix: "Pick up the framed print", email: email, password: password) == false {
            captureText(noteText, label: "the short note")
        }

        // Photo, via the real PhotosPicker against the simulator's own default Photos library —
        // seeded explicitly via `xcrun simctl addmedia` before this suite runs (confirmed live:
        // an unseeded fresh simulator install has NO default photos, unlike
        // `StashUITests.testComposerKeyboardAccessory`'s assumption of "seeded content every sim
        // ships with" — that held for whatever simulator that suite's own history happened to run
        // against, not for a brand-new sim). Same PHPickerViewController recipe otherwise.
        dismissOnboardingIfPresent(app)
        XCTAssertFalse(
            anyElement("capture.subscriptionGate").exists,
            "STOP: review account capture was refused (subscription_required) before the photo capture — do not work around this, report it")
        app.buttons["capture.photosPicker"].tap()
        // Excludes "PickerOnboardingHeaderViewIcon" — confirmed live (task-4b) that on a
        // PHPickerViewController's very first use on a given simulator, iOS inserts a one-time
        // onboarding banner ABOVE the actual photo grid, and a bare `.images.firstMatch` matches
        // that banner's icon instead of a real photo (tapping it selects nothing, so no "Add"
        // button and no attachment chip ever appear). Filtering it out by identifier lands on the
        // first real photo cell in every case, whether or not the banner is showing.
        let photoCell = app.scrollViews.firstMatch.images
            .matching(NSPredicate(format: "NOT (identifier CONTAINS[c] 'onboarding') AND NOT (label CONTAINS[c] 'onboarding')"))
            .firstMatch
        XCTAssertTrue(photoCell.waitForExistence(timeout: 15), "Expected the system photo picker to show at least one photo")
        // Confirmed live (task-4b): even after filtering the onboarding banner's OWN icon out of
        // the query above, the banner itself is a separate view stacked ON TOP of the grid's first
        // row for several seconds (it does not auto-dismiss quickly), which makes `.tap()`'s
        // hit-testing refuse the still-present, still-matched photo cell underneath ("Failed to
        // not hittable") — a 5s `isHittable` poll wasn't enough headroom. A raw coordinate tap at
        // the cell's own center bypasses XCUITest's hit-test-through-the-front-most-view check
        // entirely and delivers the touch to that screen location regardless of what else the
        // accessibility tree reports as being stacked there — safe here specifically because nothing
        // else in this composer flow could plausibly intercept a tap at these exact coordinates.
        photoCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let addButton = app.navigationBars.buttons["Add"]
        if addButton.waitForExistence(timeout: 5) { addButton.tap() }
        XCTAssertTrue(anyElement("capture.attachment.remove").waitForExistence(timeout: 10),
                      "Expected a photo attachment chip after picking a photo")

        let photoSaveButton = app.buttons["capture.save"]
        XCTAssertTrue(photoSaveButton.waitForExistence(timeout: 5), "Save button not found for the photo")
        photoSaveButton.tap()
        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 20),
                      "Expected a success toast after saving the photo")
        sleep(2)

        // Voice note, ~5s of (silent, simulator-mic) recording — same recipe as
        // `StashUITests.testVoiceNoteSmoke`.
        dismissOnboardingIfPresent(app)
        XCTAssertFalse(
            anyElement("capture.subscriptionGate").exists,
            "STOP: review account capture was refused (subscription_required) before the voice-note capture — do not work around this, report it")
        let voiceButton = anyElement("capture.voice")
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 10), "Expected the voice-note mic button")
        voiceButton.tap()
        let recordButton = anyElement("capture.voice.record")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Voice recorder sheet did not present its record button")
        recordButton.tap()
        let stopButton = anyElement("capture.voice.stop")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Expected the Stop button once recording starts")
        sleep(5)
        stopButton.tap()
        let voiceSaveButton = anyElement("capture.voice.save")
        XCTAssertTrue(voiceSaveButton.waitForExistence(timeout: 10), "Expected the preview state's Save button after Stop")
        voiceSaveButton.tap()
        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 20),
                      "Expected a success toast after saving the voice note")

        // Wait for link enrichment (titles/og-images) before this suite's screenshot pass runs —
        // REST-polled per URL rather than a blind sleep, so this scales with however long the
        // real `add-url` pipeline actually takes instead of guessing a fixed budget.
        for url in links {
            let enriched = try await pollLinkEnriched(url: url, email: email, password: password, timeout: 90)
            XCTAssertTrue(enriched, "Expected '\(url)' to be enriched (a real title, not the bare URL) within 90s")
        }
    }

    // MARK: - Screenshot capture

    /// Captures the six 6.9" frames as `SCREENSHOT_CHECKPOINT:` markers (see the class doc
    /// comment for the external `simctl io screenshot` mechanism this drives). Assumes
    /// `testSeedReviewAccountContent` has already run at least once against this simulator/build
    /// so the library has real, enriched content to show.
    func testCaptureStoreScreenshots() throws {
        let (email, password) = try reviewCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAsReviewAndReachLibrary(app, email: email, password: password),
                      "Expected to reach the review account's library")

        // `.firstMatch` (not a bare identifier subscript, which requires EXACTLY one match and
        // throws "Multiple matching elements found" otherwise) — confirmed live, task-4b: some
        // assistant replies render as two `StaticText` views sharing the same
        // `ask.bubble.<N>` identifier (a main answer plus an appended follow-up-question
        // sentence), which made a plain subscript lookup ambiguous. Taking the first match is
        // safe here — every other identifier this helper resolves is genuinely unique — and
        // still returns a real, non-empty label for the streamed-answer stability poll either way.
        func anyElement(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        func checkpoint(_ name: String, hold: UInt32 = 6) {
            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: \(name)\n".data(using: .utf8)!)
            sleep(hold)
        }
        // Confirmed live (task-4b): an identifier-based `.tap()` on a tab-bar button
        // intermittently resolves a `{-1, -1}` hit point — and so silently does nothing — when a
        // text field elsewhere in the tree (search, the Add composer, the Ask input) still holds
        // keyboard focus from the immediately-preceding step, even though `Library`/`Ask`'s own
        // keyboard-avoidance never actually covers the tab bar visually. A coordinate tap at the
        // button's own center bypasses that hit-test pre-check and reaches the real tab bar
        // button regardless, the same fix already proven for the photo-picker cell in
        // `testSeedReviewAccountContent`.
        func tapTab(_ label: String) {
            let button = app.tabBars.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(label) tab not found")
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // --- 01: View library (cards with images) ---
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")
        sleep(3)   // let card images finish loading in from cache/network
        checkpoint("01-view-library")

        // --- 02: Detail sheet of a link ---
        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found")
        searchField.tap()
        searchField.typeText("nasa.gov")
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 10), "Expected a card for the nasa.gov link")
        anyElement("card.typeChip").tap()
        let done = app.buttons["detail.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present")
        sleep(2)
        checkpoint("02-detail-link")
        done.tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
        // Clears the query AND resigns the search field's keyboard/focus in one tap
        // (`LibraryView.searchPill`'s own "clear AND dismiss" design) — confirmed live (task-4b)
        // that leaving the keyboard up (a bare delete-key `typeText` clears the text but never
        // drops focus) makes the tab bar briefly report an invalid `{-1, -1}` hit point for the
        // NEXT step's "Add" tap, silently swallowing it and leaving the Add tab's composer never
        // appearing.
        if app.buttons["library.search.clear"].waitForExistence(timeout: 5) {
            app.buttons["library.search.clear"].tap()
        }

        // --- 03: Add tab, composer with a typed line (never saved — a screenshot prop only) ---
        tapTab("Add")
        let editor = anyElement("capture.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Expected the Add tab's composer")
        let draftLine = "Remember to check the gallery opening this weekend"
        editor.tap()
        editor.typeText(draftLine)
        sleep(2)
        checkpoint("03-add-composer")
        if app.buttons["capture.dismissKeyboard"].waitForExistence(timeout: 5) {
            app.buttons["capture.dismissKeyboard"].tap()
        }
        editor.tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: draftLine.count))
        if app.buttons["capture.dismissKeyboard"].waitForExistence(timeout: 3) {
            app.buttons["capture.dismissKeyboard"].tap()
        }

        // --- 04: Ask with a short answer citing an item ---
        tapTab("Ask")
        let askInput = anyElement("ask.input")
        XCTAssertTrue(askInput.waitForExistence(timeout: 10), "Ask input field did not appear")
        // Starts a fresh, empty thread before asking — confirmed live (task-4b) that reruns of
        // this test against the review account's PERSISTENT conversation otherwise keep appending
        // to the same growing thread; by the 5th rerun the accumulated scrollback made XCUITest's
        // idle-detection time out entirely ("Failed to get matching snapshots: Timed out while
        // evaluating UI query") during the streamed reply, rather than merely running slower. A
        // new chat every run keeps the render footprint constant and disposable.
        if app.buttons["ask.newChat"].waitForExistence(timeout: 5) {
            app.buttons["ask.newChat"].tap()
        }
        askInput.tap()
        askInput.typeText("What did I save about the print shop on Valencia?")
        let sendButton = app.buttons["ask.send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Send button not found")
        sendButton.tap()

        XCTAssertFalse(anyElement("ask.gateError").waitForExistence(timeout: 2),
                       "Ask send was subscription-gate-blocked — adjudicate as gate, not a screenshot content problem")

        func lastBubbleIdentifier(timeout: TimeInterval) -> String? {
            let prefix = "ask.bubble."
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                let candidates = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
                    .allElementsBoundByIndex
                if let match = candidates.last(where: { el in
                    let suffix = el.identifier.dropFirst(prefix.count)
                    return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
                })?.identifier {
                    return match
                }
                usleep(300_000)
            } while Date() < deadline
            return nil
        }

        guard let bubbleId = lastBubbleIdentifier(timeout: 30) else {
            XCTFail("Assistant bubble did not appear")
            return
        }
        let assistantBubble = anyElement(bubbleId)
        var previousLabel: String?
        var stableStreak = 0
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let currentLabel = assistantBubble.label
            let meaningful = currentLabel.trimmingCharacters(in: .whitespaces)
            if !meaningful.isEmpty, currentLabel == previousLabel {
                stableStreak += 1
                if stableStreak >= 3 { break }
            } else {
                stableStreak = 0
            }
            previousLabel = currentLabel
            usleep(500_000)
        }
        XCTAssertFalse(assistantBubble.label.trimmingCharacters(in: .whitespaces).isEmpty,
                       "Expected a non-empty assistant answer")
        sleep(2)
        checkpoint("04-ask-answer")

        // Fresh relaunch rather than switching tabs directly out of Ask: confirmed live (task-4b)
        // that the Ask composer's `TextField` (`ChatComposerBar.swift`) has no focus-management or
        // `.onSubmit` of its own to resign via — unlike the Add tab's search field, which exposes
        // `library.search.clear` for exactly this. A software-keyboard `swipeDown()` gesture was
        // tried as a generic dismiss and rejected: it landed near enough to the keyboard's own
        // dictation control to pop a system "Enable Dictation?" prompt and background the app
        // entirely (see task-4b-report.md). Relaunching sidesteps the still-focused keyboard
        // altogether and reuses `signInAsReviewAndReachLibrary`'s already-proven cold-launch path
        // (a bare relaunch never re-shows the onboarding panel once it's been marked seen this
        // run) — no less realistic a screenshot precondition than a warm tab switch.
        app.terminate()
        XCTAssertTrue(signInAsReviewAndReachLibrary(app, email: email, password: password),
                      "Expected to reach the review account's library after relaunching for step 05")

        // --- 05: Share sheet, Safari → Stash compose card ---
        tapTab("Settings")
        XCTAssertTrue(anyElement("settings.subscription.status").waitForExistence(timeout: 15),
                      "Subscription status line not found")
        sleep(3)   // let SubscriptionStore.refresh() resolve + cache the gate before switching to Safari

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        let addressBar = safari.textFields["TabBarItemTitle"]
        XCTAssertTrue(addressBar.waitForExistence(timeout: 10), "Safari address bar not found")
        addressBar.tap()
        let urlField = safari.textFields["URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), "Safari URL edit field not found after tapping the address bar")
        // example.com, not apple.com: matches `StashUITests.testShareExtensionURLSmoke`'s own
        // proven choice — confirmed live (task-4b) that apple.com's much heavier page load can
        // leave Safari's toolbar in a state where "ShareButton" never appears within a normal
        // wait window, where example.com's near-instant load never has that problem.
        urlField.typeText("example.com\n")
        // On the iPhone 17 Pro Max's wider toolbar (confirmed live via a throwaway diagnostic
        // dump, task-4b), Safari collapses the dedicated Share icon into a "MoreMenuButton" ("•••")
        // — a direct "ShareButton" never appears on the bottom bar itself here, only inside that
        // menu once opened. `StashUITests.testShareExtensionURLSmoke` runs against a different,
        // narrower simulator where the bare icon still shows, so this tries the direct button
        // first (keeps this file's behavior aligned with that proven recipe wherever it still
        // holds) and only opens the "•••" menu as a fallback.
        var shareButton = safari.buttons["ShareButton"]
        if !shareButton.waitForExistence(timeout: 5) {
            let moreButton = safari.buttons["MoreMenuButton"]
            XCTAssertTrue(moreButton.waitForExistence(timeout: 10), "Neither Safari's Share button nor its More menu appeared")
            moreButton.tap()
            shareButton = safari.buttons["ShareButton"]
            XCTAssertTrue(shareButton.waitForExistence(timeout: 10), "Expected a Share entry inside Safari's More menu")
        }
        shareButton.tap()
        let stashCell = safari.cells["Stash"]
        XCTAssertTrue(stashCell.waitForExistence(timeout: 20), "Stash did not appear in the share sheet")
        stashCell.tap()

        let urlPreview = safari.staticTexts["share.preview.url"]
        XCTAssertTrue(urlPreview.waitForExistence(timeout: 20), "Compose card's URL preview did not render")
        // Gates on `share.save` (a Button), not `share.note` (a TextView): confirmed live,
        // task-4b, that reaching the compose card via Safari's "•••" More-menu route (this
        // device's toolbar layout, see the ShareButton fallback above) leaves `share.note`'s own
        // XCUITest snapshot unresolved for 20s+ even though a live screenshot at that exact moment
        // showed the "Optional note…" field genuinely, correctly on screen — some interaction
        // between the just-dismissed "•••" popover and this TextView's accessibility snapshot on
        // this device, not an actual rendering problem. `share.save` resolves reliably every time
        // and is present in the exact same frame as the note field, so gating on it captures an
        // identical screenshot without the flake.
        XCTAssertTrue(safari.buttons["share.save"].waitForExistence(timeout: 15), "Compose card's Save button did not render")
        sleep(2)
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: 05-share-compose\n".data(using: .utf8)!)
        sleep(6)

        // Cancel — this is a screenshot prop only; the three review-account links are already
        // seeded via the Add tab (`testSeedReviewAccountContent`), so this share is never saved.
        if safari.buttons["share.cancel"].waitForExistence(timeout: 5) {
            safari.buttons["share.cancel"].tap()
        }

        // --- 06: Share tutorial panel 2 (Settings → How to stash → advance one panel) ---
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15), "Expected to return to Stash")
        tapTab("Settings")
        let howToStashRow = app.buttons["settings.howToStash"]
        XCTAssertTrue(howToStashRow.waitForExistence(timeout: 10), "Expected the 'How to stash' Settings row")
        howToStashRow.tap()
        let primaryButton = app.buttons["onboarding.gotIt"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 10), "Expected the onboarding panel to open")
        XCTAssertEqual(primaryButton.label, "Next", "Expected panel 1's primary button labeled 'Next'")
        primaryButton.tap()   // panel 1 -> panel 2
        sleep(2)
        checkpoint("06-share-tutorial-panel2")

        let skipButton = app.buttons["onboarding.skip"]
        if skipButton.waitForExistence(timeout: 5) { skipButton.tap() }
    }
}
