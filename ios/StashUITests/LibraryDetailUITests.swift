import XCTest

/// Plan 16, Task 4 — two bugs in Will's 2026-09-30 device screenshots:
///
/// 1. A voice note's detail sheet was titled with its raw storage object name (`f200ad94-…`): the
///    card's type-label fallback now reaches the sheet as an EMPTY title field whose placeholder is
///    that label, and the sheet never writes a title the user didn't type.
/// 2. The View tab's "Search your stash" pill was half covered by the first card while it hid on
///    scroll: the pill is now the first element of the scroll content, above the cards, and
///    scrolls away with them instead of collapsing over them.
///
/// Self-contained like `DetailUITests` (its own sign-in and REST helpers). Seeded rows carry a
/// `UITEST-P16-` marker and are deleted in teardown blocks, so a failed assertion can't leak them;
/// `UITEST-FIXTURE` rows are never touched.
final class LibraryDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Detail title

    /// An audio row titled with a UUID object name (what an iOS share / Voice Memos upload stores):
    /// the sheet shows an empty title field with "Voice note" as its placeholder; opening and
    /// closing writes nothing; a title the server writes while the sheet is open (the transcription
    /// job's AI title, via realtime) replaces the placeholder and closing still writes nothing; and a
    /// typed title — into a field that really was empty — saves.
    @MainActor
    func testAnObjectNameTitleShowsTheTypeLabelAndIsOnlyEverWrittenWhenTyped() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let quietMarker = "UITEST-P16-\(epoch)-quiet"
        let typedMarker = "UITEST-P16-\(epoch)-typed"
        let quietName = "\(UUID().uuidString.lowercased()).m4a"
        let typedName = "\(UUID().uuidString.lowercased()).m4a"
        // Oldest first; no `file_path`, so the server's transcription sweep never picks them up and
        // nothing but this test writes their titles.
        let typedId = try await rest.insertItem(["type": "audio", "title": typedName, "content": "",
                                                 "description": "\(typedMarker) seeded audio"],
                                                attributes: ["media": ["duration_s": 5]])
        addTeardownBlock { try? await rest.deleteItem(id: typedId) }
        try await Task.sleep(for: .milliseconds(150))
        let quietId = try await rest.insertItem(["type": "audio", "title": quietName, "content": "",
                                                 "description": "\(quietMarker) seeded audio"],
                                                attributes: ["media": ["duration_s": 5]])
        addTeardownBlock { try? await rest.deleteItem(id: quietId) }

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let quietCard = libraryCard(app, containing: quietMarker)
        XCTAssertTrue(quietCard.waitForExistence(timeout: 20), "Expected the seeded voice note's card")
        XCTAssertTrue(quietCard.label.contains("Voice note"), "The card reads its type label, got '\(quietCard.label)'")

        // 1. Opening: an empty field with the card's label as placeholder — never the object name.
        quietCard.tap()
        let titleField = app.textFields["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        XCTAssertEqual(titleField.placeholderValue, "Voice note", "Expected the type label as the placeholder")
        // An empty text field reports its placeholder as its value; a filled one reports its text.
        XCTAssertEqual(titleField.value as? String, "Voice note",
                       "Expected an empty title field, got '\((titleField.value as? String) ?? "")'")
        attachScreenshot(named: "task-4-detail-placeholder")

        // 2. Closing without typing writes nothing (the close queues and sends anything unsaved at
        //    once, so a few seconds is plenty for a wrong write to have landed).
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let quietTitle = try await rest.title(of: quietId)
        XCTAssertEqual(quietTitle, quietName, "Opening and closing the sheet must not write a title")

        // 3. A title the server writes while the sheet is open replaces the placeholder, and closing
        //    afterwards still writes nothing.
        quietCard.tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found on reopen")
        XCTAssertEqual(titleField.placeholderValue, "Voice note")
        let aiTitle = "\(quietMarker) AI title"
        try await rest.setTitle(of: quietId, to: aiTitle)
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", aiTitle), object: titleField)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: 30), .completed,
                       "Expected the server's new title in the open sheet, got '\((titleField.value as? String) ?? "")'")
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let adoptedTitle = try await rest.title(of: quietId)
        XCTAssertEqual(adoptedTitle, aiTitle, "Closing after adopting the server's title must not write one")

        // 4. Typing a real title saves it — and the field held exactly what was typed (it was empty).
        let typedCard = libraryCard(app, containing: typedMarker)
        XCTAssertTrue(typedCard.waitForExistence(timeout: 20), "Expected the second seeded voice note's card")
        typedCard.tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        XCTAssertEqual(titleField.placeholderValue, "Voice note")
        let typed = "Groceries \(epoch)"
        tapUntilFocused(titleField)
        titleField.typeText(typed)
        XCTAssertEqual(titleField.value as? String, typed, "Expected exactly the typed title in a field that started empty")
        closeSheet(app)
        let saved = try await rest.waitForTitle(of: typedId, equalTo: typed, timeout: 20)
        XCTAssertTrue(saved, "Expected the typed title on the server")
    }

    // MARK: - Search pill

    /// Scrolls the View tab in small slow steps and samples the pill's and the first card's frames
    /// after each one: while the pill is visible (hittable) it never overlaps card 0, keeps its full
    /// height (nothing collapses), and moves up with the cards (constant gap), and at least two of
    /// the samples catch it part-way out. Screenshots of each visible step are kept for the report.
    @MainActor
    func testSearchPillNeverOverlapsTheFirstCardWhileVisible() throws {
        let (email, password) = try credentials()
        let app = XCUIApplication()
        signIn(app, email: email, password: password)

        let pill = app.descendants(matching: .any)["library.search.pill"]
        let field = app.textFields["library.search"]
        let card0 = app.descendants(matching: .any)["card.0"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Search pill not found")
        XCTAssertTrue(card0.waitForExistence(timeout: 20), "Expected at least one card")
        sleep(3)   // the cached first page, then the refreshed one, and their heroes, settle

        let restPill = pill.frame
        let restCard = card0.frame
        XCTAssertTrue(field.isHittable, "Expected the pill visible at rest")
        XCTAssertFalse(restPill.intersects(restCard), "At rest the pill \(restPill) overlaps card.0 \(restCard)")
        let restGap = restCard.minY - restPill.maxY
        attachScreenshot(named: "task-4-pill-rest")

        let window = app.windows.firstMatch.frame
        let dragStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.midX, dy: window.midY + 120))
        var partWayOut = 0
        for step in 1...14 {
            dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -22)),
                            withVelocity: .slow, thenHoldForDuration: 0.25)
            usleep(400_000)
            guard field.isHittable else { break }
            let pillFrame = pill.frame
            let cardFrame = card0.frame
            attachScreenshot(named: "task-4-pill-step-\(step)")
            XCTAssertFalse(pillFrame.intersects(cardFrame),
                           "Step \(step): the visible pill \(pillFrame) overlaps card.0 \(cardFrame)")
            XCTAssertEqual(pillFrame.height, restPill.height, accuracy: 1,
                           "Step \(step): the pill must keep its height while it scrolls away")
            XCTAssertEqual(cardFrame.minY - pillFrame.maxY, restGap, accuracy: 1,
                           "Step \(step): the pill must move with the cards")
            if pillFrame.minY < restPill.minY - 4 { partWayOut += 1 }
        }
        XCTAssertGreaterThanOrEqual(partWayOut, 2, "Expected to sample the pill part-way out while still visible")

        // Once it's gone, the cards run on up into the slot it left (nothing stays reserved for it).
        dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -60)),
                        withVelocity: .slow, thenHoldForDuration: 0.25)
        usleep(400_000)
        XCTAssertFalse(field.isHittable, "Expected the pill gone once scrolled past it")
        XCTAssertLessThan(card0.frame.minY, restPill.minY, "Expected card.0 to have scrolled up through the pill's old slot")
        attachScreenshot(named: "task-4-pill-gone")
    }

    // MARK: - Helpers

    private func credentials() throws -> (String, String) {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["STASH_TEST_EMAIL"], let password = environment["STASH_TEST_PASSWORD"],
              !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        return (email, password)
    }

    /// `--uitest-reset-auth` forces the real sign-in screen (the Keychain session survives
    /// reinstalls on the Simulator); `--uitest-tab-view` lands on the View tab once signed in — no
    /// tab-bar tap, which iOS 26 swallows while the sign-in keyboard is still going away (the tab
    /// button reports a {-1, -1} hit point then).
    @MainActor
    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        app.launchArguments = ["--uitest-reset-auth", "--uitest-tab-view"]
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        tapUntilFocused(emailField)
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        tapUntilFocused(passwordField)
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the tab bar after sign-in")
        // A fresh simulator's Passwords app offers "Save Password?" over the app after a sign-in
        // (seen on iOS 26.5) — decline it so it can't cover the View tab.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
    }

    /// The grid card (`card.<n>`) whose accessibility label contains `text`.
    @MainActor
    private func libraryCard(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#, text))
            .firstMatch
    }

    @MainActor
    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["detail.done"]
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "The sheet didn't close")
    }

    /// Taps `field` until it has keyboard focus (a tap can land while a sheet is still settling).
    @MainActor
    private func tapUntilFocused(_ field: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts {
            field.tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            if XCTWaiter().wait(for: [focused], timeout: 1.5) == .completed { return }
        }
    }

    /// A full-screen screenshot kept in the result bundle (exported for the task report).
    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// A password-grant REST session for the test account — seeds, reads, writes and deletes this
