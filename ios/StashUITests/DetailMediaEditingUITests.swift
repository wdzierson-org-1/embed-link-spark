import XCTest

/// Native acceptance on an isolated QA simulator. Every mutation targets a disposable UUID;
/// the synthetic transcript is explicitly a fixture, not a claim about the public test video.
final class DetailMediaEditingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAddressValidationCancelSaveAndReloadPreserveCapturedText() async throws {
        let fixture = try await makeFixture()
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        defer { app.terminate() }
        open(fixture, in: app)

        let transcript = app.buttons["Transcript"]
        A11yScreens.scrollIntoView(app, transcript)
        XCTAssertTrue(transcript.exists)
        XCTAssertFalse(app.buttons["Original Content"].exists, "Flagged video source is a transcript")
        transcript.tap()
        XCTAssertTrue(element("detail.transcriptText", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("detail.transcriptText", in: app).label.contains(Self.body))
        screens.attachScreenshot(named: "detail-video-transcript")
        app.buttons["Summary"].tap()
        screens.attachScreenshot(named: "detail-video-summary")

        let edit = app.buttons["detail.url.edit"]
        A11yScreens.scrollIntoView(app, edit)
        edit.tap()
        let field = app.textFields["detail.url.editor"]
        replace(field, with: "javascript:alert(1)")
        app.buttons["detail.url.save"].tap()
        XCTAssertTrue(element("detail.url.error", in: app).waitForExistence(timeout: 5))
        let unchanged = try await row(fixture)
        XCTAssertEqual(unchanged["url"] as? String, Self.address)
        app.buttons["detail.url.cancel"].tap()
        XCTAssertEqual(element("detail.urlText", in: app).label, Self.address)

        edit.tap()
        replace(field, with: "example.com/updated-source")
        app.buttons["detail.url.save"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 15), "A successful save closes address editing")
        let changed = try await row(fixture)
        XCTAssertEqual(changed["url"] as? String, "https://example.com/updated-source")
        XCTAssertEqual(changed["supplemental_note"] as? String, Self.note)
        XCTAssertEqual(changed["page_body"] as? String, Self.body)
        XCTAssertEqual(changed["summary"] as? String, Self.summary)
        let attributes = try XCTUnwrap(changed["attributes"] as? [String: Any])
        XCTAssertNil(attributes["link"], "Old canonical address cannot override the edit")
        XCTAssertNil((attributes["enrichment"] as? [String: Any])?["evidence"])
        XCTAssertEqual(attributes["fixture_preserve"] as? String, "untouched")
        XCTAssertEqual(changed["is_public"] as? Bool, false)
        screens.attachScreenshot(named: "detail-edited-address")

        app.terminate()
        _ = screens.launch(.large, tab: .view)
        open(fixture, in: app)
        XCTAssertEqual(element("detail.urlText", in: app).label, "https://example.com/updated-source")
        XCTAssertFalse(app.buttons["Transcript"].exists)
        XCTAssertFalse(element("detail.mediaStage", in: app).exists)
        let original = app.buttons["Original Content"]
        A11yScreens.scrollIntoView(app, original)
        original.tap()
        XCTAssertTrue(element("detail.originalText", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("detail.originalText", in: app).label.contains(Self.body))
    }

