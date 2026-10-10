import UIKit
import XCTest

/// Run only on the isolated review-account QA simulator. Every write targets a disposable
/// UUID, and teardown deletes only that row; permanent review/fixture items are untouched.
final class DetailRefinementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCompactTitleExplicitSaveAndMediaOrder() async throws {
        let fixture = try await makeFixture()
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        defer { app.terminate() }
        open(fixture, in: app)

        let title = app.buttons["detail.title"]
        let media = element("detail.mediaStage", in: app)
        let description = element("detail.description", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, fixture.title, "The compact title must expose its entire text to VoiceOver")
        // At Large the panel title is 28pt. Two lines plus its touch floor fit below 84pt;
        // this fixture would need substantially more lines if rendered without a limit.
        XCTAssertGreaterThan(title.frame.height, 50, "The long fixture should occupy both title lines")
        XCTAssertLessThanOrEqual(title.frame.height, 84, "A collapsed title must stay within two lines")
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        assertAbove(title, media, "Title must precede the media stage")
        assertAbove(media, description, "Description must follow the media stage")
        XCTAssertFalse(element("detail.url.copy", in: app).exists)
        XCTAssertFalse(element("detail.openLink", in: app).exists)
        XCTAssertTrue(app.buttons["detail.url.edit"].exists)
        XCTAssertTrue(element("detail.eyebrow", in: app).label.lowercased().hasPrefix("youtube.com"),
                      "The machine header should start with the source, without a type chip")
        XCTAssertFalse(app.buttons["Original Content"].exists)
        screens.attachScreenshot(named: "detail-refined-layout")

