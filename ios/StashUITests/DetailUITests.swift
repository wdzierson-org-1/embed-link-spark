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

    /// Final wave B: a location edit is written onto the server's CURRENT attributes — never the
    /// sheet's copy. Production writes `attributes` while a sheet is open (the transcription job's
    /// `media.transcript`, enrichment's `enrichment.*`); here the test itself writes a key from
    /// outside the app after the sheet has read its copy, and commits the edit at once — before
    /// realtime could bring that key into the sheet. The server must keep that key, the seeded
    /// `link`, and get the new location.
    @MainActor
    func testALocationEditKeepsAttributesTheServerWroteWhileTheSheetWasOpen() async throws {
        let (email, password) = try credentials()
        let rest = try await RestSession.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let title = "UITEST-DETAIL: location \(epoch)"
        let seededLocation: [String: Any] = ["label": "Seed Location", "source": "device-geolocation",
                                             "latitude": 40.7128, "longitude": -74.006]
        let id = try await rest.insertItem(["type": "text", "title": title, "content": ""],
                                           attributes: ["location": seededLocation, "link": ["flavor": "article"]])
        addTeardownBlock { try? await rest.deleteItem(id: id) }

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let card = libraryCard(app, titled: title)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        card.tap()

        let details = app.descendants(matching: .any)["detail.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10), "Details drawer row not found")
        details.tap()
        let label = app.descendants(matching: .any)["detail.location.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "Expected the seeded location")
        label.tap()
        let field = app.descendants(matching: .any)["detail.location.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Location field didn't open")
        let prefilled = (field.value as? String) ?? ""
        field.tap()
        if !prefilled.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prefilled.count))
        }
        field.typeText("Test City")

        // The server writes a key the sheet has never seen — then the edit is committed at once.
        let marker = "server-write-\(epoch)"
        var serverAttributes = try await rest.attributes(of: id)
        serverAttributes["uitest_server_write"] = ["marker": marker]
        try await rest.setAttributes(of: id, to: serverAttributes)
        field.typeText("\n")

        let edited = app.descendants(matching: .any)["detail.location.label"]
        XCTAssertTrue(edited.waitForExistence(timeout: 10), "Expected the edited location row")
        XCTAssertEqual(edited.label, "posted from Test City")

        var saved: [String: Any] = [:]
        let deadline = Date().addingTimeInterval(20)
        repeat {
            saved = try await rest.attributes(of: id)
            if (saved["location"] as? [String: Any])?["label"] as? String == "Test City" { break }
            try await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        let location = saved["location"] as? [String: Any]
        XCTAssertEqual(location?["label"] as? String, "Test City", "The edit reached the server")
        XCTAssertEqual(location?["source"] as? String, "manual")
        XCTAssertEqual((saved["uitest_server_write"] as? [String: Any])?["marker"] as? String, marker,
                       "A key the server wrote while the sheet was open must survive the location save")
        XCTAssertEqual((saved["link"] as? [String: Any])?["flavor"] as? String, "article")
        app.buttons["detail.done"].tap()
    }

    /// Plan 15 wrap: a transcription job that ended `failed` left no transcript — the Transcript tab
    /// says why instead of "Transcription in progress…" forever (`no_speech` gets its own sentence).
    /// The seeded audio rows have no `file_path`, so the server's transcription sweep never picks
    /// them up.
    @MainActor
    func testAFailedTranscriptionSaysSoInsteadOfInProgress() async throws {
        let (email, password) = try credentials()
        let rest = try await RestSession.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let cases = [("UITEST-DETAIL: no speech \(epoch)", "no_speech", "No speech was detected in this recording."),
                     ("UITEST-DETAIL: failed transcript \(epoch)", "transcription_failed", "Couldn't transcribe this recording.")]
        for (title, code, _) in cases {
            let transcript: [String: Any] = ["status": "failed", "error": code, "attempts": 3, "updated_at": stamp]
            let id = try await rest.insertItem(["type": "audio", "title": title, "content": ""],
                                               attributes: ["media": ["duration_s": 4, "transcript": transcript]])
            addTeardownBlock { try? await rest.deleteItem(id: id) }
        }

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        for (title, _, expected) in cases {
            let card = libraryCard(app, titled: title)
            XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card '\(title)'")
            card.tap()
            let transcript = app.descendants(matching: .any)["detail.transcriptText"]
            XCTAssertTrue(transcript.waitForExistence(timeout: 10), "Transcript text container not found")
            let honest = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected),
                                                   object: transcript)
            XCTAssertEqual(XCTWaiter().wait(for: [honest], timeout: 10), .completed,
                           "Expected '\(expected)', got '\(transcript.label)'")
            let close = app.buttons["detail.done"]
            close.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
            XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "The sheet didn't close")
        }
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

    func attributes(of id: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request("/rest/v1/items", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "attributes"),
        ]))
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = rows.first
        else { throw Failure(description: "attributes read failed for \(id)") }
        return row["attributes"] as? [String: Any] ?? [:]
    }

    /// A write to `attributes` from outside the app — what production's async writers (the
    /// transcription job, enrichment) do while a detail sheet is open.
    func setAttributes(of id: String, to attributes: [String: Any]) async throws {
        var request = request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["attributes": attributes])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw Failure(description: "attributes write failed for \(id)")
        }
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