    @MainActor
    func testVideoPlayAndFullScreenKeepTheSamePlaybackPosition() async throws {
        let fixture = try await makeFixture()
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        defer { app.terminate() }
        open(fixture, in: app)
        let player = element("detail.media.webPlayer", in: app)
        A11yScreens.scrollIntoView(app, player)
        XCTAssertTrue(player.waitForExistence(timeout: 15))
        let fullscreen = app.buttons["detail.media.fullscreen"]
        XCTAssertFalse((fullscreen.value as? String ?? "").contains("state:playing"), "Opening detail must not autoplay")
        let play = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Play")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 30), "Provider must expose a real play control")
        play.tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let status = fullscreen.value as? String ?? ""
            return status.contains("state:playing") && self.seconds(status) > 5
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [playing], timeout: 30), .completed,
                       "Real IFrame API must report playing/time; a loaded web view is not enough")
        screens.attachScreenshot(named: "detail-video-playing")
        let before = seconds(fullscreen.value as? String ?? "")
        A11yScreens.scrollIntoView(app, fullscreen)
        fullscreen.tap()
        let close = app.buttons["detail.media.closeFullscreen"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        // Wait while the exact same WKWebView plays in its native full-screen host.
        try await Task.sleep(for: .seconds(3))
        screens.attachScreenshot(named: "detail-video-fullscreen")
        close.tap()
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(seconds(fullscreen.value as? String ?? ""), before + 1,
                             "Full-screen transition must retain and advance the existing playback")
        app.buttons["detail.done"].tap()
        XCTAssertTrue(app.textFields["library.search"].waitForExistence(timeout: 10))
    }

    private static let address = "https://www.youtube.com/watch?v=M7lc1UVf-VE"
    private static let body = "UI TEST transcript fixture. This text verifies transcript routing only."
    private static let summary = "A disposable native playback and link-editing test."
    private static let note = "UI TEST note must survive an address edit."
    private struct Fixture { let id: String; let title: String; let token: String }
    private struct FixtureError: Error { let operation: String; let status: Int }

    private func makeFixture() async throws -> Fixture {
        let env = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(env["STASH_TEST_EMAIL"])
        let password = try XCTUnwrap(env["STASH_TEST_PASSWORD"])
        let auth = try await request("auth/v1/token?grant_type=password", method: "POST",
                                     body: ["email": email, "password": password])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: auth) as? [String: Any])
        let token = try XCTUnwrap(object["access_token"] as? String)
        let user = try XCTUnwrap((object["user"] as? [String: Any])?["id"] as? String)
        let id = UUID().uuidString
        let title = "UITEST-MEDIA-EDIT-\(id.prefix(8))"
        addTeardownBlock {
            _ = try await self.request("rest/v1/items?id=eq.\(id)", method: "DELETE", token: token)
        }
        _ = try await request("rest/v1/items", method: "POST", token: token, body: [
            "id": id, "user_id": user, "type": "link", "title": title,
            "url": Self.address, "summary": Self.summary, "page_body": Self.body,
            "supplemental_note": Self.note, "is_public": false,
            "attributes": ["link": ["flavor": "video", "canonical_url": Self.address],
                           "enrichment": ["evidence": ["transcript": true, "canonical_url": Self.address]],
                           "fixture_preserve": "untouched"]
        ])
        return Fixture(id: id, title: title, token: token)
    }

    private func row(_ fixture: Fixture) async throws -> [String: Any] {
        let data = try await request("rest/v1/items?id=eq.\(fixture.id)&select=*", token: fixture.token)
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first)
    }

    private func request(_ path: String, method: String = "GET", token: String? = nil,
                         body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: StashTestProject.baseURL.appendingPathComponent("/"))!)
        request.httpMethod = method
        request.setValue(StashTestProject.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? StashTestProject.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await fixtureData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw FixtureError(operation: method, status: status) }
        return data
    }

    /// The simulator's HTTP/3 connection may close between assertions and cleanup.
    /// Retry only idempotent bookkeeping; never replay a fixture insertion.
    private func fixtureData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let canRetry = ["GET", "DELETE"].contains(request.httpMethod ?? "GET")
            || request.url?.path.hasSuffix("/auth/v1/token") == true
        var attempt = 1
        while true {
            do { return try await URLSession.shared.data(for: request) }
            catch let error as URLError where canRetry && attempt < 3 && error.code != .cancelled {
                attempt += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor private func open(_ fixture: Fixture, in app: XCUIApplication) {
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        replace(search, with: fixture.title)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                   "card.", fixture.title)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10))
    }

    @MainActor private func replace(_ field: XCUIElement, with text: String) {
        A11yScreens.tapUntilFocused(field)
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != field.placeholderValue {
            // A tap may place the caret in the middle of a long URL. Backspacing its length
            // would leave the trailing suffix intact, so use the native selection action.
            field.press(forDuration: 1.1)
            let app = XCUIApplication()
            let selectAll = app.menuItems["Select All"].exists
                ? app.menuItems["Select All"] : app.buttons["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
            selectAll.tap()
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "The editor must contain exactly the intended test value")
    }

    @MainActor private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func seconds(_ label: String) -> Double { Double(label.components(separatedBy: "time:").last ?? "") ?? 0 }
}