        title.tap()
        let editor = element("detail.title.editor", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, fixture.title, "Opening the editor must preserve the full title")
        let save = app.buttons["detail.title.save"]
        let cancel = app.buttons["detail.title.cancel"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.exists)
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)

        let unsaved = "\(fixture.marker) — This is a local draft that Cancel must discard"
        replace(editor, with: unsaved, in: app)
        // Longer than the former 400ms title debounce: a premature autosave must be caught.
        try await Task.sleep(for: .seconds(1))
        let duringDraft = try await row(fixture)
        XCTAssertEqual(duringDraft["title"] as? String, fixture.title)
        A11yScreens.scrollIntoView(app, cancel)
        cancel.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, fixture.title)
        let afterCancel = try await row(fixture)
        XCTAssertEqual(afterCancel["title"] as? String, fixture.title)

        A11yScreens.scrollIntoView(app, title)
        title.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let committed = "\(fixture.marker) — Updated title after explicit Save"
        replace(editor, with: committed, in: app)
        screens.attachScreenshot(named: "detail-refined-title-editor")
        A11yScreens.scrollIntoView(app, save)
        save.tap()
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            title.exists && title.label == committed && !editor.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [collapsed], timeout: 15), .completed,
                       "A successful explicit Save should collapse the title editor")
        let afterSave = try await row(fixture)
        XCTAssertEqual(afterSave["title"] as? String, committed)
        assertPreservedContent(afterSave)

        // An unflagged source must never be relabelled as the video's transcript.
        let transcript = app.buttons["Transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Summary"].exists)
        XCTAssertFalse(app.buttons["Original Content"].exists)
        A11yScreens.scrollIntoView(app, transcript)
        transcript.tap()
        let transcriptText = element("detail.transcriptText", in: app)
        XCTAssertTrue(transcriptText.waitForExistence(timeout: 5))
        XCTAssertTrue(transcriptText.label.contains("No transcript"))
        XCTAssertFalse(transcriptText.label.contains(Self.sourceBody))

        app.terminate()
        _ = screens.launch(.large, tab: .view)
        open(fixture, in: app)
        XCTAssertEqual(app.buttons["detail.title"].label, committed)
        XCTAssertFalse(element("detail.title.editor", in: app).exists)
        let reloaded = try await row(fixture)
        XCTAssertEqual(reloaded["title"] as? String, committed)
        assertPreservedContent(reloaded)

        app.terminate()
        _ = screens.launch(.ax3, tab: .view)
        open(fixture, in: app)
        let largeTitle = app.buttons["detail.title"]
        XCTAssertTrue(largeTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(largeTitle.label, committed)
        let twoLineLimit = UIFontMetrics(forTextStyle: .title1)
            .scaledValue(for: 84, compatibleWith: A11yVariant.ax3.traits)
        XCTAssertLessThanOrEqual(largeTitle.frame.height, twoLineLimit,
                                 "Accessibility text must still use a compact two-line reading title")
        largeTitle.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, committed)
        replace(editor, with: "\(fixture.marker) — Accessibility draft to cancel", in: app)
        revealActionAboveKeyboard(save, in: app)
        XCTAssertTrue(save.isHittable, "Save must be reachable at AX3 with the keyboard open")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        screens.attachScreenshot(named: "detail-refined-title-editor")
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(largeTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(largeTitle.label, committed)
        let afterAccessibilityCancel = try await row(fixture)
        XCTAssertEqual(afterAccessibilityCancel["title"] as? String, committed)
        assertPreservedContent(afterAccessibilityCancel)
    }

    private static let address = "https://www.youtube.com/watch?v=M7lc1UVf-VE"
    private static let notes = "Disposable detail-refinement notes must survive title editing."
    private static let description = "This description belongs below the media stage."
    private static let sourceBody = "UI TEST original page text; this is deliberately not a transcript."
    private static let summary = "A disposable detail refinement acceptance fixture."
    private struct Fixture { let id: String; let userID: String; let marker: String; let title: String; let token: String }
    private struct FixtureError: Error { let operation: String; let status: Int }

    private func makeFixture() async throws -> Fixture {
        let env = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(env["STASH_TEST_EMAIL"])
        let password = try XCTUnwrap(env["STASH_TEST_PASSWORD"])
        try XCTSkipUnless(email.lowercased().contains("+review@"), "Use the dedicated review account on its isolated QA simulator")
        let auth = try await request("auth/v1/token?grant_type=password", method: "POST",
                                     body: ["email": email, "password": password])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: auth) as? [String: Any])
        let token = try XCTUnwrap(object["access_token"] as? String)
        let userID = try XCTUnwrap((object["user"] as? [String: Any])?["id"] as? String)
        let id = UUID().uuidString
        let marker = "UITEST-DETAIL-REFINE-\(id.prefix(8))"
        let title = "\(marker) — A deliberately long saved video title that spans many lines when expanded, with enough complete words to prove that the compact reading title stops after two lines while keeping the entire original title available for editing"
        addTeardownBlock {
            _ = try await self.request("rest/v1/items?id=eq.\(id)&user_id=eq.\(userID)", method: "DELETE", token: token)
        }
        _ = try await request("rest/v1/items", method: "POST", token: token, body: [
            "id": id, "user_id": userID, "type": "link", "title": title,
            "url": Self.address, "description": Self.description, "content": Self.notes,
            "summary": Self.summary, "page_body": Self.sourceBody, "is_public": false,
            "attributes": ["link": ["flavor": "video", "canonical_url": Self.address],
                           "enrichment": ["evidence": ["transcript": false],
                                          "protected_fields": ["title": true, "description": true, "summary": true, "page_body": true]],
                           "fixture_preserve": "untouched"]
        ])
        return Fixture(id: id, userID: userID, marker: marker, title: title, token: token)
    }

    private func row(_ fixture: Fixture) async throws -> [String: Any] {
        let data = try await request("rest/v1/items?id=eq.\(fixture.id)&user_id=eq.\(fixture.userID)&select=*", token: fixture.token)
        return try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first)
    }

    private func assertPreservedContent(_ row: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(row["content"] as? String, Self.notes, file: file, line: line)
        XCTAssertEqual(row["description"] as? String, Self.description, file: file, line: line)
        XCTAssertEqual(row["summary"] as? String, Self.summary, file: file, line: line)
        XCTAssertEqual(row["page_body"] as? String, Self.sourceBody, file: file, line: line)
        XCTAssertEqual(row["url"] as? String, Self.address, file: file, line: line)
        XCTAssertEqual(row["is_public"] as? Bool, false, file: file, line: line)
    }

    private func request(_ path: String, method: String = "GET", token: String? = nil,
                         body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: StashTestProject.baseURL.appendingPathComponent("/"))!)
        request.httpMethod = method
        request.setValue(StashTestProject.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? StashTestProject.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let retryable = method == "GET" || method == "DELETE" || path.hasPrefix("auth/v1/token")
        var attempt = 1
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(status) else { throw FixtureError(operation: method, status: status) }
                return data
            } catch let error as URLError where retryable && attempt < 3 && error.code != .cancelled && !Task.isCancelled {
                attempt += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor private func open(_ fixture: Fixture, in app: XCUIApplication) {
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        replace(search, with: fixture.marker, in: app)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                   "card.", fixture.marker)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10))
    }

    @MainActor private func replace(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        A11yScreens.tapUntilFocused(field)
        let old = field.value as? String ?? ""
        if !old.isEmpty && old != field.placeholderValue {
            field.press(forDuration: 1.1)
            var selectAll = app.menuItems["Select All"].exists ? app.menuItems["Select All"] : app.buttons["Select All"]
            // At AX3 the native edit menu fits Paste / Select on its first page. Its
            // observed Forward control reveals Select All without changing the editor.
            for _ in 0..<3 where !selectAll.exists && app.buttons["Forward"].exists {
                app.buttons["Forward"].tap()
                selectAll = app.menuItems["Select All"].exists ? app.menuItems["Select All"] : app.buttons["Select All"]
            }
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
            selectAll.tap()
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    @MainActor private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The editing viewport ends above the pinned Delete/keyboard-dismiss footer, which
    /// itself sits above the keyboard. Start inside that viewport, never on the footer.
    @MainActor private func revealActionAboveKeyboard(_ action: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            let bottom = min(keyboardTop, app.buttons["detail.delete"].frame.minY) - 12
            if action.isHittable && action.frame.maxY < bottom - 8 { return }
            let distance = action.frame.midY - (bottom - 40)
            let movement = max(-140, min(140, -distance))
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width - 12, dy: bottom - 35))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: movement)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    @MainActor private func assertAbove(_ first: XCUIElement, _ second: XCUIElement, _ message: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(first.frame.height, 0, file: file, line: line)
        XCTAssertGreaterThan(second.frame.height, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(first.frame.maxY, second.frame.minY + 2, message, file: file, line: line)
    }
}
