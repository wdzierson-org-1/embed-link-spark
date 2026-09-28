import XCTest

/// Plan 15 Task 6B (detail sheet): closing never waits on the network and never loses an edit.
///
/// Every test seeds its own throwaway `UITEST-DETAIL:` row straight into `items` (PostgREST, RLS
/// scopes it to the test account — the lapsed account's `add-note` answers 403) and deletes it in a
/// teardown block, so a failed assertion can't leak it. `UITEST-FIXTURE` rows are never touched.
///
/// A standalone file (`StashUITests.swift` belongs to another task this round), so it carries its
/// own small sign-in and REST helpers — the same recipes `StashUITests` uses.
final class DetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// H5 on a stalled link (`--uitest-stall-item-writes`: every item write hangs 10 s, then times
    /// out): a note typed into the sheet while its autosave is stuck in flight survives an instant
    /// close — the X doesn't wait on the stuck save — reopening shows it (queued, laid over the
    /// list), the server doesn't have it yet, and once the app runs again with a working network
    /// the launch refresh delivers it.
    @MainActor
    func testNoteTypedOnAStalledLinkSurvivesAnInstantCloseAndLandsLater() async throws {
        let (email, password) = try credentials()
        let rest = try await RestSession.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let title = "UITEST-DETAIL: stalled \(epoch)"
        let marker = "stalled-note-\(epoch)"
        let id = try await rest.insertItem(["type": "text", "title": title, "content": ""])
        addTeardownBlock { try? await rest.deleteItem(id: id) }

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-stall-item-writes"])
        let card = libraryCard(app, titled: title)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        card.tap()

        let notes = app.textViews["detail.notes.editor"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Notes editor not found")
        notes.tap()
        // Same warm-up keystroke `testEditSmoke` documents: the first characters typed into a
        // freshly tapped TextEditor can land before its selection settles.
        notes.typeText("x")
        sleep(1)
        notes.typeText(marker)
        sleep(2)   // the 600 ms notes debounce has fired: that save is now stuck in flight

        let close = app.buttons["detail.done"]
        let started = Date()
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 4), .completed, "The sheet didn't close")
        XCTAssertLessThan(Date().timeIntervalSince(started), 4, "Closing must not wait on the stuck save")

        card.tap()
        let reopened = app.textViews["detail.notes.editor"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10), "Notes editor not found on reopen")
        XCTAssertTrue(((reopened.value as? String) ?? "").contains(marker),
                      "Expected the queued note on reopen, got '\((reopened.value as? String) ?? "")'")
        let serverContent = try await rest.content(of: id)
        XCTAssertFalse(serverContent.contains(marker), "The stalled link can't have delivered the note yet")
        app.buttons["detail.done"].tap()

        // The network is back: run the app again without the switch (still signed in) — its
        // launch refresh flushes the queue before it reads page 1.
        app.terminate()
        app.launchArguments = ["--uitest-tab-view"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in")
        let delivered = try await rest.waitForContent(of: id, containing: marker, timeout: 30)
        XCTAssertTrue(delivered, "Expected the queued note to reach the server once the network returned")
        XCTAssertTrue(libraryCard(app, titled: title).waitForExistence(timeout: 15))
    }

    /// H5 on a working network: a title edit closed straight away — still inside its 400 ms
    /// autosave debounce, so nothing has sent it yet — reaches the server anyway (the close queues
    /// it and sends it at once), alongside a note typed just before; the list shows the new title.
    @MainActor
    func testATitleClosedInsideItsDebounceStillReachesTheServer() async throws {
        let (email, password) = try credentials()
        let rest = try await RestSession.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let title = "UITEST-DETAIL: quick \(epoch)"
        let marker = "quick-note-\(epoch)"
        let id = try await rest.insertItem(["type": "text", "title": title, "content": ""])
        addTeardownBlock { try? await rest.deleteItem(id: id) }

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let card = libraryCard(app, titled: title)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        card.tap()

        let notes = app.textViews["detail.notes.editor"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Notes editor not found")
        notes.tap()
        notes.typeText("x")
        sleep(1)
        notes.typeText(marker)

        let titleField = app.descendants(matching: .any)["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        titleField.tap()
        titleField.typeText("Q")
        // Where a tap lands the caret in this field isn't reliable (see `testEditSmoke`), so the
        // expected title is whatever the field now holds.
        let editedTitle = (titleField.value as? String) ?? ""
        XCTAssertNotEqual(editedTitle, title, "The title edit didn't register")

        let close = app.buttons["detail.done"]
        close.tap()   // at once: the title's debounce hasn't fired
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 4), .completed, "The sheet didn't close")

        let delivered = try await rest.waitForRow(of: id, timeout: 20) { row in
            (row["title"] as? String) == editedTitle && ((row["content"] as? String) ?? "").contains(marker)
        }
        XCTAssertTrue(delivered, "Expected the title (and the note) on the server after an immediate close")
        XCTAssertTrue(libraryCard(app, titled: editedTitle).waitForExistence(timeout: 10),
                      "Expected the card to show the edited title")
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
    /// reinstalls on the Simulator); lands on the View tab.
    @MainActor
    private func signIn(_ app: XCUIApplication, email: String, password: String, extraArguments: [String] = []) {
        app.launchArguments = ["--uitest-reset-auth"] + extraArguments
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        let viewTab = app.tabBars.buttons["View"]
        XCTAssertTrue(viewTab.waitForExistence(timeout: 15), "Expected the tab bar after sign-in")
        viewTab.tap()
    }

    /// The grid card (`card.<n>`) whose accessibility label contains `title`.
    @MainActor
    private func libraryCard(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#, title))
            .firstMatch
    }
}

/// A password-grant REST session for the test account — seeds, reads and deletes throwaway rows
/// independently of whatever the app itself is doing.
private struct RestSession: Sendable {
    /// The public project URL + anon key `StashConfig.swift` ships (not secrets — the web client
    /// ships them too). A UI-test bundle can't import StashKit.
    static let baseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let token: String
    let userId: String

    static func signIn(email: String, password: String) async throws -> RestSession {
        var request = URLRequest(url: baseURL.appending(path: "/auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              let user = object["user"] as? [String: Any], let userId = user["id"] as? String
        else { throw Failure(description: "test-account sign-in failed") }
        return RestSession(token: token, userId: userId)
    }

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path).appending(queryItems: query))
        request.httpMethod = method
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func insertItem(_ fields: [String: Any]) async throws -> String {
        var body = fields
        body["user_id"] = userId
        body["is_public"] = false
        body["attributes"] = [String: Any]()
        var request = request("/rest/v1/items", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String
        else { throw Failure(description: "throwaway insert failed") }
        return id
    }

    func deleteItem(id: String) async throws {
        let (_, response) = try await URLSession.shared.data(
            for: request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "DELETE"))
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw Failure(description: "throwaway delete failed for \(id)")
        }
    }

    func row(of id: String) async throws -> [String: Any]? {
        let (data, response) = try await URLSession.shared.data(for: request("/rest/v1/items", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "id,title,content"),
        ]))
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw Failure(description: "row read failed for \(id)")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first
    }

    func content(of id: String) async throws -> String {
        (try await row(of: id)?["content"] as? String) ?? ""
    }

    func waitForRow(of id: String, timeout: TimeInterval, until matches: ([String: Any]) -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let row = try? await row(of: id), matches(row) { return true }
            try await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return false
    }

    func waitForContent(of id: String, containing marker: String, timeout: TimeInterval) async throws -> Bool {
        try await waitForRow(of: id, timeout: timeout) { (($0["content"] as? String) ?? "").contains(marker) }
    }
}