/// file's throwaway rows independently of the app. The public project URL + anon key are the ones
/// `StashConfig.swift` ships (not secrets); a UI-test bundle can't import StashKit.
private struct P16Rest: Sendable {
    static let baseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let token: String
    let userId: String

    static func signIn(email: String, password: String) async throws -> P16Rest {
        var request = URLRequest(url: baseURL.appending(path: "/auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await send(request)
        guard succeeded(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              let user = object["user"] as? [String: Any], let userId = user["id"] as? String
        else { throw Failure(description: "test-account sign-in failed") }
        return P16Rest(token: token, userId: userId)
    }

    /// `URLSession` with up to three tries on a transport error — only for the idempotent requests
    /// (auth, reads, the title write, deletes); the insert goes out once.
    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var tries = 1
        while true {
            do {
                return try await URLSession.shared.data(for: request)
            } catch let error as URLError where tries < 3 {
                print("REST retry after URLError \(error.code.rawValue)")
                tries += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func succeeded(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path).appending(queryItems: query))
        request.httpMethod = method
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func insertItem(_ fields: [String: Any], attributes: [String: Any] = [:]) async throws -> String {
        var body = fields
        body["user_id"] = userId
        body["is_public"] = false
        body["attributes"] = attributes
        var request = request("/rest/v1/items", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard Self.succeeded(response),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String
        else { throw Failure(description: "throwaway insert failed") }
        return id
    }

    func deleteItem(id: String) async throws {
        let (_, response) = try await Self.send(
            request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "DELETE"))
        guard Self.succeeded(response) else { throw Failure(description: "throwaway delete failed for \(id)") }
    }

    func title(of id: String) async throws -> String? {
        let (data, response) = try await Self.send(request("/rest/v1/items", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "title"),
        ]))
        guard Self.succeeded(response),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = rows.first
        else { throw Failure(description: "title read failed for \(id)") }
        return row["title"] as? String
    }

    /// A title write from outside the app — what the server's transcription job does when it
    /// replaces an object-name title with an AI one.
    func setTitle(of id: String, to title: String) async throws {
        var request = request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
        let (_, response) = try await Self.send(request)
        guard Self.succeeded(response) else { throw Failure(description: "title write failed for \(id)") }
    }

    func waitForTitle(of id: String, equalTo expected: String, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let title = try? await title(of: id), title == expected { return true }
            try await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return false
    }
}
