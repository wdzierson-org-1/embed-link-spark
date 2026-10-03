import UIKit
import XCTest

/// Drives the real sign-in screen against production Supabase (test account creds are
/// injected via TEST_RUNNER_ environment variables, never hardcoded). Covers both the
/// wrong-password error path and the successful sign-in path in one launch so the two
/// scenarios can't drift out of order across reruns.
final class StashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Plan 16: the real Bold Text setting is simulator-global, and an interrupted a11y run can
        // leave it on — which would silently turn every screen here bold.
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    func testWrongPasswordShowsErrorThenCorrectPasswordSignsIn() throws {
        guard
            let email = ProcessInfo.processInfo.environment["STASH_TEST_EMAIL"],
            let password = ProcessInfo.processInfo.environment["STASH_TEST_PASSWORD"],
            !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            return
        }

        let app = XCUIApplication()
        // Without this, a second consecutive run against the same simulator finds a
        // Keychain session already persisted from the first run's successful sign-in
        // (uninstall/reinstall doesn't clear it — see task-8-report.md Adaptation #5),
        // so the app launches straight into MainTabView, "signin.email" never appears,
        // and the test fails on a timeout that looks like a regression but is stale state.
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        let passwordField = app.secureTextFields["signin.password"]
        let submitButton = app.buttons["signin.submit"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")

        emailField.tap()
        emailField.typeText(email)

        let wrongPassword = "wrong-\(password)"
        passwordField.tap()
        passwordField.typeText(wrongPassword)

        submitButton.tap()

        let errorText = app.staticTexts["signin.error"]
        XCTAssertTrue(
            errorText.waitForExistence(timeout: 10),
            "Expected an error message after signing in with the wrong password"
        )

        // Replace the wrong password with the correct one (secure fields don't support
        // reliable select-all-via-gesture in XCUITest, so backspace it out by length instead).
        passwordField.tap()
        passwordField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: wrongPassword.count))
        passwordField.typeText(password)

        submitButton.tap()

        let viewTab = app.tabBars.buttons["View"]
        XCTAssertTrue(
            viewTab.waitForExistence(timeout: 15),
            "Expected the tab bar (View tab) to appear after signing in with correct credentials"
        )
    }

    /// Env-sourced test creds, shared by the two tests below (the wrong-password test above
    /// keeps its own inline guard — untouched, already proven).
    private func testCredentials() throws -> (email: String, password: String) {
        guard
            let email = ProcessInfo.processInfo.environment["STASH_TEST_EMAIL"],
            let password = ProcessInfo.processInfo.environment["STASH_TEST_PASSWORD"],
            !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        return (email, password)
    }

    /// Happy-path sign-in, reused by tests that don't need the wrong-password detour.
    ///
    /// Plan 16: lands on its tab by launch argument (`--uitest-tab-view`, or `landingTab`) — never
    /// a tab-bar tap, which iOS 26 swallows while the sign-in keyboard is still going away — taps
    /// each field until it has focus, and declines iOS 26's "Save Password?" sheet with the
    /// canonical `A11yScreens.dismissSavePasswordPrompt` (exactly "Not Now", never "Save"), which
    /// otherwise takes the test's next tap.
    @discardableResult
    private func signInAndReachLibrary(_ app: XCUIApplication, email: String, password: String,
                                       landingTab: String = "--uitest-tab-view") -> Bool {
        MainActor.assumeIsolated {
            app.launchArguments = ["--uitest-reset-auth", landingTab]
            app.launch()
            let emailField = app.textFields["signin.email"]
            guard emailField.waitForExistence(timeout: 10) else { return false }
            A11yScreens.tapUntilFocused(emailField)
            emailField.typeText(email)
            let passwordField = app.secureTextFields["signin.password"]
            A11yScreens.tapUntilFocused(passwordField)
            passwordField.typeText(password)
            app.buttons["signin.submit"].tap()
            let reached = app.tabBars.buttons["View"].waitForExistence(timeout: 15)
            if reached { A11yScreens.dismissSavePasswordPrompt(app) }
            return reached
        }
    }

    // MARK: - Library search + card helpers (plan 15, Task 3)
    //
    // The View tab's search asks the server (`search-items`, web parity) after a 300 ms debounce
    // and shows the instant local filter until it answers; server results are relevance-ranked
    // (literal title/content matches first) and reach pages the phone hasn't loaded. So a fixture
    // is found by its TITLE once the search has settled — never by grid position, and never via a
    // shared child identifier like `card.typeChip`, which now matches one chip per result card.

    /// Waits until the search pill (`library.search.pill`) stops reporting "searching" — i.e. the
    /// grid shows the server's answer (or the local fallback, if the server failed).
    @discardableResult
    private func waitForLibrarySearchToSettle(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let pill = app.descendants(matching: .any)["library.search.pill"]
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "searching"), object: pill)
        return XCTWaiter().wait(for: [settled], timeout: timeout) == .completed
    }

    /// The grid card (`card.<n>`) whose accessibility label contains `title`.
    private func libraryCard(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#, title))
            .firstMatch
    }

    /// Types `query` into the library search, waits for it to settle, and returns the card for
    /// `title` (asserting it's there).
    @discardableResult
    private func searchLibrary(_ app: XCUIApplication, for query: String, cardTitled title: String) -> XCUIElement {
        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        MainActor.assumeIsolated { A11yScreens.tapUntilFocused(searchField) }
        searchField.typeText(query)
        XCTAssertTrue(waitForLibrarySearchToSettle(app), "Search for '\(query)' never settled")
        let card = libraryCard(app, titled: title)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Expected a card titled '\(title)' for search '\(query)'")
        return card
    }

    /// Clears the search with the pill's own clear button (atomic: query → "" and keyboard down)
    /// and waits for the unfiltered grid.
    private func clearLibrarySearch(_ app: XCUIApplication) {
        let searchField = app.textFields["library.search"]
        MainActor.assumeIsolated { A11yScreens.tapUntilFocused(searchField) }
        let clear = app.buttons["library.search.clear"]
        if clear.waitForExistence(timeout: 5) { clear.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["card.0"].waitForExistence(timeout: 15),
                      "Expected the grid back after clearing the search")
    }

    // MARK: - Fixture self-repair (Task 8 hardening)
    //
    // testEditSmoke's fixture-corruption failure mode has hit TWICE: a crashed run dying
    // between its in-app edit and its own end-of-test restore (further down in this file) left
    // "UITEST-FIXTURE: note one" with a mutated TITLE ("... (edited <epoch>)") and a stale
    // appended notes paragraph (see the Task 5 escalation and task-6-report.md's "discovered +
    // repaired in passing" note — both in .superpowers/sdd/2026-08-11-ios-plan-3-parity/). The
    // structural fix is to restore-FIRST, not just restore-after: every run REST-repairs the
    // fixture to canonical before touching it, so a run is self-healing regardless of what a
    // previous run crashed and left behind. These helpers back that pre-flight (used by
    // testEditSmoke below).

    /// Same Supabase project URL + public anon key `StashConfig.swift` (StashKit) ships — not a
    /// secret, it ships in the committed web client too (see that file's own comment).
    /// Duplicated here rather than imported: `StashUITests` has no package dependency on
    /// StashKit per `project.yml` (a UI-test bundle only depends on the `Stash` app target and
    /// drives it purely through the accessibility tree in a separate process — it cannot
    /// `import` the host app's own module or its package dependencies).
    private static let fixtureRepairBaseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    private static let fixtureRepairAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    private struct FixtureRepairError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// Password-grant access token for the test account, fetched fresh for this repair alone —
    /// a separate, ephemeral REST session from whatever the app itself is signed into via the
    /// UI. Uses the same `STASH_TEST_EMAIL`/`STASH_TEST_PASSWORD` (TEST_RUNNER_-sourced) every
    /// other test in this file already reads via `testCredentials()`.
    private func fixtureRepairAccessToken(email: String, password: String) async throws -> String {
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/auth/v1/token")
                .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError(
                "test-account auth failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1)) — cannot self-heal fixtures")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String
        else {
            throw FixtureRepairError("test-account auth response missing access_token")
        }
        return token
    }

    /// Restores "UITEST-FIXTURE: note one" to its byte-exact canonical title+content. Matches by
    /// a LIKE prefix (`UITEST-FIXTURE: note one*`), not an exact title match, specifically so
    /// this still finds and repairs the row when a prior crash left the TITLE itself mutated —
    /// an exact-title lookup would silently match nothing in exactly the corruption case this
    /// exists to fix. Verified live (read-only) against production before wiring this in: the
    /// prefix matches "note one" only, never "note two" (see task-8-report.md).
    private func restoreNoteOneFixtureToCanonical(email: String, password: String) async throws {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [URLQueryItem(name: "title", value: "like.UITEST-FIXTURE: note one*")]))
        request.httpMethod = "PATCH"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": "UITEST-FIXTURE: note one",
            "content": "UITEST-FIXTURE: stable note for library smoke — do not delete",
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError("fixture restore PATCH failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !rows.isEmpty else {
            throw FixtureRepairError(
                "fixture restore PATCH matched zero rows — 'UITEST-FIXTURE: note one' appears to be missing entirely")
        }
    }

    /// Puts "UITEST-FIXTURE: note two" back to what `testPublicSmoke` leaves it as — private, no
    /// sticky note — by exact title (that test never edits the title). The note goes back to
    /// `null`, the fixture's own seeded value (the app's un-share writes `""`; both mean no note).
    private func restoreNoteTwoFixtureToPrivate(email: String, password: String) async throws {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [URLQueryItem(name: "title", value: "eq.UITEST-FIXTURE: note two")]))
        request.httpMethod = "PATCH"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["is_public": false, "supplemental_note": NSNull()])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError("note-two restore PATCH failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        // A PATCH that matched nothing still answers 2xx: say so instead of passing silently.
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !rows.isEmpty else {
            throw FixtureRepairError("note-two restore PATCH matched zero rows — 'UITEST-FIXTURE: note two' is missing")
        }
    }

    /// REST fetch of "UITEST-FIXTURE: note one*"'s current `content` — same LIKE-prefix title
    /// match as `restoreNoteOneFixtureToCanonical` above (robust to a still-mutated title from a
    /// prior crash). Used by `testEditSmoke`'s notes step to verify the inline editor's autosave
    /// actually landed server-side, not just in the UI.
    private func fetchNoteOneContent(email: String, password: String) async throws -> String {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [
                    URLQueryItem(name: "title", value: "like.UITEST-FIXTURE: note one*"),
                    URLQueryItem(name: "select", value: "content"),
                ]))
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError(
                "note-one content fetch failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first, let content = row["content"] as? String
        else {
            throw FixtureRepairError("note-one content fetch returned no rows")
        }
        return content
    }

    /// Signs into the real View tab and exercises the grid, type chip, search, and sign-out
    /// against production data. Element types for custom-identifier views (grid/cards) are
    /// looked up type-agnostically since SwiftUI doesn't guarantee a stable XCUIElementType
    /// for arbitrary containers the way it does for Button/TextField.
    func testLibrarySmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()

        func anyElement(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any)[identifier]
        }

        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        // 1. Grid shows at least one real item card.
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected at least one item card in the grid")

        // Screenshot rig (Task 8, same checkpoint technique as testDetailSheets/testAskSmoke):
        // holds here, on the plain unfiltered grid (all fixtures, "All" chip, no search/tag
        // filter applied yet — those come next), so an external `xcrun simctl io <udid>
        // screenshot` can capture the View tab's default state before this test narrows it.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: grid\n".data(using: .utf8)!)
        sleep(3)

        // 2. Search (plan 15: server `search-items` with the instant local filter as fallback).
        // (Type chips and the tag filter are gone — the 2026-08-28 UI pass removed the chip
        // row and hid tags from the View tab entirely, pending product-wide tag deprecation.
        // Search is the custom pill field now, a plain text field, not `.searchable` — so no
        // system "Cancel" button appears and no dismissal dance is needed.)
        //
        // a) A term that lives ONLY in a row's page_body ("florentine" — the Wikipedia article
        //    behind "UITEST-FIXTURE: link two"; no title/description/content/url contains it, so
        //    the local filter alone finds nothing) comes back from the server, ranked first.
        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        let pageBodyHit = searchLibrary(app, for: "florentine", cardTitled: "UITEST-FIXTURE: link two")
        XCTAssertEqual(pageBodyHit.identifier, "card.0", "Expected the page_body match ranked first")
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: search\n".data(using: .utf8)!)
        sleep(3)
        clearLibrarySearch(app)

        // b) A literal title match is ranked first even when the server's own relevance puts a
        //    sibling above it ("note one" → "note two" scores close; the literal match wins).
        let noteOne = searchLibrary(app, for: "note one", cardTitled: "UITEST-FIXTURE: note one")
        XCTAssertEqual(noteOne.identifier, "card.0", "Expected the literal title match ranked first")
        clearLibrarySearch(app)

        // 5. Sign out via the Settings tab (Task 7: relocated from the library toolbar's avatar
        // menu, which no longer exists — `library.menu`/`library.signOut` are gone).
        app.tabBars.buttons["Settings"].tap()
        let signOutButton = app.buttons["settings.signout"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 10), "Sign Out row not found in Settings")
        signOutButton.tap()

        confirmSignOut(app)

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10), "Expected the sign-in screen after signing out")
    }

    /// Taps the sign-out confirmation. Plan 16: on iOS 26 the confirmation dialog's button is in the
    /// tree twice ("Multiple matching elements found" on the 26.5 simulator) — tap the one that
    /// can take the tap.
    private func confirmSignOut(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.buttons.matching(identifier: "settings.signout.confirm")
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), "Sign-out confirmation dialog did not appear",
                      file: file, line: line)
        let confirm = matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
        confirm.tap()
    }

    /// Opens the read-only detail sheet for one permanent UITEST-FIXTURE card of each of
    /// [link, text, image, audio] (found via a unique local-search substring, not grid
    /// position, so ordering changes can't break this), asserting the segmented tab set
    /// matches what `contentTabsConfig(for:)` predicts for that type — and, audio only, that
    /// the Transcript tab shows real, non-empty text (the fixture's Whisper transcript).
    /// After each assertion, prints a checkpoint marker to stderr (unbuffered even when
    /// redirected to a file, unlike stdout) and sleeps briefly so an external
    /// `xcrun simctl io <udid> screenshot` can capture the open sheet mid-test — same
    /// technique as testTagFilterSheetOpens below, one checkpoint per type.
    /// Note: presenting the sheet doesn't resign the presenting view's search-field
    /// keyboard (confirmed empirically — neither a submit-via-return, a tap on an unrelated
    /// button, nor a scroll gesture dismissed it), so it stays visible under the sheet in
    /// every screenshot here — harmless for the (accessibility-tree-based) assertions;
    /// link/text/audio's header and tabs still fit above it, only the image checkpoint's
    /// hero image pushes its header below the fold in the screenshot (task-12-report.md).
    func testDetailSheets() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")

        func openAndCheck(search: String, expectedTabs: [String], forbiddenTabs: [String],
                           checkpoint: String, extra: () -> Void = {}) {
            // Plan 15: the whole card is one tap target (no in-card note/kicker gestures left to
            // dodge — the plan-14 `card.typeChip` workaround is gone), and server search ranks
            // results, so the fixture is found by title and tapped anywhere.
            searchLibrary(app, for: search, cardTitled: "UITEST-FIXTURE: \(search)").tap()

            let done = app.buttons["detail.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for '\(search)'")
            for label in expectedTabs {
                XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5),
                              "Expected '\(label)' tab for '\(search)'")
            }
            for label in forbiddenTabs {
                XCTAssertFalse(app.buttons[label].exists, "Did not expect '\(label)' tab for '\(search)'")
            }
            extra()

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: \(checkpoint)\n".data(using: .utf8)!)
            sleep(5)

            done.tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
            // The card tap dropped search focus (plan 12 Task 3), so `clearLibrarySearch`
            // re-taps the field before using the pill's clear button.
            clearLibrarySearch(app)
        }

        openAndCheck(search: "link one", expectedTabs: ["Summary", "Original Content"],
                     forbiddenTabs: ["Transcript", "Notes"], checkpoint: "link")

        // Plan 7 Task 6: pill tabs only render when a type has more than one
        // (`ItemDetailContent.sectionHead`, web parity — `EditItemContentSection.tsx`'s own
        // `config.tabs.length > 1` gate). Single-"Notes"-tab types (text/image) now show the
        // "NOTES" micro-label with no tab buttons at all, not a lone "Notes" button.
        openAndCheck(search: "note one", expectedTabs: [],
                     forbiddenTabs: ["Summary", "Original Content", "Transcript", "Notes"], checkpoint: "text")

        openAndCheck(search: "image one", expectedTabs: [],
                     forbiddenTabs: ["Summary", "Original Content", "Transcript", "Notes"], checkpoint: "image")

        openAndCheck(search: "audio one", expectedTabs: [],
                     forbiddenTabs: ["Summary", "Original Content", "Notes", "Transcript"], checkpoint: "audio") {
            let transcript = app.descendants(matching: .any)["detail.transcriptText"]
            XCTAssertTrue(transcript.waitForExistence(timeout: 10), "Transcript text container not found")
            XCTAssertFalse(transcript.label.isEmpty, "Expected non-empty transcript text")
            XCTAssertNotEqual(transcript.label, "Transcription in progress…",
                              "Expected a real transcript, not the in-progress placeholder")
        }
    }

    /// Card anatomy (Task 7's object-first rework) exercised against real fixtures for the first
    /// time: the repo/video-link and located-note fixtures Task 9 adds, plus the pre-existing
    /// "document one" fixture for the file-plate assertion. View tab only — no detail-sheet dive.
    /// Task 7 added all five identifiers asserted below (`card.repoplate`/`card.faviconplate`/
    /// `card.hero.tall`/`card.fileplate`/`card.location`) but had no repo/video/located fixtures
    /// to verify them against yet (see task-7-report.md's own disclosed verification gap) — this
    /// test closes that gap, and the repo/video fixtures' mere existence with the correct flavor
    /// E2Es Task 1's server-side link-flavor classification in production one more time (seeded
    /// via a bare `add-url` POST with no explicit `attributes.link.flavor` — the server classified
    /// both correctly; see task-9-report.md for the REST seed/verify transcript).
    func testCardAnatomySmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected at least one card in the grid")

        // Screenshot rig (same checkpoint technique as testLibrarySmoke/testDetailSheets): the
        // plain, unfiltered "All" grid — sorted newest-first, so the three Task 9 fixtures (repo/
        // video/located, all seeded together) sit at or near the top alongside older fixture
        // types, giving one screenshot real card-anatomy variety.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: anatomy-grid\n".data(using: .utf8)!)
        sleep(3)

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")

        /// Finds one fixture's card by title after a search (never grid position — same reasoning
        /// `testDetailSheets` documents; plan 15's server search returns several ranked cards, so
        /// every assertion below is scoped INSIDE the fixture's own card), runs `assert`,
        /// screenshots, then clears the search and waits for the grid to return.
        func isolateAndCheck(search: String, title: String, checkpoint: String, assert: (XCUIElement) -> Void) {
            let card = searchLibrary(app, for: search, cardTitled: title)

            assert(card)

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: anatomy-\(checkpoint)\n".data(using: .utf8)!)
            sleep(2)

            clearLibrarySearch(app)
        }

        // 1. Repo link (Task 9 fixture) → dark repo plate, mono "owner/repo" label.
        isolateAndCheck(search: "repo link", title: "supabase/supabase-swift", checkpoint: "repo") { card in
            let plate = card.descendants(matching: .any)["card.repoplate"]
            XCTAssertTrue(plate.waitForExistence(timeout: 10), "Expected a repo plate for the repo-link fixture")
            XCTAssertTrue(plate.label.contains("supabase/supabase-swift"),
                          "Expected the repo plate's label to contain 'supabase/supabase-swift', got '\(plate.label)'")
        }

        // 2. Located note (Task 9 fixture) → footer location badge, "posted from <label>".
        isolateAndCheck(search: "located note", title: "UITEST-FIXTURE: located note", checkpoint: "location") { card in
            let location = card.descendants(matching: .any)["card.location"]
            XCTAssertTrue(location.waitForExistence(timeout: 10), "Expected a location badge for the located-note fixture")
            XCTAssertTrue(location.label.contains("Saratoga Springs"),
                          "Expected the location badge's label to contain 'Saratoga Springs', got '\(location.label)'")
        }

        // 3. Video link (Task 9 fixture) → EITHER a tall hero (YouTube's og:image survived and
        // decoded) OR a favicon plate (it didn't) — both are correct anatomy outcomes per the
        // brief; a link preview image's survival is an external, non-deterministic fact about the
        // live URL (and this app's own image-decode step), not something the app's own
        // correctness hinges on, so this asserts "one of the two", not a specific one. Whichever
        // branch actually renders is written to stderr and disclosed in the report rather than
        // silently assumed.
        isolateAndCheck(search: "video link", title: "Rick Astley", checkpoint: "video") { card in
            let tallHero = card.descendants(matching: .any)["card.hero.tall"]
            let favicon = card.descendants(matching: .any)["card.faviconplate"]
            let heroExists = tallHero.waitForExistence(timeout: 8)
            // 30s: the faviconplate branch renders only after AsyncImage fetch-FAILS the watch-page HTML — budget must exceed slow-network fetch failure, not just render time.
            let faviconExists = !heroExists && favicon.waitForExistence(timeout: 30)
            XCTAssertTrue(heroExists || faviconExists,
                          "Expected the video-link card to expose either card.hero.tall or card.faviconplate")
            FileHandle.standardError.write(
                "VIDEO_HERO_BRANCH: \(heroExists ? "card.hero.tall" : "card.faviconplate")\n".data(using: .utf8)!)
        }

        // 4. Document (pre-existing "document one" fixture — Task 7's own file-plate case, first
        // asserted on here rather than just visually confirmed) → file plate, "PDF" facts.
        isolateAndCheck(search: "document one", title: "UITEST-FIXTURE: document one", checkpoint: "document") { card in
            let plate = card.descendants(matching: .any)["card.fileplate"]
            XCTAssertTrue(plate.waitForExistence(timeout: 10), "Expected a file plate for the document fixture")
            XCTAssertTrue(plate.label.contains("PDF"),
                          "Expected the file plate's label to contain 'PDF', got '\(plate.label)'")
        }
    }

    /// Opens the tag-filter sheet — independent of item-count data, so it stays meaningful
    /// even when the account has no items. Also the screenshot rig for task-10-report.md's
    /// required tag-filter-sheet capture: sleeps briefly post-presentation so an external
    /// `xcrun simctl io <udid> screenshot` can capture it mid-test.
    // testTagFilterSheetOpens was deleted in the 2026-08-28 UI pass along with the tag filter
    // itself — tags are hidden from the View tab pending product-wide deprecation.

    /// Add is the plan-2 launch tab: the composer is reachable at launch with no tab tap, so
    /// this types a marker note straight in, saves it, and confirms it lands on the View tab
    /// via the same realtime path `testLibrarySmoke` already exercises. The created row is
    /// disposable — deleted via REST in the shell after this test runs, unlike the permanent
    /// UITEST-FIXTURE rows `testDetailSheets`/`testLibrarySmoke` depend on.
    ///
    /// STANDING ADJUDICATED GATE FAILURE (plan-4 wrap onward): the UI-test account's Stripe trial
    /// lapsed 2026-08-16 and remains lapsed (Settings still reads "Expired" as of this plan's own
    /// live checks) — Will's Stripe decision (comp the account / new history-free account / accept
    /// degraded capture-smoke verification) is still pending; see the plan-4 outcome's
    /// "Stripe-lapse blocker" section and its plan-5 handoff. `capture.save` is client-side gated by
    /// `SubscriptionStore.canAddContent`, so this test is EXPECTED TO FAIL on every full-suite run
    /// against this account, exactly like `testLocationPinSmoke` (same Add-tab gate) and
    /// `testAskSmoke` (same underlying gate via `AskView`'s `canUseAI` alias — see that test's own
    /// "Gate-vs-RAG disambiguation" comment). These three are the standing adjudicated-failure set a
    /// full-suite run should reproduce; anything else is a genuine regression.
    ///
    /// Plan-5 Task 8 EXTENDS this adjudication rather than adding a fourth member to it:
    /// `testShareExtensionURLSmoke` reads the SAME underlying subscription gate — mirrored into the
    /// share extension's own cached App Group `UserDefaults` bool by `SubscriptionStore.refresh()`
    /// — but, unlike this test, is written CONDITION-AWARE: it asserts the pre-gate compose-card
    /// flow (URL preview + note field) unconditionally, then branches on whichever gate state is
    /// actually live — closed: Save disabled + REST-verified no item created; open/a post-comp
    /// future: Save succeeds + REST-verified item created, then cleaned up. It is written to PASS
    /// either way, so it never joins this standing-failure set. If Will's Stripe decision ever lifts
    /// the lapse, this test (and `testLocationPinSmoke`/`testAskSmoke`) should be expected to start
    /// passing too — that would be the moment to revisit this comment, not before.
    func testCaptureSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // Add is the launch tab (plan 2) — the editor must appear without tapping any tab.
        let editor = anyElement("capture.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 15),
                      "Expected the capture editor to appear on launch (Add is the launch tab)")
        MainActor.assumeIsolated { A11yScreens.dismissSavePasswordPrompt(app) }

        // Screenshot rig (Task 8, same checkpoint technique as testDetailSheets/testAskSmoke):
        // holds here, on the empty composer immediately after launch/sign-in — before this test
        // types anything into it — so an external `xcrun simctl io <udid> screenshot` can capture
        // the Add tab's launch state (empty, no keyboard raised yet).
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: add\n".data(using: .utf8)!)
        sleep(3)

        let marker = "UITEST-CAPTURE: smoke note \(Int(Date().timeIntervalSince1970))"
        editor.tap()
        editor.typeText(marker)

        app.buttons["capture.save"].tap()

        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 10),
                      "Expected a success toast after saving")

        app.tabBars.buttons["View"].tap()
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found")
        searchField.tap()
        searchField.typeText("UITEST-CAPTURE: smoke note")
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 10),
                      "Expected the newly-captured card to appear via realtime")
    }

    /// Debounced field autosave + notes-append + detail-sheet persistence, exercised against the
    /// permanent "UITEST-FIXTURE: note one" fixture. This test mutates that fixture's title
    /// (restored below via the same in-app editing path it was changed with) and its content
    /// (mutated by the notes-append step, which can only ever ADD a paragraph — there's no
    /// in-app "undo" for that).
    ///
    /// RESTORE-FIRST (Task 8 hardening): before touching anything, this test REST-PATCHes note
    /// one back to its byte-exact canonical title+content via `restoreNoteOneFixtureToCanonical`
    /// (above). This fixture-corruption failure mode — a crashed run dying between the in-app
    /// edit below and this test's own end-of-test restore, leaving the title itself mutated —
    /// has hit TWICE (see the Task 5 escalation and task-6-report.md's "discovered + repaired in
    /// passing" note). Restoring first makes every run self-healing regardless of what a prior
    /// crashed run left behind; the end-of-test restore further down is kept too, as a belt —
    /// the fast/expected path when nothing crashed, not the actual safety net anymore.
    ///
    /// Title edits go through `replaceText` (see its doc comment) rather than trying to position
    /// the caret and append/trim a suffix — two earlier approaches (a coordinate tap near the
    /// field's trailing edge; a long-press for the system edit callout) both empirically landed
    /// the caret mid-string instead of at the end, corrupting the title (see task-8-report.md).
    /// `replaceText` makes no assumption about caret position at all.
    ///
    /// `@MainActor`: XCTest always runs test methods on the main thread/actor in practice (the
    /// synchronous `throws`-only tests elsewhere in this file rely on that same fact implicitly);
    /// this just makes it explicit so the compiler doesn't flag every `XCUIElement` call in this
    /// `async` test as a possible off-main-actor access (each one really is main-actor-isolated
    /// API — `tap()`, `typeText`, `waitForExistence`, etc. — this annotation matches reality
    /// rather than working around a false warning).
    @MainActor
    func testEditSmoke() async throws {
        let (email, password) = try testCredentials()
        try await restoreNoteOneFixtureToCanonical(email: email, password: password)

        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        // Empirically (see task-8-report.md), neither a coordinate tap near the trailing edge
        // nor a long-press-for-callout reliably lands the caret at a known position in this
        // SwiftUI TextField — both were observed inserting mid-string instead. What IS reliable:
        // reading the field's *actual current value* (never assumed) and backspacing exactly
        // that many characters, looping (re-tapping each round, since the field's on-screen
        // width-vs-content ratio — and hence where a plain center tap's caret lands — changes as
        // the string shrinks) until the field reports empty. This makes no assumption about
        // caret position at all; it only assumes backspace deletes characters before the caret,
        // which is universally true. Bounded to 5 rounds so a genuine failure loops rather than
        // hangs; the caller's own post-condition assertion is the real safety net regardless.
        // Plan 16: the title field wraps now (a vertical-axis field — a text view underneath), which
        // a bare `.tap()` doesn't always focus: every tap here taps until the field has focus. And a
        // clear selects all (⌘A, a hardware-keyboard command the simulator takes) before deleting,
        // so where the tap left the caret in a two-line title doesn't matter; the counted deletes
        // after it are the old fallback, harmless on an empty field.
        func clearField(_ field: XCUIElement, placeholder: String) {
            for _ in 0..<5 {
                let current = (field.value as? String) ?? ""
                if current.isEmpty || current == placeholder { return }
                A11yScreens.tapUntilFocused(field)
                field.typeKey("a", modifierFlags: .command)
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
        }

        func replaceText(_ field: XCUIElement, placeholder: String, with newValue: String) {
            clearField(field, placeholder: placeholder)
            A11yScreens.tapUntilFocused(field)
            field.typeText(newValue)
        }

        let searchField = app.textFields["library.search"]
        // Plan 15: found by title after the server search settles (never grid position — a wrong
        // card here would edit another fixture), and opened by a plain whole-card tap.
        searchLibrary(app, for: "note one", cardTitled: "UITEST-FIXTURE: note one").tap()

        let originalTitle = "UITEST-FIXTURE: note one"
        let epoch = Int(Date().timeIntervalSince1970)
        let editedTitle = "\(originalTitle) (edited \(epoch))"

        let titleField = anyElement("detail.title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        replaceText(titleField, placeholder: "Untitled", with: editedTitle)
        XCTAssertEqual(titleField.value as? String, editedTitle,
                       "Expected the title field to show the edit immediately")

        // Debounce is 400ms; give the save round trip margin, then hold for the external
        // screenshot rig (same checkpoint technique as testDetailSheets/testTagFilterSheetOpens).
        sleep(2)
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: edit\n".data(using: .utf8)!)
        sleep(5)

        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")

        // Reopen — searching the ORIGINAL substring still matches since the edit only appended.
        let editedCard = libraryCard(app, titled: editedTitle)
        XCTAssertTrue(editedCard.waitForExistence(timeout: 15), "Expected the edited card to still be findable")
        editedCard.tap()

        let reopenedTitleField = anyElement("detail.title")
        XCTAssertTrue(reopenedTitleField.waitForExistence(timeout: 10), "Title field not found on reopen")
        XCTAssertEqual(reopenedTitleField.value as? String, editedTitle,
                       "Expected the edited title to have persisted across dismiss/reopen")

        // Notes autosave (Plan 8 Task 5: inline editor replaces the old append composer).
        // "note one"'s fixture content is plain text (not TipTap JSON), so the editor shows it in
        // full, directly editable. `app.textViews[...]` (not the file's usual `anyElement` helper)
        // — same reasoning `capture.dismissKeyboard` documents above: this view's own
        // `.toolbar(placement: .keyboard)` accessory renders an extra non-interactive "other"
        // container that inherits the same identifier, so `descendants(matching: .any)` can match
        // that instead of the real, focusable `UITextView`.
        //
        // Typing directly after `.tap()` reliably SPLIT the marker across two positions when
        // typed straight into this non-empty multi-line `TextEditor` — confirmed live, and
        // independent of every one of this view's own modifiers (reproduced with autosave,
        // `.focused`, and the keyboard toolbar each individually disabled in turn): the first
        // couple characters landed at the tap point, then the rest jumped to the very end, as if
        // the field's selection settled mid-type. A short throwaway keystroke right after the tap,
        // followed by a brief pause, reliably absorbs whatever that settle is before the real
        // marker types — same shape as `clearField`'s own multi-round tap warm-up above (which
        // masked the same underlying issue without ever actually managing to delete anything).
        // Since this test only needs the marker to land SOMEWHERE in the saved content (the REST
        // check below), not at a specific position, an extra throwaway character ahead of it is
        // harmless.
        let noteMarker = "appended-\(epoch)"
        let notesField = app.textViews["detail.notes.editor"]
        XCTAssertTrue(notesField.waitForExistence(timeout: 10), "Notes editor field not found")
        notesField.tap()
        XCTAssertTrue(app.buttons["detail.dismissKeyboard"].waitForExistence(timeout: 5),
                      "Expected the keyboard-minimize accessory once the notes editor is focused")
        notesField.typeText("x")
        sleep(1)
        notesField.typeText(noteMarker)

        // Debounce is 600ms; give the save round trip margin, then wait for the footer to settle
        // back on its resting caption (same "Changes saved automatically" the title edit above
        // relies on) before REST-verifying the save actually landed server-side.
        sleep(2)
        let autosave = anyElement("detail.autosave")
        let savedCaption = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Changes saved automatically"), object: autosave)
        XCTAssertEqual(XCTWaiter().wait(for: [savedCaption], timeout: 10), .completed,
                       "Expected the autosave footer to settle after the notes edit")

        // Screenshot rig (same checkpoint technique as testDetailSheets/the "edit" checkpoint
        // above): holds here, notes editor populated and autosave settled, for an external
        // `xcrun simctl io <udid> screenshot`.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: notes\n".data(using: .utf8)!)
        sleep(3)

        let savedContent = try await fetchNoteOneContent(email: email, password: password)
        XCTAssertTrue(savedContent.contains(noteMarker),
                      "Expected 'note one's saved content to contain '\(noteMarker)', got '\(savedContent)'")

        // Fix round 1, review finding #1: a note typed then dismissed WITHIN the 600ms debounce
        // window (no wait at all here, unlike the marker above) must still persist — `detail.done`
        // now flushes the pending notes draft before actually dismissing, rather than relying on
        // the debounce alone. Already focused from the step above, so this types straight in.
        let immediateMarker = "immediate-\(epoch)"
        notesField.typeText(immediateMarker)
        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10),
                      "Expected the library after the immediate-dismiss tap (Done should await the flush)")

        let reopenedCard = libraryCard(app, titled: editedTitle)
        XCTAssertTrue(reopenedCard.waitForExistence(timeout: 15),
                      "Expected the card to still be findable after the immediate-dismiss round trip")
        reopenedCard.tap()

        let reopenedNotesField = app.textViews["detail.notes.editor"]
        XCTAssertTrue(reopenedNotesField.waitForExistence(timeout: 10),
                      "Notes editor not found after the immediate-dismiss reopen")
        let reopenedNotesValue = (reopenedNotesField.value as? String) ?? ""
        XCTAssertTrue(reopenedNotesValue.contains(immediateMarker),
                      "Expected the immediately-dismissed note edit to have persisted, got '\(reopenedNotesValue)'")

        let contentAfterImmediateDismiss = try await fetchNoteOneContent(email: email, password: password)
        XCTAssertTrue(contentAfterImmediateDismiss.contains(immediateMarker),
                      "Expected REST content to contain the immediate-dismiss marker '\(immediateMarker)', " +
                      "got '\(contentAfterImmediateDismiss)'")

        // Restore: back to exactly the canonical fixture title. Content stays mutated after this
        // test (the notes step above can only ever grow the note — no in-app undo) — cleaned up
        // either by an explicit REST PATCH in the shell right after this run, or automatically by
        // the NEXT run's own restore-first pre-flight (top of this test) if that shell step is
        // ever skipped, or this run crashes before reaching it.
        replaceText(reopenedTitleField, placeholder: "Untitled", with: originalTitle)
        XCTAssertEqual(reopenedTitleField.value as? String, originalTitle,
                       "Expected the title to be restored to exactly the original fixture title")
        sleep(2)

        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after final dismiss")
    }

    /// Seeds `testDeleteSmoke`'s own disposable item directly via the `add-note` edge function —
    /// same self-contained REST pattern as `seedNoteWithLocationAndLink`/`testLocationPinSmoke`'s
    /// own generated marker, just without the extra attributes this test doesn't need. Never
    /// touches the permanent UITEST-FIXTURE rows.
    private func seedDisposableNote(content: String, email: String, password: String) async throws {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(url: Self.fixtureRepairBaseURL.appending(path: "/functions/v1/add-note"))
        request.httpMethod = "POST"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["content": content, "is_public": false])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError(
                "add-note seed failed for testDeleteSmoke's disposable row (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
    }

    /// Delete flow (plan-12 feedback round 3, Task 1 — Will, on-device: "added a simple note...
    /// then deleted it from the detail sheet, and the item is still showing in the list.
    /// pull-refresh didn't help"). Root cause (see `SupabaseItemPatcher.deleteItemCascade`'s own
    /// doc comment): a PostgREST DELETE that matches zero rows server-side (RLS, or a stale/
    /// mismatched id) still returns an HTTP SUCCESS with an empty representation body — the fix
    /// makes `ItemEditor.delete` actually read that body and throw `.deleteMatchedNoRows` on an
    /// empty result, so a no-op delete now surfaces as a real failure instead of silently
    /// pretending to have worked. This test proves the row is gone THREE ways, mirroring exactly
    /// what Will did and what a client-side-only "fix" (e.g. just removing the row locally on tap)
    /// would NOT actually prove:
    ///   1. right after confirming, the marker search narrows to no results (the local store
    ///      dropped it — matches the original version of this test);
    ///   2. clearing the search back to the full unfiltered grid and pulling to refresh (a genuine
    ///      REST re-fetch, exactly the gesture Will used) does NOT resurrect it — searching the
    ///      marker again still finds nothing;
    ///   3. a direct REST GET confirms the row is actually gone server-side, not merely filtered
    ///      out of this client's own view of it.
    /// Self-seeds its own disposable item via `add-note` (no external pre-seed/env var required —
    /// unlike this test's previous, `STASH_DELETE_MARKER`-gated version) so it never touches the
    /// permanent UITEST-FIXTURE rows and never needs a human in the loop to run.
    @MainActor
    func testDeleteSmoke() async throws {
        let (email, password) = try testCredentials()
        let marker = "UITEST-DELETE: smoke \(Int(Date().timeIntervalSince1970))"
        try await seedDisposableNote(content: marker, email: email, password: password)

        // F5 (whole-branch review): capture the seeded row's own id up front so the teardown
        // below can delete it directly by id if the UI delete path — the very thing this test
        // exercises — doesn't actually land server-side, whether because the assertions below
        // genuinely fail or because something upstream throws first. Before this, a failing run
        // left the disposable row behind permanently: three `UITEST-DELETE: smoke …` rows leaked
        // into production this way and were purged by hand as part of this same fix.
        let seededId: String?
        do {
            let seededRow = try await pollForRow(matchingContent: marker, email: email, password: password, timeout: 15)
            seededId = seededRow["id"] as? String
        } catch {
            seededId = nil
        }

        do {
            let app = XCUIApplication()
            XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                          "Expected the tab bar to appear after sign-in")

            func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
            func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

            let searchField = app.textFields["library.search"]
            // Plan 15: found by its marker once the server search settles; whole-card tap. (The
            // marker is the row's `content`, which the card shows as its note preview.)
            searchLibrary(app, for: marker, cardTitled: marker).tap()

            let deleteButton = app.buttons["detail.delete"]
            XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Delete button not found in detail sheet")
            deleteButton.tap()

            let confirmButton = app.buttons["Delete"]
            XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Delete confirmation dialog did not appear")
            confirmButton.tap()

            // 1. The deleted card is gone from the (still-searched) grid. Server search always
            // returns its nearest neighbours, so "no card for the marker" — not an empty state —
            // is the assertion.
            let deletedCard = libraryCard(app, titled: marker)
            let goneAfterDelete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                            object: deletedCard)
            XCTAssertEqual(XCTWaiter().wait(for: [goneAfterDelete], timeout: 15), .completed,
                           "Expected the deleted item's card to disappear after deletion")

            // 2. Clear the search back to the full unfiltered grid, then pull-to-refresh it: the
            // exact gesture from Will's report, and the one a purely-local "remove it from the
            // array" fix would pass right past — only a genuine server round trip proves the row is
            // really gone. Re-`tap()` the field first: confirming the delete dismissed the sheet
            // AND, per this fix round's "a card tap dismisses the keyboard first" change, dropped
            // the search field's own focus — it's still the frontmost element, just no longer
            // focused, so a bare action on it fails to synthesize without refocusing first. The
            // pill's own clear button (atomic, drops the query to exactly "" in one step) rather
            // than a counted backspace (this fix round's search pill copy/shape is a moving target,
            // but the clear button's identifier and effect are stable regardless).
            searchField.tap()
            app.buttons["library.search.clear"].tap()
            let grid = anyElement("library.grid")
            XCTAssertTrue(grid.waitForExistence(timeout: 15), "Expected the unfiltered grid back once the search clears")
            grid.swipeDown()
            sleep(3)   // let the pulled-to-refresh fetch resolve before searching again

            searchField.tap()
            searchField.typeText(marker)
            XCTAssertTrue(waitForLibrarySearchToSettle(app), "Marker search never settled")
            XCTAssertFalse(libraryCard(app, titled: marker).exists,
                           "Expected the deleted item to STILL be absent after a real pull-to-refresh " +
                           "re-fetch — its reappearance here would mean the delete never actually landed server-side")

            // 3. Server-side proof, independent of anything this client believes: the row itself is
            // gone, not just absent from whatever this one session's store happens to hold.
            let stillExists = try await rowExists(matchingContent: marker, email: email, password: password)
            if stillExists, let seededId {
                // Teardown: the UI delete path under test didn't actually remove the row
                // server-side — clean it up directly by id rather than leaking a permanent
                // `UITEST-DELETE: smoke …` row (see F5's doc comment above).
                try? await deleteRow(id: seededId, email: email, password: password)
            }
            XCTAssertFalse(stillExists, "Expected the deleted item's row to be gone server-side, not just filtered from view")
        } catch {
            if let seededId { try? await deleteRow(id: seededId, email: email, password: password) }
            throw error
        }
    }

    /// Public toggle/sticky-note lifecycle (Task 9), exercised against the permanent
    /// `UITEST-FIXTURE: note two` fixture — a different fixture than testEditSmoke's "note one"
    /// so the two tests' mutations never land on the same row. Leaves the fixture exactly as
    /// found: public/sticky are toggled on then off (`is_public`/`supplemental_note` restored to
    /// false/nil, REST-verified in the shell after this test).
    ///
    /// Plan 7 Task 6 retired the tags manager UI (`DESIGN.md` — "No tag UI on cards or panel");
    /// this test's own tag-add/remove steps (`detail.tags.*`) were removed with it — `tags` data
    /// itself is untouched server-side, just no longer surfaced in this sheet (see
    /// `testDetailSheetAnatomy`'s own assertion that `detail.tags.input` is gone). Renamed from
    /// `testTagsAndPublicSmoke` (final wave, item E) now that no tag steps remain here — the
    /// Settings tab's own `TagsSection` row was removed in the same change.
    func testPublicSmoke() throws {
        let (email, password) = try testCredentials()
        // Plan 16: a run that stops between "public on" and "public off" (seen once — a tap that
        // didn't focus the sticky field) used to leave the permanent fixture PUBLIC. The teardown
        // puts it back as the test leaves it — private, no sticky note — however the test ends,
        // and says so if it can't (2b review N-7: it used to fail silently).
        addTeardownBlock {
            do {
                try await self.restoreNoteTwoFixtureToPrivate(email: email, password: password)
            } catch {
                print("testPublicSmoke: RESTORE FAILED — 'UITEST-FIXTURE: note two' may be left public: \(error)")
                await MainActor.run {
                    XCTContext.runActivity(named: "note-two fixture restore failed: \(error)") { _ in }
                }
            }
        }
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.textFields["library.search"]
        // Plan 15: by title after the server search settles, whole-card tap.
        searchLibrary(app, for: "note two", cardTitled: "UITEST-FIXTURE: note two").tap()

        XCTAssertTrue(anyElement("detail.done").waitForExistence(timeout: 10), "Detail sheet did not present")

        // --- Public toggle ON, sticky note text, toggle OFF (un-share confirm since a sticky
        // note is now present), assert the sticky field disappears once confirmed. ---
        let publicToggle = anyElement("detail.public.toggle")
        XCTAssertTrue(publicToggle.waitForExistence(timeout: 10), "Public toggle not found")
        publicToggle.tap()

        let stickyField = anyElement("detail.public.sticky")
        XCTAssertTrue(stickyField.waitForExistence(timeout: 10), "Sticky note field did not appear after enabling public")
        // Plan 16: the Sharing section's text is bigger, so the field can open right above the
        // sheet's footer — bring it into view, and tap until it has focus (a vertical-axis field
        // is a text view, which a bare tap doesn't always focus).
        MainActor.assumeIsolated {
            A11yScreens.scrollIntoView(app, stickyField)
            A11yScreens.tapUntilFocused(stickyField)
        }
        stickyField.typeText("UITEST-FIXTURE sticky check")

        // Let the sticky note's own debounced autosave land (same 400ms path as title/
        // description) before toggling off, so the un-share confirm's "a note is present" check
        // — and the un-share patch's own read of the note — see the saved value rather than
        // racing the pending debounce (see SharingSection.swift's header doc comment).
        sleep(2)
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: public\n".data(using: .utf8)!)
        sleep(3)

        publicToggle.tap()
        let confirmButton = app.buttons["Make Private"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Un-share confirmation dialog did not appear")
        confirmButton.tap()

        let stickyGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stickyField)
        XCTAssertEqual(XCTWaiter().wait(for: [stickyGone], timeout: 15), .completed,
                       "Expected the sticky note field to disappear after un-sharing")

        sleep(2)   // margin for the un-share PATCH to land before this test's REST verification
        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
    }

    /// Ask tab: streaming Q&A against production — a real answer that shows its source (a chip, or
    /// an inline citation). One real model call per attempt (normally one per test, two on the
    /// RAG-variance retry path; expected and budgeted). See `askAboutPersimmons`. The citation
    /// sheet is `testAskCitationChipOpensTheDetailSheet`'s.
    func testAskSmoke() throws {
        _ = try askAboutPersimmons()
        // Screenshot rig (same checkpoint technique as testDetailSheets/testPublicSmoke): holds
        // here so an external `xcrun simctl io <udid> screenshot` can capture the streamed answer
        // with its source visible.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: ask\n".data(using: .utf8)!)
        sleep(3)
    }

    /// The Ask smoke's citation step, on its own (2b review M-1): a source chip under a live answer
    /// opens that item's detail sheet over Ask, and Done comes back to Ask. Only the sources an
    /// answer DOESN'T cite get chips (Plan 8 Task 4, web parity): a source it cites is an inline
    /// link in its text — the intended rendering — and XCUITest can't tap a link run inside the
    /// answer's `Text` (it sees one static text per block, iOS 17.0 checked). So when the answer
    /// cites its source inline only, this SKIPS, saying so: the untested citation sheet shows in
    /// every run's counts instead of passing silently, as the smoke used to. The deterministic
    /// route — a seeded citation opening a real fixture — belongs to the Ask suite (Task 2d).
    func testAskCitationChipOpensTheDetailSheet() throws {
        let (app, bubbleId) = try askAboutPersimmons()
        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        // The chip of the SAME bubble (its index, not assumed), whichever attempt produced it.
        let indexSuffix = bubbleId.replacingOccurrences(of: "ask.bubble.", with: "")
        let firstChip = anyElement("ask.sources.\(indexSuffix).chip.0")
        guard firstChip.waitForExistence(timeout: 3) else {
            XCTAssertTrue(anyElement("\(bubbleId).hasLinks").exists, "Expected the answer's inline citation marker")
            throw XCTSkip("Citation sheet NOT exercised: the live answer (\(bubbleId)) cites its source inline only, "
                          + "so there's no chip, and XCUITest can't tap a link inside the answer's Text. "
                          + "Covered deterministically by the Ask suite's seeded citation (Task 2d), if present.")
        }
        firstChip.tap()

        let done = app.buttons["detail.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for the tapped source")
        done.tap()
        XCTAssertTrue(anyElement("ask.input").waitForExistence(timeout: 10),
                      "Expected the Ask tab after dismissing the detail sheet")
    }

    /// Signs in straight onto Ask, asks about the permanent document fixture ("persimmons" — its
    /// extracted `page_body` guarantees retrievable content) and waits for a non-empty answer that
    /// shows a source, with a one-shot RAG-variance retry (Task 8 hardening — see its call site).
    /// Returns the app and the answer's `ask.bubble.<N>` identifier.
    ///
    /// Deliberately does NOT assume `ask.bubble.0` is the user question / `ask.bubble.1` is the
    /// assistant reply: chat history is durable (Task 2 persists every exchange to
    /// `conversations`/`messages`), so a second run against the same account restores prior turns
    /// first and appends after them — the indices a run lands on depend on how much history already
    /// exists. Instead this finds whichever `ask.bubble.*`/`ask.sources.*` elements are LAST in the
    /// tree right after sending, which are always the freshly-appended ones.
    private func askAboutPersimmons() throws -> (app: XCUIApplication, bubbleId: String) {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        // Plan 16: straight onto Ask by launch argument (no tab-bar tap — iOS 26 swallows one while
        // the sign-in keyboard is still going away).
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password, landingTab: "--uitest-tab-ask"),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        /// Plan 16: an answer is drawn block by block (`ChatAnswerText`), and every block's `Text`
        /// carries the bubble's `ask.bubble.N` — so the bubble is ALL the elements with that
        /// identifier, read in order (one element, if they are ever combined). Reading `.label` off
        /// `anyElement(id)` fails with "multiple matching elements" once an answer has two blocks.
        func bubbleText(_ identifier: String) -> String {
            // One snapshot, not index-bound elements: a streaming answer's blocks come and go between the
            // count and the read.
            guard let snapshot = try? app.snapshot() else { return "" }
            var labels: [String] = []
            func visit(_ node: XCUIElementSnapshot) {
                if node.identifier == identifier { labels.append(node.label) }
                node.children.forEach(visit)
            }
            visit(snapshot)
            return labels.joined(separator: "\n")
        }

        let input = anyElement("ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")

        // Whichever `ask.bubble.<N>` is currently LAST in the tree right after sending is the
        // freshly-appended assistant reply (appended immediately after the user's own bubble,
        // well before the network stream produces its first token) — see the doc comment above.
        //
        // Needs to match the identifier EXACTLY as "<prefix><digits>", not just BEGINSWITH: an
        // assistant bubble also carries sibling identifiers like "ask.bubble.5.speak",
        // "ask.bubble.5.thumbsUp" for its action row, which themselves begin with the exact same
        // "ask.bubble." prefix — a plain BEGINSWITH query matches those too, and once the action
        // row renders (as soon as any content has streamed in) one of THEM sorts last in the tree,
        // not the bare bubble text. Confirmed live: this silently resolved to "ask.bubble.5.speak"
        // on a real second-suite run, which made the derived "ask.sources.5.speak" lookup fail
        // (never existing) — the assistant's actual reply/sources were fine; only this query was
        // wrong. A first fix attempt used an NSPredicate `MATCHES` (regex) — confirmed live that
        // XCUITest's identifier-query predicate translation doesn't support it (matched nothing at
        // all, "Assistant bubble did not appear"). A second fix attempt used BEGINSWITH (which IS
        // well-supported) filtered to an all-digit suffix in plain Swift, but held onto the
        // resulting `XCUIElement` (from `allElementsBoundByIndex`) and polled `.label` on it
        // directly — that's still an INDEX-bound reference under the hood, and the thread's
        // `LazyVStack` virtualizes bubbles that scroll out of the rendered window as the answer
        // streams in and auto-scroll keeps pace; the match count shifting from under it broke
        // re-resolution mid-poll ("Failed to get matching snapshot: No matches found for Element at
        // index 20"). Fix: resolve the identifier STRING once via this filter, then look the
        // element back up by EXACT identifier for every subsequent read — an identity-based lookup
        // re-resolves correctly regardless of how the surrounding query's result set shifts,
        // exactly like every other identifier lookup in this file already does.
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

        // Types `question` into the composer and sends it (the composer clears its own text on
        // send — `AskView.sendTapped` — so no manual clear is needed between attempts), then
        // waits for the freshly-appended assistant bubble's label to stop changing (stream
        // completion, capped at 30s) and asserts it's non-empty. Returns that bubble's
        // `ask.bubble.<N>` identifier. Factored out so the initial send and the RAG-variance
        // retry below are byte-identical in behavior — the retry is exactly "do this again", not
        // a separate, potentially-diverging code path.
        func askAndAwaitStableReply(_ question: String) -> String {
            MainActor.assumeIsolated { A11yScreens.tapUntilFocused(input) }
            input.typeText(question)

            let sendButton = app.buttons["ask.send"]
            XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Send button not found")
            XCTAssertTrue(sendButton.isEnabled, "Expected Send to be enabled for non-empty input")
            sendButton.tap()

            // Gate-vs-RAG disambiguation (final review, plan-4): on a lapsed-subscription
            // account, `AskView.sendTapped`'s `guard subscription.canUseAI` (AskView.swift:196-199)
            // returns before `ChatStore.send` is ever called — no new bubble is appended, so
            // `lastBubbleIdentifier` below would silently resolve to a stale, already-on-screen
            // RESTORED history bubble instead (`ChatHistoryAPI.loadHistory` never persists/reloads
            // `sources`, so a restored bubble is sourceless by construction) — misreadable as a RAG
            // failure. Fail loudly and specifically instead. See the plan-5 handoff in
            // docs/superpowers/plans/2026-08-17-ios-plan-4-object-parity.md for the full hypothesis
            // and its falsification protocol.
            XCTAssertFalse(anyElement("ask.gateError").waitForExistence(timeout: 2),
                           "Ask send was subscription-gate-blocked — adjudicate as gate, not RAG")

            guard let bubbleId = lastBubbleIdentifier(timeout: 30) else {
                XCTFail("Assistant bubble did not appear")
                return ""
            }

            // Poll for the bubble's text to stabilize (stream completion), capped at 30s total.
            var previousLabel: String?
            var stableStreak = 0
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                let currentLabel = bubbleText(bubbleId)
                let meaningful = currentLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !meaningful.isEmpty, currentLabel == previousLabel {
                    stableStreak += 1
                    if stableStreak >= 3 { break }   // stable across 3 consecutive 0.5s polls (~1.5s quiet)
                } else {
                    stableStreak = 0
                }
                previousLabel = currentLabel
                usleep(500_000)
            }
            let finalLabel = bubbleText(bubbleId).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(finalLabel.isEmpty, "Expected a non-empty assistant answer")
            // Plan 16: what came back, so a sourceless answer can be told from an error reply.
            print("ASK answer \(bubbleId): \(finalLabel.prefix(400).replacingOccurrences(of: "\n", with: " ⏎ "))")
            return bubbleId
        }

        func sourcesRow(forBubble bubbleId: String) -> XCUIElement {
            anyElement("ask.sources.\(bubbleId.replacingOccurrences(of: "ask.bubble.", with: ""))")
        }

        /// Plan 16: an answer's sources reach the user two ways (Plan 8 Task 4, web parity): a
        /// source the answer CITES is an inline link in its text (`[1]` → `#item=<uuid>`, marked by
        /// `ask.bubble.N.hasLinks`), and only the sources it doesn't cite get chips
        /// (`ask.sources.N`). A test that waited for chips alone failed whenever the model cited
        /// its one source inline — which is the good case.
        func sourcesShown(forBubble bubbleId: String, timeout: TimeInterval) -> Bool {
            let chips = sourcesRow(forBubble: bubbleId)
            let inlineLinks = anyElement("\(bubbleId).hasLinks")
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                if chips.exists || inlineLinks.exists { return true }
                usleep(250_000)
            } while Date() < deadline
            return chips.exists || inlineLinks.exists
        }


        let question = "What do my saved items say about persimmons?"
        var bubbleId = askAndAwaitStableReply(question)

        // RAG-variance retry (Task 8 hardening): "a real, non-empty streamed answer but NO source
        // chip" has hit this exact assertion TWICE across T5–T7's full-suite runs (see
        // task-6-report.md / task-7-report.md), always as the sole failure in an otherwise-clean
        // run. Root cause, per those reports' own investigation: the SSE `.done` event genuinely
        // carries an empty `sources` array some fraction of the time — retrieval variance against
        // the same fixture content on the server side, not an XCUITest race (that's a *different*,
        // already-fixed bug, documented above in `lastBubbleIdentifier`'s comment). One in-test
        // retry absorbs that variance without weakening the assertion: if the first attempt's
        // bubble has real text but no source chip within 10s, ask the IDENTICAL question again as
        // a fresh message (a brand-new user+assistant bubble pair, found and awaited exactly like
        // the first) and re-check. This is still a genuine, reportable failure if BOTH attempts
        // come back sourceless — that would mean retrieval against the document fixture is
        // actually broken, not just unlucky once.
        if !sourcesShown(forBubble: bubbleId, timeout: 10) {
            bubbleId = askAndAwaitStableReply(question)
            XCTAssertTrue(
                sourcesShown(forBubble: bubbleId, timeout: 10),
                "Expected the persimmons answer to show a source (a chip, or an inline citation link) — sourceless on both the initial attempt and the RAG-variance retry")
        }
        return (app, bubbleId)
    }

    /// Voice notes (Task 6): record → Stop → Save → success toast → View tab shows the new item.
    /// "Type audio" is proven the same way `testDetailSheets` proves type for its "audio one"
    /// fixture — the segmented tab set (`contentTabsConfig`), not any grid-level type indicator,
    /// since `ItemCardView` exposes no type string directly and this recording has no searchable
    /// text marker (voice notes never attach the composer's typed text as content — see
    /// `CaptureViewModel.submitVoiceNote`'s own doc comment, so unlike `testCaptureSmoke` there's
    /// nothing to type into the search field first). Sim mic permission (`simctl privacy … grant
    /// microphone`) is granted as a pre-step before this test runs, same spirit as testAskSmoke's
    /// grants — with it pre-granted, `AudioRecorderController` never shows a system prompt, so the
    /// sheet's record button is tappable immediately.
    ///
    /// The created row and its uploaded storage object are disposable: REST-polled for its
    /// Whisper-assigned `description` (silence → the "no speech" description path, plan 1) then
    /// REST-deleted in the shell after this test runs — same cleanup-outside-the-test convention
    /// testDeleteSmoke/testCaptureSmoke already use; never touches the permanent UITEST-FIXTURE rows.
    func testVoiceNoteSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // Add is the launch tab (plan 2) — the mic button must appear without tapping any tab.
        let voiceButton = anyElement("capture.voice")
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 15), "Expected the voice-note mic button on the Add tab")
        MainActor.assumeIsolated { A11yScreens.dismissSavePasswordPrompt(app) }
        voiceButton.tap()

        let recordButton = anyElement("capture.voice.record")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10),
                      "Voice recorder sheet did not present its record button")
        recordButton.tap()

        let stopButton = anyElement("capture.voice.stop")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Expected the Stop button once recording starts")

        // Screenshot rig (same checkpoint technique as testDetailSheets/testAskSmoke): holds here,
        // mid-recording, so an external `xcrun simctl io <udid> screenshot` can capture the timer
        // + level meter + Stop/Cancel state before this test moves on.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: voice-recording\n".data(using: .utf8)!)
        sleep(2)   // ~2s of host-mic audio — silent on the simulator, which is fine (brief's own note)
        stopButton.tap()

        let saveButton = anyElement("capture.voice.save")
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Expected the preview state's Save button after Stop")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: voice-preview\n".data(using: .utf8)!)
        sleep(3)
        saveButton.tap()

        // Review fix (task-6 review, Finding 1): Cancel must be disabled the instant Save is
        // tapped, for the whole in-flight upload — a query right after the tap, with no wait, is
        // safe either way: `isEnabled` reads false both while genuinely disabled AND if the sheet
        // has already dismissed (save resolved faster than this line runs), so this can't flake
        // toward a false failure on a fast save.
        XCTAssertFalse(anyElement("capture.voice.cancel").isEnabled,
                       "Expected Cancel to be disabled for the duration of the save")

        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 15),
                      "Expected a success toast after saving the voice note")

        app.tabBars.buttons["View"].tap()
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")

        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the newly-captured voice note's card to appear")
        card0().tap()

        let done = app.buttons["detail.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for the new voice note")
        XCTAssertTrue(app.descendants(matching: .any)["detail.notes.heading"].waitForExistence(timeout: 5), "Expected the standalone Notes section")
        // Single-tab types (audio included) render no pill-tab buttons at all — only the section's
        // static "TRANSCRIPT" `SectionHeader` (`ItemDetailContent`'s `if !tabs.isEmpty { sectionHead
        // }`, plan 14 housekeeping base) — so "a Transcript tab button exists" is no longer a valid
        // signal. `detail.transcriptText` (the transcript body container, only ever rendered for
        // audio/video) is the stable stand-in for the same intent: "this card is type audio".
        XCTAssertTrue(anyElement("detail.transcriptText").waitForExistence(timeout: 5),
                      "Expected the Transcript section — the signal that this card is type audio")
        XCTAssertFalse(app.buttons["Summary"].exists, "Did not expect a Summary tab for an audio item")
        XCTAssertFalse(app.buttons["Original Content"].exists, "Did not expect an Original Content tab for an audio item")

        done.tap()
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 10), "Expected the library after dismiss")
    }

    // MARK: - Location pin (Task 6)
    //
    // Polls `items?content=eq.<marker>` until the row `testLocationPinSmoke` just created via the
    // UI appears (the in-app save + this REST read are two independent paths — same "give it a
    // moment" reasoning as `testCaptureSmoke`'s in-app realtime-search step, just via REST instead
    // of the UI here), returning `id`/`attributes` for that test's own assertions. Reuses
    // `fixtureRepairAccessToken`/`fixtureRepairBaseURL`/`fixtureRepairAnonKey`/`FixtureRepairError`
    // (above) rather than duplicating the auth dance.
    private func pollForRow(matchingContent marker: String, email: String, password: String,
                            timeout: TimeInterval) async throws -> [String: Any] {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [
                    URLQueryItem(name: "content", value: "eq.\(marker)"),
                    URLQueryItem(name: "select", value: "id,attributes"),
                ]))
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let row = rows.first {
                return row
            }
            try? await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        throw FixtureRepairError("timed out waiting for the disposable location row '\(marker)' to appear via REST")
    }

    /// Cleanup for `testLocationPinSmoke`'s disposable row — same REST-verified deletion
    /// `testDeleteSmoke` exercises through the in-app UI, performed here directly since this test
    /// already has the row's `id` in hand from `pollForRow` above and never touches the permanent
    /// UITEST-FIXTURE rows.
    private func deleteRow(id: String, email: String, password: String) async throws {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")]))
        request.httpMethod = "DELETE"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError("cleanup DELETE failed for disposable location row \(id)")
        }
    }

    /// One-shot existence check by `content` (written for the share smoke's gate-CLOSED branch,
    /// which now uses `itemsWithNote` — a URL share's note lives in `supplemental_note`). Unlike
    /// `pollForRow` above (which retries until a row APPEARS — correct for "this save should have
    /// landed eventually"), an expected ABSENCE has nothing to wait for: the correct check is a
    /// single fetch, taken only after the caller has already given the (non-)event a generous
    /// settle window — polling-until-absent could only ever time out, not confirm anything sooner.
    private func rowExists(matchingContent marker: String, email: String, password: String) async throws -> Bool {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [
                    URLQueryItem(name: "content", value: "eq.\(marker)"),
                    URLQueryItem(name: "select", value: "id"),
                ]))
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError(
                "existence check failed for marker '\(marker)' (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return !rows.isEmpty
    }

    /// Opt-in location capture (Task 6): pin toggle → CoreLocation one-shot fix (simulator location
    /// pre-set via `simctl location set`, permission pre-granted via `simctl privacy grant
    /// location` — both shell pre-steps run before this suite, see task-6-report.md) → native
    /// reverse geocode → non-empty preview line → Save → REST-verified `attributes.location` on
    /// the saved row (label, `source == "device-geolocation"`, latitude). The created row is
    /// disposable: REST-polled then REST-DELETEd within this test itself (`pollForRow`/`deleteRow`
    /// above), never touching the permanent UITEST-FIXTURE rows.
    ///
    /// `@MainActor`: same reasoning as `testEditSmoke` — XCTest always runs test methods on the
    /// main thread/actor in practice; this just makes the `XCUIElement` calls in this `async` test
    /// explicit about it rather than leaving the compiler to flag each one as a possible
    /// off-main-actor access.
    @MainActor
    func testLocationPinSmoke() async throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // Add is the launch tab (plan 2) — the pin button must appear without tapping any tab.
        let pinButton = anyElement("capture.pin")
        XCTAssertTrue(pinButton.waitForExistence(timeout: 15), "Expected the location pin button on the Add tab")
        // Already on the main actor (`@MainActor` test): a direct call. (`assumeIsolated` is for
        // the synchronous smokes; from an async context it's a warning, an error in Swift 6.)
        A11yScreens.dismissSavePasswordPrompt(app)
        pinButton.tap()

        // Screenshot rig (same checkpoint technique as testDetailSheets/testAskSmoke): holds
        // briefly right after the tap, while CoreLocation/CLGeocoder are still resolving (the
        // pin button shows a spinner in this state — see `pinIconName`/`.resolving` in
        // CaptureComposerView), before the wait below moves on to the resolved preview.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: pin-resolving\n".data(using: .utf8)!)
        sleep(2)

        let preview = anyElement("capture.pin.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10),
                      "Expected a 'posted from <label>' preview once the pin resolves")
        let previewLabel = preview.label
        XCTAssertTrue(previewLabel.hasPrefix("posted from "),
                      "Expected the pin preview text to read 'posted from <place>', got '\(previewLabel)'")
        let place = previewLabel.dropFirst("posted from ".count).trimmingCharacters(in: .whitespaces)
        XCTAssertFalse(place.isEmpty, "Expected a non-empty resolved location label")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: pin-preview\n".data(using: .utf8)!)
        sleep(3)

        let marker = "UITEST-LOC: pin smoke \(Int(Date().timeIntervalSince1970))"
        let editor = anyElement("capture.editor")
        editor.tap()
        editor.typeText(marker)

        app.buttons["capture.save"].tap()
        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 10),
                      "Expected a success toast after saving")

        let row = try await pollForRow(matchingContent: marker, email: email, password: password, timeout: 20)
        let attributes = row["attributes"] as? [String: Any]
        let location = attributes?["location"] as? [String: Any]
        XCTAssertNotNil(location, "Expected an attributes.location blob on the saved row")
        XCTAssertFalse(((location?["label"] as? String) ?? "").isEmpty, "Expected a non-empty location label")
        XCTAssertEqual(location?["source"] as? String, "device-geolocation")
        XCTAssertNotNil(location?["latitude"], "Expected a latitude on the device-resolved location")

        if let id = row["id"] as? String {
            try await deleteRow(id: id, email: email, password: password)
        }
    }

    // MARK: - Location edit (Task 8)

    /// Seeds `testLocationEditSmoke`'s disposable item directly via the `add-note` edge function
    /// (Task 1: accepts `attributes` in its body, sanitized server-side) — never through the
    /// in-app composer. This sidesteps the plan-wide blocker documented on `testCaptureSmoke`/
    /// `testLocationPinSmoke`/`testVoiceNoteSmoke` (the UI-test account's Stripe trial lapsed
    /// 2026-08-16, gate-blocking in-app capture actions client-side): a raw REST call to an edge
    /// function isn't a capture-UI action, so it isn't affected by that client-side gate either
    /// way, and the edit flow this test actually exercises isn't subscription-gated at all (only
    /// capture/AI actions are). `content` is the caller's own unique marker, matched back via
    /// `pollForRow` the same way `testLocationPinSmoke` polls for its own disposable row.
    private func seedNoteWithLocationAndLink(content: String, email: String, password: String) async throws {
        let token = try await fixtureRepairAccessToken(email: email, password: password)
        var request = URLRequest(url: Self.fixtureRepairBaseURL.appending(path: "/functions/v1/add-note"))
        request.httpMethod = "POST"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "content": content,
            "is_public": false,
            "attributes": [
                "location": [
                    "label": "Seed Location", "latitude": 40.7128, "longitude": -74.0060,
                    "accuracy_m": 12, "city": "Seed Location", "region": "NY", "country": "US",
                    "source": "device-geolocation", "captured_at": "2026-08-01T12:00:00Z",
                ],
                "link": ["flavor": "article"],
            ],
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError(
                "add-note seed failed for disposable location-edit row (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
    }

    /// Edit-sheet location row (Task 8; relocated into the Details drawer in Task 7's Fix round
    /// 1 — this test now taps `detail.details` open first, matching where the row actually lives
    /// today): a DISPOSABLE item seeded directly via the `add-note` edge function
    /// (`seedNoteWithLocationAndLink` above) with a device-geolocation location blob AND a `link`
    /// attribute, so this test can prove the row's read-modify-write survives a sibling key it
    /// doesn't touch. Opens the row (asserts the seeded device location renders), edits it to
    /// "Test City" (asserts `source: "manual"`, coordinates dropped, `link` still present via
    /// REST), clears it via the row's own remove button (asserts the `location` key is gone
    /// entirely while `link` still survives), then deletes the disposable row — same REST
    /// seed/poll/delete shape `testLocationPinSmoke` already established.
    ///
    /// Edit flows are NOT subscription-gated (plan-wide note: only capture/AI actions are) — this
    /// smoke is expected to fully pass despite the UI-test account's lapsed Stripe trial, unlike
    /// `testCaptureSmoke`/`testLocationPinSmoke`/`testVoiceNoteSmoke`.
    ///
    /// `@MainActor`: same reasoning as `testEditSmoke`/`testLocationPinSmoke` — makes the
    /// `XCUIElement` calls in this `async` test's main-actor isolation explicit.
    @MainActor
    func testLocationEditSmoke() async throws {
        let (email, password) = try testCredentials()
        let marker = "UITEST-LOC: edit smoke \(Int(Date().timeIntervalSince1970))"
        try await seedNoteWithLocationAndLink(content: marker, email: email, password: password)

        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        // Plan 15: by marker (the card's note preview) after the server search settles, whole-card tap.
        searchLibrary(app, for: marker, cardTitled: marker).tap()

        XCTAssertTrue(anyElement("detail.done").waitForExistence(timeout: 10), "Detail sheet did not present")

        // Fix round 1 (review finding #1): the location editor now lives inside the Details
        // drawer (collapsed by default, matching the web's own `EditItemDetailsDrawer` — see
        // `DetailsDrawer.swift`'s doc comment) rather than always-visible near the top of the
        // sheet, so it must be expanded first.
        let detailsRow = anyElement("detail.details")
        XCTAssertTrue(detailsRow.waitForExistence(timeout: 10), "Details drawer row not found")
        detailsRow.tap()

        let locationLabel = anyElement("detail.location.label")
        XCTAssertTrue(locationLabel.waitForExistence(timeout: 10), "Expected the row to show the seeded device location")
        XCTAssertEqual(locationLabel.label, "posted from Seed Location")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: location-display\n".data(using: .utf8)!)
        sleep(3)

        locationLabel.tap()
        let field = anyElement("detail.location.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Expected the location field to appear for editing")
        XCTAssertEqual(field.value as? String, "Seed Location", "Expected the field to prefill with the current label")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: location-editing\n".data(using: .utf8)!)
        sleep(3)

        // Same reliable length-based clear `testEditSmoke`'s `clearField` uses (never assumes
        // caret position — see that helper's own doc comment for why).
        let prefilled = (field.value as? String) ?? ""
        field.tap()
        if !prefilled.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prefilled.count))
        }
        field.typeText("Test City\n")

        let editedLabel = anyElement("detail.location.label")
        XCTAssertTrue(editedLabel.waitForExistence(timeout: 10), "Expected the row to show the edited label")
        XCTAssertEqual(editedLabel.label, "posted from Test City")

        sleep(2)   // margin for the commit's (un-debounced but still async) PATCH to land
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: location-edited\n".data(using: .utf8)!)
        sleep(3)

        let afterEdit = try await pollForRow(matchingContent: marker, email: email, password: password, timeout: 20)
        let afterEditAttributes = afterEdit["attributes"] as? [String: Any]
        let afterEditLocation = afterEditAttributes?["location"] as? [String: Any]
        XCTAssertEqual(afterEditLocation?["label"] as? String, "Test City")
        XCTAssertEqual(afterEditLocation?["source"] as? String, "manual")
        XCTAssertNil(afterEditLocation?["latitude"], "Expected coordinates to be dropped on a manual edit")
        XCTAssertEqual((afterEditAttributes?["link"] as? [String: Any])?["flavor"] as? String, "article",
                       "Expected the seeded link attribute to survive the location edit")

        // Clear via the row's own remove button — no need to re-enter edit mode.
        let removeButton = anyElement("detail.location.remove")
        XCTAssertTrue(removeButton.waitForExistence(timeout: 10), "Expected a remove button on the populated row")
        removeButton.tap()

        let addButton = anyElement("detail.location.add")
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Expected the ghost 'Add a location' button after clearing")

        sleep(2)
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: location-cleared\n".data(using: .utf8)!)
        sleep(3)

        let afterClear = try await pollForRow(matchingContent: marker, email: email, password: password, timeout: 20)
        let afterClearAttributes = afterClear["attributes"] as? [String: Any]
        XCTAssertNil(afterClearAttributes?["location"], "Expected the location key to be fully removed after clearing")
        XCTAssertEqual((afterClearAttributes?["link"] as? [String: Any])?["flavor"] as? String, "article",
                       "Expected the link attribute to still survive after clearing location")

        app.buttons["detail.done"].tap()

        if let id = afterClear["id"] as? String {
            try await deleteRow(id: id, email: email, password: password)
        }
    }

    // MARK: - Share extension (Task 8, plan 5)

    /// Share-extension smoke: drives Safari's REAL system share sheet end-to-end into the live
    /// `StashShareExtension` process — the GOLD automation recipe this reuses verbatim from T5/T7's
    /// own live checks (see task-5-report.md/task-7-report.md): `XCUIApplication(bundleIdentifier:
    /// "com.apple.mobilesafari")` driving Safari's own `ShareButton`, with Stash appearing directly
    /// in the share sheet's FIRST ROW (no "More" step needed on this iOS/Simulator version) — no
    /// springboard-bundle-id workaround required.
    ///
    /// Two NEW automation findings this task adds to T7's own leaf-identifier note (extension-
    /// hosting accessibility quirks — see `ShareComposeView.swift`'s own `doneView`/`gateMessage`
    /// doc comments for the original one):
    /// 1. The compose card's BUTTONS (`share.cancel`/`share.save`) resolve as an ambiguous
    ///    container+child pair through Safari's proxy — a wrapping `Other` element inherits the
    ///    SAME identifier as the real `Button` beneath it — under a type-erased
    ///    `.descendants(matching: .any)` query ("Multiple matching elements found", confirmed live).
    ///    A TYPED query (`app.buttons["…"]`) resolves unambiguously, since only the actual Button
    ///    matches that element type. `share.gate`/`share.preview.url` (leaf `Text`s) don't hit this
    ///    — `.staticTexts["…"]` resolves to a single clean match, matching T7's own verified leaf-
    ///    identifier approach.
    /// 2. The note field (`TextField(..., axis: .vertical)`) surfaces to accessibility as a
    ///    `TextView`, not a `TextField` — `app.textViews["share.note"]`, not `app.textFields[...]`.
    ///
    /// CONDITION-AWARE, same adjudication shape as `testCaptureSmoke`/`testLocationPinSmoke` (see
    /// `testCaptureSmoke`'s own doc comment for the standing gate context this extends): the
    /// UI-test account's lapsed Stripe trial means the extension's cached gate (App Group
    /// `UserDefaults`, written by `SubscriptionStore.refresh()`) currently reads `false`. This smoke
    /// asserts the PRE-GATE flow (compose card renders, URL preview + note field both present)
    /// UNCONDITIONALLY either way, then branches on the live gate state: gate visible -> Save
    /// disabled, Cancel, REST-verify NO item was created; gate absent (fail-open / a post-comp
    /// future) -> Save, REST-verify the item WAS created, clean it up. Unlike the three standing-
    /// adjudicated smokes, this test is written to PASS regardless of which branch fires — it never
    /// joins that failure set.
    ///
    /// Dwells on Settings right after sign-in (reading the real subscription status line, same
    /// technique `testSettingsSmoke` uses) BEFORE ever switching over to Safari:
    /// `SubscriptionStore.refresh()` needs a moment to actually resolve and write the gate cache —
    /// observed live that skipping this dwell reads the cache as MISSING (fail-open) regardless of
    /// the true account state, a timing artifact of this test's own launch sequence, not a genuine
    /// "gate removed" signal (see task-8-report.md).
    ///
    /// Loads example.com by typing into Safari's OWN address bar — never `xcrun simctl openurl`,
    /// which can only run as an external shell step BETWEEN separate `xcodebuild test` invocations
    /// (T5/T7's own scratch-probe discovery methodology); this is one self-contained test. Safari's
    /// address bar identifier changes from "TabBarItemTitle" (idle) to "URL" (once tapped/editing) —
    /// a stale reference to the pre-tap identifier fails to re-resolve; this re-queries the NEW
    /// identifier instead of reusing the original one.
    ///
    /// A unique marker is typed into the note field regardless of which branch fires — this ties
    /// "REST-verify no item was created" to something concrete and falsifiable (an actual `content`
    /// value that WOULD exist if a bug ever let a gate-disabled Save slip through) rather than a
    /// coarser, fixture-collision-prone check against the shared, non-unique `example.com` URL.
    ///
    /// `@MainActor`: same reasoning as `testEditSmoke`/`testLocationPinSmoke` — makes the
    /// `XCUIElement` calls in this `async` test's main-actor isolation explicit.
    @MainActor
    func testShareExtensionURLSmoke() async throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        // The confirmation is held 3 s (DEBUG) so XCUITest, which looks only once Safari idles
        // after the tap, reliably sees it; the latency itself is the extension's own measurement.
        launchSignedIn(app, arguments: ["--uitest-share-confirmation-hold=3000"], email: email, password: password)

        // Let SubscriptionStore.refresh() resolve + write the gate cache before switching to
        // Safari — see doc comment above. Best effort: both gate branches below are valid
        // outcomes, and on iOS 26 a tab button's identifier is its symbol name, so it's found by
        // its label.
        let settingsTab = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        if settingsTab.waitForExistence(timeout: 5) { settingsTab.tap() }
        _ = app.descendants(matching: .any)["settings.subscription.status"].waitForExistence(timeout: 15)
        sleep(3)

        // --- Unconditional pre-gate flow: the compose card renders with the URL preview + note
        // field, regardless of gate state (plan 15: the shared helper also copes with iOS 26
        // Safari — Share inside the ••• menu, the note field surfacing as a TextField). ---
        let marker = "UITEST-P15-T4: smoke \(Int(Date().timeIntervalSince1970))"
        // Whatever branch runs, nothing this test creates may outlive it.
        addTeardownBlock {
            for row in (try? await self.itemsWithNote(marker, email: email, password: password)) ?? [] {
                if let id = row["id"] as? String { try? await self.deleteSharedItem(id: id, email: email, password: password) }
            }
        }
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let saveButton = openStashComposeCard(in: safari, url: "example.com", note: marker, checkpoint: "share-compose")
        let urlPreview = safari.staticTexts["share.preview.url"]
        XCTAssertTrue(urlPreview.label.contains("example.com"),
                      "Expected the URL preview to reference example.com, got '\(urlPreview.label)'")

        // Plan 7 Task 2: the extension-side font proof — an appex has its own bundle (separate
        // from the host app's), so this is the only way to confirm PP Neue Montreal actually
        // registered INSIDE the running share-extension process, not just the app's.
        let fontStatus = safari.descendants(matching: .any)["share.fontStatus"]
        XCTAssertTrue(fontStatus.waitForExistence(timeout: 5), "share.fontStatus label not found in the compose card")
        XCTAssertEqual(fontStatus.label, "font:neue-montreal",
                       "Expected PP Neue Montreal to load in the share-extension target, not fall back to SF Pro")

        if safari.staticTexts["share.gate"].waitForExistence(timeout: 3) {
            // --- Gate visible (this account's current lapsed-trial state): Save disabled, no item
            // created. ---
            XCTAssertFalse(saveButton.isEnabled, "Expected Save to be disabled while the gate is showing")

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: share-gate-closed\n".data(using: .utf8)!)
            sleep(3)

            safari.buttons["share.cancel"].tap()
            XCTAssertTrue(waitForShareCardGone(in: safari, timeout: 15), "Expected to return to Safari after Cancel")

            // Generous settle window before the REST check — this is an ABSENCE assertion, so
            // there's nothing to poll-until; a fixed wait then a single check is the correct shape
            // (see `rowExists`'s own doc comment). Both note columns: a URL share's note is
            // stored in `supplemental_note`.
            sleep(5)
            let rows = try await itemsWithNote(marker, email: email, password: password)
            XCTAssertTrue(rows.isEmpty, "Expected NO item to be created while the share-extension gate was showing")
        } else {
            // --- Gate absent (fail-open / a post-comp future): Save → instant confirmation → the
            // upload finishes in the background → exactly one item. ---
            XCTAssertTrue(saveButton.isEnabled, "Expected Save to be enabled while the gate is absent")
            let confirmation = tapSaveAndTimeConfirmation(saveButton, in: safari)
            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: share-gate-open-saving\n".data(using: .utf8)!)
            // Plan 15: the confirmation no longer waits on the network.
            XCTAssertNotNil(confirmation, "Expected the 'Saved to Stash' confirmation right after Save")
            if let confirmation {
                XCTAssertEqual(confirmation.text, "Saved to Stash")
                XCTAssertLessThanOrEqual(confirmation.measuredMs ?? .max, Self.instantConfirmationBudgetMs,
                                         "Save → confirmation took \(confirmation.measuredMs.map { "\($0) ms" } ?? "an unknown time")")
            }
            XCTAssertTrue(waitForShareCardGone(in: safari, timeout: 15), "Expected the sheet to dismiss itself after the confirmation")

            let rows = try await waitForItemsWithNote(marker, email: email, password: password, timeout: 20)
            XCTAssertEqual(rows.count, 1, "Expected the shared URL to land exactly once")
        }
    }

    /// The extension's own Save → "Saved to Stash" measurement must stay within this (final wave,
    /// T4 review carry: measured 26–76 ms on the simulators, so 500 ms still leaves room for a
    /// loaded CI machine while catching any network round trip creeping back in).
    static let instantConfirmationBudgetMs = 500

    /// Plan 15 Task 4 (Will: "the user should click the save button, see a confirmation, and then
    /// the stash should happen in the background seamlessly"): Save shows "Saved to Stash" within
    /// `instantConfirmationBudgetMs` — no network round trip in between — and the sheet dismisses
    /// itself right after, yet the share lands server-side exactly once: the background session
    /// finishes the upload without the extension. The lapsed test account's CLIENT gate is opened
    /// for this run (`--uitest-share-gate-open`, DEBUG). GATE-BLOCKED on that account since the
    /// 2026-09-29 production redeploy: the server now answers every lapsed capture — URL ones
    /// included — 403 `subscription_required`, so the confirmation half passes and the "lands
    /// exactly once" assertion fails (the share parks in the Outbox) until the account is comped.
    /// The latency asserted is the extension's own Save → confirmation measurement: XCUITest only
    /// looks once Safari idles after the tap (0.4–1.4 s observed), so the confirmation is held 3 s
    /// here (`--uitest-share-confirmation-hold`, DEBUG) for it to be seen at all.
    @MainActor
    func testShareSaveConfirmsInstantlyAndLandsOnceInTheBackground() async throws {
        let (email, password) = try testCredentials()
        let epoch = Int(Date().timeIntervalSince1970)
        let marker = "UITEST-P15-T4: instant \(epoch)"
        addTeardownBlock {
            for row in (try? await self.itemsWithNote(marker, email: email, password: password)) ?? [] {
                if let id = row["id"] as? String { try? await self.deleteSharedItem(id: id, email: email, password: password) }
            }
        }
        let app = XCUIApplication()
        launchSignedIn(app, arguments: ["--uitest-share-gate-open", "--uitest-share-confirmation-hold=3000"],
                       email: email, password: password)

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let saveButton = openStashComposeCard(in: safari, url: "example.com/?p15t4=instant-\(epoch)", note: marker,
                                              checkpoint: "p15t4-compose")
        XCTAssertTrue(saveButton.isEnabled, "Expected Save to be enabled (gate opened for this test)")
        let confirmation = tapSaveAndTimeConfirmation(saveButton, in: safari, screenshot: "p15t4-confirmation")
        XCTAssertNotNil(confirmation, "Expected the 'Saved to Stash' confirmation right after Save")
        if let confirmation {
            XCTAssertEqual(confirmation.text, "Saved to Stash")
            XCTAssertNotNil(confirmation.measuredMs, "Expected the extension's own latency on the confirmation (DEBUG)")
            XCTAssertLessThanOrEqual(confirmation.measuredMs ?? .max, Self.instantConfirmationBudgetMs,
                                     "Save → confirmation took \(confirmation.measuredMs.map { "\($0) ms" } ?? "an unknown time")")
            print("P15T4-TIMING: save→confirmation \(confirmation.measuredMs.map { "\($0) ms" } ?? "?") in the extension; seen by XCUITest after \(String(format: "%.2f", confirmation.seconds)) s")
        }
        XCTAssertTrue(waitForShareCardGone(in: safari, timeout: 10),
                      "Expected the sheet to dismiss itself once the confirmation has been shown")

        let rows = try await waitForItemsWithNote(marker, email: email, password: password, timeout: 20)
        XCTAssertEqual(rows.count, 1, "Expected the share to land server-side exactly once")
        XCTAssertEqual(rows.first?["type"] as? String, "link")
        // No late second copy from a retry.
        try await Task.sleep(for: .seconds(4))
        let settled = try await itemsWithNote(marker, email: email, password: password)
        XCTAssertEqual(settled.count, 1, "Expected still exactly one item")
    }

    /// Plan 15 Task 4: neither the app nor the share extension is running when the upload
    /// answers. The app is terminated before the share, and the extension exits 150 ms after
    /// handing the share to the background session (`--uitest-share-exit-after-handoff=150`,
    /// DEBUG) — before the server can answer — so the upload can only be carried by the system's
    /// transfer daemon (which then launches the app in the background to deliver the result).
    /// The item must land before the app is opened again. Relaunching with a 1 s stale-transfer
    /// interval then makes the launch drain resend anything still marked in flight — which must
    /// still leave exactly one item (the capture id is the idempotency key) and nothing queued.
    /// GATE-BLOCKED on the lapsed test account since the 2026-09-29 production redeploy (the server
    /// answers its URL captures 403 `subscription_required`): the "landed" wait fails and the
    /// share sits parked in the Outbox, until the account is comped.
    ///
    /// No note is typed: the unique shared URL is the marker. (Harness-only observation: after
    /// XCUITest has typed into the app's sign-in form and then killed the app, the share card's
    /// text view doesn't take keyboard focus, while Safari's own fields do. With the app running,
    /// terminated, or relaunched otherwise, the card focuses normally — see task-4-report.md.)
    @MainActor
    func testShareSaveWithTheAppTerminatedLandsOnceAndLeavesNothingQueued() async throws {
        let (email, password) = try testCredentials()
        let marker = "p15t4-terminated-\(Int(Date().timeIntervalSince1970))"
        addTeardownBlock {
            for row in (try? await self.itemsWithURL(containing: marker, email: email, password: password)) ?? [] {
                if let id = row["id"] as? String { try? await self.deleteSharedItem(id: id, email: email, password: password) }
            }
        }
        let app = XCUIApplication()
        launchSignedIn(app, arguments: ["--uitest-share-gate-open", "--uitest-share-exit-after-handoff=150"],
                       email: email, password: password)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let saveButton = openStashComposeCard(in: safari, url: "example.com/?q=\(marker)", note: nil)
        XCTAssertTrue(saveButton.isEnabled, "Expected Save to be enabled (gate opened for this test)")
        saveButton.tap()
        XCTAssertTrue(waitForShareCardGone(in: safari, timeout: 10),
                      "Expected the share sheet to be gone right after Save")

        // Landed with neither process running: carried by the background session.
        let landed = try await waitForItemsWithURL(containing: marker, email: email, password: password, timeout: 45)
        XCTAssertEqual(landed.count, 1, "Expected the share to land exactly once with the app and the extension gone")

        // The transfer daemon now wakes the app in the background to hand it the result. A
        // relaunch that lands in the same instant as that wake can bring up the system-launched
        // process, which has none of this test's arguments — so let the wake settle first, and
        // relaunch once more if the probe still doesn't show.
        let woke = app.wait(for: .runningBackgroundSuspended, timeout: 10)
        print("P15T4-WAKE: app woken in the background for the result: \(woke) (state \(app.state.rawValue))")

        // Relaunch (stored session, no sign-in) with a 1 s stale-transfer interval: the launch
        // drain resends whatever is still marked in flight — never a second item.
        app.launchArguments = ["--uitest-stale-transfer-seconds=1", "--uitest-outbox-probe"]
        app.launch()
        let probe = app.descendants(matching: .any)["debug.outbox"]
        if !probe.waitForExistence(timeout: 10) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(probe.waitForExistence(timeout: 20), "Expected the Outbox probe after relaunch")
        let drained = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH 'count=' AND NOT (label CONTAINS %@)", marker), object: probe)
        XCTAssertEqual(XCTWaiter().wait(for: [drained], timeout: 30), .completed,
                       "Expected nothing left queued for this share, got '\(probe.label)'")
        try await Task.sleep(for: .seconds(4))
        XCTAssertFalse(probe.label.contains(marker), "Expected the Outbox to stay clear of this share")
        let settled = try await itemsWithURL(containing: marker, email: email, password: password)
        XCTAssertEqual(settled.count, 1, "Expected still exactly one item after the relaunch's drain")
    }

    /// Conversations navigation (2026-08-29 sessions model): the Ask header's history button
    /// pushes the Conversations list — UNGATED, unlike sending (listing is a plain RPC read, no
    /// subscription check), so this passes on the lapsed test account. The account's row count
    /// depends on what earlier (pre-gate-lapse) runs persisted, so a populated list and the
    /// empty state are BOTH acceptable outcomes; only the navigation shell (search pill, back
    /// to the thread) is asserted unconditionally.
    func testConversationsSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")
        func anyElement(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any)[identifier]
        }

        app.tabBars.buttons["Ask"].tap()
        XCTAssertTrue(app.buttons["ask.newChat"].waitForExistence(timeout: 10), "New-chat button missing")
        let historyButton = app.buttons["ask.history"]
        XCTAssertTrue(historyButton.exists, "History button missing")
        historyButton.tap()

        XCTAssertTrue(app.textFields["convos.search"].waitForExistence(timeout: 10),
                      "Conversations search pill did not appear")
        let populated = anyElement("convos.list").waitForExistence(timeout: 10)
        XCTAssertTrue(populated || anyElement("convos.empty").waitForExistence(timeout: 5),
                      "Expected either conversation rows or the empty state")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: conversations\n".data(using: .utf8)!)
        sleep(4)

        // Back pops to the thread (the root registers "Ask" as its hidden-bar title, so the
        // system back button carries it).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(anyElement("ask.input").waitForExistence(timeout: 10),
                      "Expected the Ask thread after popping Conversations")
    }

    /// Settings tab (Task 7): account email, a non-empty subscription status line, and sign-out —
    /// exercised as its own smoke test now that `testLibrarySmoke`'s sign-out step lives here
    /// instead (see that test's own updated navigation preamble). The test account carries an
    /// active trial/subscription (seeded in plan 1), so this only asserts the status line is
    /// non-empty — never a specific status string, which would make this test brittle against
    /// any real subscription-lifecycle change (trial expiring, plan changes, etc.).
    func testSettingsSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        app.tabBars.buttons["Settings"].tap()

        let emailText = anyElement("settings.account.email")
        XCTAssertTrue(emailText.waitForExistence(timeout: 10), "Account email not found in Settings")
        XCTAssertEqual(emailText.label, email, "Expected the signed-in account's own email")

        let statusText = anyElement("settings.subscription.status")
        XCTAssertTrue(statusText.waitForExistence(timeout: 15), "Subscription status line not found")
        XCTAssertFalse(statusText.label.trimmingCharacters(in: .whitespaces).isEmpty,
                       "Expected a non-empty subscription status line")

        // Screenshot rig (same checkpoint technique as testDetailSheets/testAskSmoke/
        // testVoiceNoteSmoke): holds here, with the full Settings list on screen (account,
        // phone, subscription all loaded — Tags was retired from this tab, final wave item E),
        // so an external `xcrun simctl io <udid> screenshot` can capture it before this test
        // moves on to signing out.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: settings\n".data(using: .utf8)!)
        sleep(4)

        // Sign out via Settings (Task 7: relocated from the library toolbar).
        let signOutButton = app.buttons["settings.signout"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 5), "Sign Out row not found in Settings")
        signOutButton.tap()

        confirmSignOut(app)

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10), "Expected the sign-in screen after signing out")
    }

    /// Plan 7 Task 2: proves PP Neue Montreal is bundled + actually loads in the APP target (the
    /// share extension gets its own proof — a DEBUG print of `UIFont.familyNames` captured live,
    /// since an appex has no UI surface this smoke rig can reach). `design.fontStatus` is a
    /// DEBUG-only a11y label in the Settings footer (`StashType.isNeueMontrealAvailable` reads
    /// `"font:neue-montreal"` when `Font.custom` resolves, `"font:sf-fallback"` otherwise) — if the
    /// font ever fails to register (bad `UIAppFonts` entry, missing bundle resource), this catches
    /// it at UI-test time instead of silently degrading to SF Pro on device. Plan 9 Task 0 appended
    /// a second probe to the same label — `StashType.isEditorialAvailable` reads
    /// `"editorial:loaded"` once the "PP Editorial New" card-title face registers in the app
    /// target's own `UIAppFonts` entry (`"editorial:fallback"` otherwise) — asserted together since
    /// both are read from the same identifier.
    func testDesignSystemFontsLoad() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        app.tabBars.buttons["Settings"].tap()

        // Plan 14 T3 added a whole new "Delete account" section above the footer, pushing the
        // DEBUG-only font-status label below the fold; SwiftUI `List` rows off-screen aren't in
        // the accessibility tree yet, so scroll the list before looking for it (same technique
        // `testLibrarySearchBarFadesAndKeyboardDismisses` already uses on the grid).
        app.swipeUp()

        let fontStatus = app.descendants(matching: .any)["design.fontStatus"]
        XCTAssertTrue(fontStatus.waitForExistence(timeout: 10), "design.fontStatus label not found in Settings footer")
        XCTAssertEqual(fontStatus.label, "font:neue-montreal editorial:loaded",
                       "Expected PP Neue Montreal and PP Editorial New to both load in the app target, not fall back")
    }

    /// Plan 7 Task 3: the sign-in card's pill tabs actually switch content — tapping
    /// `auth.tab.signUp` reveals the sign-up-only `auth.username` field, tapping back to
    /// `auth.tab.signIn` hides it again. Doesn't submit anything (no account is created), so it
    /// needs no test credentials and is safe to run standalone.
    func testSignUpTabRenders() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10),
                      "Expected the sign-in screen to appear")

        let signUpTab = app.buttons["auth.tab.signUp"]
        XCTAssertTrue(signUpTab.waitForExistence(timeout: 5), "Expected a Sign up tab")
        signUpTab.tap()

        let usernameField = app.textFields["auth.username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5), "Expected the username field on the Sign up tab")

        let signInTab = app.buttons["auth.tab.signIn"]
        XCTAssertTrue(signInTab.waitForExistence(timeout: 5), "Expected a Sign in tab")
        signInTab.tap()

        XCTAssertFalse(usernameField.waitForExistence(timeout: 3), "Expected the username field to disappear back on the Sign in tab")
    }

    /// Plan 8 Task 2 (feedback round 1): Will's reversal — the plan-7 footer text links didn't
    /// work well on a phone ("the previous implementation… buttons in a mobile friendly way was
    /// the better approach — go back to this"), so this restores the pre-plan-7 header affordance:
    /// two round icon buttons, right-aligned above the thread. Plan 12 Task 2 then added a small
    /// "Chat with your Stash" title left-aligned in the same header row (Will: "add a title back
    /// to the 'Ask' tab") — NOT the old "Ask Stash" title block this test used to describe as
    /// fully removed; only its item-count subtitle (`ask.itemCount`) stayed gone. Same
    /// accessibility identifiers as before (`ask.newChat`/`ask.history`), so
    /// `testConversationsSmoke`'s navigation keeps working unchanged; this test proves the NEW
    /// position (above the intro bubble, not below the composer) and that `ask.itemCount` is gone.
    func testAskHeaderButtonsOpenConversations() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        // Plan 16: straight onto Ask by launch argument (no tab-bar tap).
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password, landingTab: "--uitest-tab-ask"),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        let input = anyElement("ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")

        let newChatButton = app.buttons["ask.newChat"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 10), "New-chat header button missing")
        let historyButton = app.buttons["ask.history"]
        XCTAssertTrue(historyButton.exists, "History header button missing")

        // Above the intro bubble (the restored pre-plan-7 position), not below the composer (the
        // plan-7 footer-link position this reverses). Plan 16: a circle's accessibility frame is
        // its 44×44 pt TAP TARGET, which overhangs the 36 pt circle, so the circle itself is read
        // from the frame's centre and its known diameter.
        //
        // The intro bubble belongs to a fresh thread, and Ask opens on the account's latest
        // conversation instead when that is under 3 h old (`ChatStore.loadHistoryOnce`, web parity)
        // — any Ask test in the last 3 h leaves one (seen 2026-10-01: the thread opened on
        // `testAskSmoke`'s persimmons answer). Start a new chat first when it opened on one.
        let bubble = anyElement("ask.emptyState")
        // Any row: a long continued thread opens at its end, and its first row is in the lazy history, not built.
        let continuedThread = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ask.bubble.")).firstMatch
        if !bubble.waitForExistence(timeout: 5), continuedThread.exists {
            newChatButton.tap()
        }
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "Intro bubble did not appear")
        XCTAssertGreaterThanOrEqual(historyButton.frame.height, 43.5, "Expected History's 44 pt target")
        func circleBottom(_ button: XCUIElement) -> CGFloat { button.frame.midY + 36 / 2 }
        XCTAssertLessThan(circleBottom(newChatButton), bubble.frame.minY,
                          "Expected the new-chat circle above the intro bubble")
        XCTAssertLessThan(circleBottom(historyButton), bubble.frame.minY,
                          "Expected the history circle above the intro bubble")

        // The old "Ask Stash" title block's item-count subtitle stays gone — plan 12 Task 2 added
        // back a small "Chat with your Stash" title in this same header row (see `askHeader`),
        // but never brought back `ask.itemCount`.
        XCTAssertFalse(anyElement("ask.itemCount").exists, "Expected ask.itemCount to be removed")

        // Screenshot rig (same checkpoint technique as testAskSmoke/testConversationsSmoke): holds
        // here with the header buttons and intro bubble on screen before tapping through.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: ask-header-buttons\n".data(using: .utf8)!)
        sleep(4)

        historyButton.tap()
        XCTAssertTrue(app.navigationBars["Conversations"].waitForExistence(timeout: 10),
                      "Expected the Conversations screen title")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: conversations-rows\n".data(using: .utf8)!)
        sleep(4)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(anyElement("ask.input").waitForExistence(timeout: 10),
                      "Expected the Ask thread after popping Conversations")
    }

    /// 2026-09-07 Ask composer cleanup (Will's notes): the mic/dictation button is gone, and the
    /// composer row is `.top`-aligned so the send circle stays on the first line while the field
    /// grows. Types a question long enough to wrap to several lines (no send — the standing test
    /// account is subscription-gated for Ask anyway) and checks geometry: the send button's top
    /// edge matches the field's top edge, and sits well above the field's bottom edge. Also the
    /// screenshot rig for this round: two checkpoints, empty composer and the wrapped one.
    func testAskComposerLayout() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        // Plan 16: straight onto Ask by launch argument (no tab-bar tap).
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password, landingTab: "--uitest-tab-ask"),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        let input = anyElement("ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")
        let send = app.buttons["ask.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button did not appear")
        XCTAssertFalse(app.buttons["ask.mic"].exists, "Expected the mic button to be gone")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: ask-composer-empty\n".data(using: .utf8)!)
        sleep(4)

        MainActor.assumeIsolated { A11yScreens.tapUntilFocused(input) }
        input.typeText("Which of my saved links talk about coding agents, what did each of them recommend for keeping memory across sessions, and which one should I read first if I only have ten minutes tonight?")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: ask-composer-wrapped\n".data(using: .utf8)!)
        sleep(4)

        // Re-read frames after the field has grown. `ask.input`'s accessibility frame is the
        // TEXT area only — `ChatComposerBar`'s `.padding(.vertical, 10)` wraps it but is not part
        // of the element (measured live: one 14pt line reports ~17pt, three lines ~51pt) — so the
        // visible field spans `inputFrame` inset by that padding. With `.top` alignment the 40pt
        // send circle's top edge meets the field's top edge, and it ends above the field's
        // bottom edge once the field has wrapped.
        //
        // Plan 16: the send circle's accessibility frame is its 44×44 pt TAP TARGET, centred on the
        // 40 pt circle (2 pt of overhang each side), so the circle's own edges are read from the
        // frame's centre and its diameter.
        let fieldPadding: CGFloat = 10
        let sendDiameter: CGFloat = 40
        let inputFrame = input.frame
        let sendFrame = send.frame
        XCTAssertGreaterThanOrEqual(sendFrame.height, 43.5, "Expected the send circle's 44 pt target")
        let circleTop = sendFrame.midY - sendDiameter / 2
        let circleBottom = sendFrame.midY + sendDiameter / 2
        let fieldTop = inputFrame.minY - fieldPadding
        let fieldBottom = inputFrame.maxY + fieldPadding
        XCTAssertGreaterThan(inputFrame.height, 30, "Expected the composer to have wrapped (text height \(inputFrame.height))")
        XCTAssertLessThan(abs(circleTop - fieldTop), 4,
                          "Expected the send circle top-aligned with the field (circle top \(circleTop) vs field top \(fieldTop))")
        XCTAssertLessThan(circleBottom, fieldBottom - 6,
                          "Expected the send circle to end above the field's bottom edge (circle bottom \(circleBottom) vs field bottom \(fieldBottom))")
    }

    /// Plan 7 Task 6: the item detail sheet rebuilt to DESIGN.md's detail-panel anatomy — eyebrow
    /// (type pill + domain), URL bar (replacing the old blue "Open Link" button), pill content
    /// tabs, and the autosave footer caption. Exercised against the permanent "UITEST-FIXTURE:
    /// link one" fixture (`example.com`, per `docs/superpowers/plans/2026-08-17-
    /// ios-plan-4-object-parity.md`'s fixture table) — a link item, so every element under test
    /// (eyebrow domain, URL bar, the three-tab Summary/Original Content/Notes config) applies.
    /// Also asserts the retired tags UI is gone: no `detail.tags.input` anywhere in the sheet.
    func testDetailSheetAnatomy() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.textFields["library.search"]
        searchLibrary(app, for: "link one", cardTitled: "UITEST-FIXTURE: link one").tap()

        XCTAssertTrue(anyElement("detail.done").waitForExistence(timeout: 10), "Detail sheet did not present")

        let eyebrow = anyElement("detail.eyebrow")
        XCTAssertTrue(eyebrow.waitForExistence(timeout: 10), "Eyebrow not found")
        XCTAssertTrue(eyebrow.label.contains("LINK"), "Expected the eyebrow to read the type LINK, got '\(eyebrow.label)'")
        XCTAssertTrue(eyebrow.label.contains("example.com"),
                      "Expected the eyebrow to include the domain 'example.com', got '\(eyebrow.label)'")

        let urlBar = anyElement("detail.urlBar")
        XCTAssertTrue(urlBar.waitForExistence(timeout: 10), "URL bar not found")

        for label in ["Summary", "Original Content"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), "Expected a '\(label)' tab")
        }
        XCTAssertTrue(anyElement("detail.tabs").exists, "Expected the pill-tabs container")

        let autosave = anyElement("detail.autosave")
        XCTAssertTrue(autosave.waitForExistence(timeout: 10), "Autosave caption not found")
        XCTAssertEqual(autosave.label, "Changes saved automatically",
                       "Expected the resting autosave caption, got '\(autosave.label)'")

        XCTAssertFalse(anyElement("detail.tags.input").exists, "Expected the retired tags UI to be gone")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: detail-anatomy-link\n".data(using: .utf8)!)
        sleep(3)

        // --- Final wave, item B: the keyboard accessory clears WHICHEVER field has focus, not
        // just notes'. Previously hardcoded to only clear notes' own focus, so tapping it while
        // title/description was focused was a dead tap (confirmed live: the keyboard stayed up).
        // F7 (plan 12 final wave) then moved this control from the notes section header into the
        // pinned footer bar (right side, next to the autosave label) — reachable regardless of
        // scroll position instead of ~400pt below the title field. Same identifier, same
        // "visible while any field is focused" contract, so this assertion is unchanged.
        let titleField = anyElement("detail.title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        // Plan 16: the title wraps (a vertical-axis field), which a bare tap doesn't always focus.
        MainActor.assumeIsolated { A11yScreens.tapUntilFocused(titleField) }

        let dismissKeyboard = app.buttons["detail.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 10),
                      "Expected the keyboard-minimize accessory once the title field is focused")

        // Screenshot rig (same checkpoint technique as every other test in this file): holds here,
        // title focused with the keyboard + accessory both visible.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: final-wave-focus\n".data(using: .utf8)!)
        sleep(3)

        dismissKeyboard.tap()
        let accessoryGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                        object: dismissKeyboard)
        XCTAssertEqual(XCTWaiter().wait(for: [accessoryGone], timeout: 10), .completed,
                       "Expected the keyboard accessory to disappear once the title field's focus " +
                       "is cleared (final wave, item B)")

        // --- Task 7: Details drawer + Sharing section ---
        let detailsRow = anyElement("detail.details")
        XCTAssertTrue(detailsRow.waitForExistence(timeout: 10), "Details drawer row not found")
        XCTAssertTrue(detailsRow.label.contains("example.com"),
                      "Expected the collapsed Details row to show the fixture's domain, got '\(detailsRow.label)'")
        detailsRow.tap()

        let savedRow = anyElement("detail.details.row.saved")
        XCTAssertTrue(savedRow.waitForExistence(timeout: 10),
                      "Expected a 'Saved' row once the Details drawer expands")

        let sharing = anyElement("detail.sharing")
        XCTAssertTrue(sharing.waitForExistence(timeout: 10), "Sharing section not found")
        XCTAssertTrue(sharing.label.contains("Private"),
                      "Expected the Sharing section to read Private for this fixture, got '\(sharing.label)'")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: detail-drawer-sharing\n".data(using: .utf8)!)
        sleep(3)

        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
    }

    // MARK: - Composer keyboard accessory (Plan 8 fix round 1, Task 3; reworked plan 12 Task 2)

    /// Device-review fix: while typing, the keyboard toolbar's text "Done" button used to read as
    /// a second primary action competing with the violet send button. Replaced with an icon-only
    /// minimize-keyboard control (`keyboard.chevron.compact.down`) — this proves the "Done" text
    /// button is gone, the icon control appears (with an accessible label) once the editor is
    /// focused, and tapping it actually dismisses the keyboard (the accessory itself disappears
    /// once focus clears). Also proves the composer's old public/lock toggle
    /// (`capture.toggle.public`) is gone entirely — sharing now lives only on the detail sheet's
    /// `detail.public.toggle` (see `testDetailSheets`), and captures default private
    /// (`CaptureViewModel.isPublic == false`, unchanged in StashKit by this fix). Also screenshots
    /// CaptureAttachmentsRow's clipped-× fix: picks a photo via the real PhotosPicker (the
    /// simulator's own default Photos library) and holds with the chip visible.
    ///
    /// Plan 12 Task 2 (Will, on-device: "the 'minimize keyboard' button appears to occlude the
    /// 'submit note' button" on iOS 26): `.toolbar(placement: .keyboard)` is retired — the same
    /// `capture.dismissKeyboard` identifier moved to a plain button in the composer's own bottom
    /// bar (left group, shown only while the editor is focused). Final wave (F1 + Will's markup,
    /// device review round 2): that in-bar CIRCLE turned out to have the same class of bug at a
    /// smaller scale — it widened the bottom bar past the card's own column while focused
    /// (measured margin 14→2.7pt) — so it's gone too, replaced with a "Cancel" TEXT button
    /// top-right of the header row (visible only while the editor is focused; tapping it resigns
    /// focus and keeps the draft — never clears it). Same identifier, new label ("Cancel", not
    /// "Hide keyboard") and new location; assertions below updated to match.
    func testComposerKeyboardAccessory() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // Add is the launch tab — the editor must appear without tapping any tab.
        let editor = anyElement("capture.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 15),
                      "Expected the capture editor to appear on launch (Add is the launch tab)")
        MainActor.assumeIsolated { A11yScreens.dismissSavePasswordPrompt(app) }

        // The composer's own lock/public toggle is gone entirely — sharing lives on the detail
        // sheet only now.
        XCTAssertFalse(anyElement("capture.toggle.public").exists,
                       "Expected the composer's public/lock toggle to be removed")

        editor.tap()
        editor.typeText("x")

        // `.buttons[...]` (not the file's usual `anyElement` helper) — a plain header-row text
        // button now (final wave, F1 + Will's markup: the in-bar minimize CIRCLE that used to sit
        // here was removed outright — it widened the bottom bar past the card's own column while
        // focused — and replaced with a "Cancel" text button top-right of the wordmark header),
        // scoped the same way `capture.save`/`signin.submit` already are elsewhere in this file.
        let dismissKeyboard = app.buttons["capture.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 10),
                      "Expected the header's Cancel control to appear while the editor is focused")
        XCTAssertEqual(dismissKeyboard.label, "Cancel",
                       "Expected the header control's a11y label to read 'Cancel', got '\(dismissKeyboard.label)'")
        XCTAssertFalse(app.buttons["Done"].exists,
                       "Expected the keyboard toolbar's text 'Done' button to be gone")

        // Screenshot rig (same checkpoint technique as testCaptureSmoke/testLocationPinSmoke):
        // holds here, keyboard up with "x" typed, so an external `xcrun simctl io <udid>
        // screenshot` can capture the violet send button (bottom bar) alongside the header's
        // "Cancel" text button — no competing "Done" text button, no overlap between the two.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: composer-keyboard\n".data(using: .utf8)!)
        sleep(3)

        dismissKeyboard.tap()

        let accessoryGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                        object: dismissKeyboard)
        XCTAssertEqual(XCTWaiter().wait(for: [accessoryGone], timeout: 10), .completed,
                       "Expected 'Cancel' to disappear once the keyboard is dismissed")
        // Cancel = dismiss keyboard only, draft preserved — the typed "x" survives the tap above
        // (contrast a hypothetical "discard" affordance, which this deliberately is not).
        XCTAssertEqual(app.textViews["capture.editor"].value as? String, "x",
                       "Expected Cancel to preserve the draft, not clear it")

        // Attachment × clipping fix (CaptureAttachmentsRow): drives the real PhotosPicker against
        // the simulator's own default Photos library (seeded content every sim ships with, no
        // fixture needed) rather than screenshotting manually — PHPickerViewController runs
        // out-of-process, so no photo-library permission prompt is even in the way here.
        app.buttons["capture.photosPicker"].tap()

        let firstPhoto = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
        let photoCell = firstPhoto.waitForExistence(timeout: 10) ? firstPhoto : app.scrollViews.firstMatch.images.firstMatch
        XCTAssertTrue(photoCell.waitForExistence(timeout: 10), "Expected the system photo picker to show at least one photo")
        // A coordinate tap: on iOS 26.5 the out-of-process picker reports its photos "not
        // hittable" to XCUITest, and `tap()` refuses to tap such an element.
        photoCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let addButton = app.navigationBars.buttons["Add"]
        if addButton.waitForExistence(timeout: 5) { addButton.tap() }

        let attachmentRemove = anyElement("capture.attachment.remove")
        XCTAssertTrue(attachmentRemove.waitForExistence(timeout: 10),
                      "Expected an attachment chip with a remove control after picking a photo")

        // Holds with the attachment chip visible so an external screenshot can confirm the
        // remove × (offset off the chip's top-trailing corner) is no longer clipped by the
        // attachments row's own top edge.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: composer-attachment\n".data(using: .utf8)!)
        sleep(3)
    }

    /// Plan 9 Task 3: visual sweep — visits all four tabs and attaches a screenshot of each
    /// (`.keepAlways` so `xcresulttool` can pull them back out after the run), so every suite
    /// run leaves a reviewable visual record of the themed surfaces. Ported from the
    /// `worktree-ios-plan6-visual` branch's own `testVisualSweepScreenshots` (never merged to
    /// main), against this suite's current tab labels/helpers. Deliberately gate-agnostic: the
    /// only asserts are reachability (tab bar taps), never gate-dependent state (no save
    /// actions), so this passes with the test account's trial lapsed or active — and is the
    /// proof rig for DESIGN.md's "Color scheme: light-only" lock: run once with the simulator's
    /// OS appearance set to Light and once set to Dark (`xcrun simctl ui <udid> appearance
    /// light|dark`, external to this test), the four screenshots from the Dark-appearance run
    /// must render identically to the Light-appearance run — `StashApp`'s
    /// `.preferredColorScheme(.light)` overrides the system trait regardless.
    func testVisualSweepScreenshots() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        for (tab, name) in [("Add", "add"), ("Ask", "ask"), ("View", "view"), ("Settings", "settings")] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 10), "Tab \(tab) not found")
            tabButton.tap()
            sleep(1)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "sweep-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    /// Plan 9 Task 3: two assertions Tasks 1/2 couldn't add themselves (single-owner-of-this-file
    /// rule for this round) — (a) the always-visible type chip (`card.typeChip`, `CardChips.swift`
    /// `TypeChip`) renders for the types Task 1's fixtures/anatomy work covers and stays absent for
    /// the types DESIGN.md says get "real imagery — no field, no tint" instead; (b) the composer
    /// card's own idle/composing state (`capture.card`'s `accessibilityValue`, `ComposerCard.swift`)
    /// actually flips with focus, the way Task 2's `stashComposerRing` styling assumes it does.
    func testLibraryTypeChipAndComposerCard() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")

        // Finds one fixture's card by title after the server search settles (plan 15), and reads
        // `card.typeChip` (a shared identifier across every card in the grid) from INSIDE that
        // card only, never a sibling's.
        func isolateAndCheck(search: String, title: String, assert: (XCUIElement) -> Void) {
            let card = searchLibrary(app, for: search, cardTitled: title)
            assert(card.descendants(matching: .any)["card.typeChip"])
            clearLibrarySearch(app)
        }

        // (a) Type chip present, correct label: audio fixture -> "voice note" (under the ten-
        // minute recording/voice-note threshold, CardChips.swift's `audioSubtype`), document
        // fixture -> "pdf" (lowercased extension, CardChips.swift's `typeChip(for:)`).
        isolateAndCheck(search: "audio one", title: "UITEST-FIXTURE: audio one") { chip in
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Expected a type chip for the audio fixture")
            XCTAssertEqual(chip.label, "voice note", "Expected the audio fixture's type chip to read 'voice note', got '\(chip.label)'")
        }

        isolateAndCheck(search: "document one", title: "UITEST-FIXTURE: document one") { chip in
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Expected a type chip for the document fixture")
            XCTAssertEqual(chip.label, "pdf", "Expected the document fixture's type chip to read 'pdf', got '\(chip.label)'")
        }

        // (a) Type chip present, NEUTRAL: plan 9 final wave — DESIGN.md "Photos, videos, and
        // link covers use real imagery — no field, no tint" still holds (no TINTED chip / plate
        // tint for these), but `typeChip(for:)` now emits a neutral `MetaChip` carrying the
        // link's flavor label for every `.link`, so the repo-link and video-link fixtures (Task
        // 9's own link-flavor fixtures) each get a leading `card.typeChip` reading their flavor.
        isolateAndCheck(search: "repo link", title: "supabase/supabase-swift") { chip in
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Expected a neutral type chip for the repo-link fixture")
            XCTAssertEqual(chip.label, "repo", "Expected the repo-link fixture's type chip to read 'repo', got '\(chip.label)'")
        }

        isolateAndCheck(search: "video link", title: "Rick Astley") { chip in
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Expected a neutral type chip for the video-link fixture")
            XCTAssertEqual(chip.label, "video", "Expected the video-link fixture's type chip to read 'video', got '\(chip.label)'")
        }
        // (`clearLibrarySearch` already dismissed the keyboard via the pill's clear button.)

        // (b) Composer card idle/active state (Add tab) — `ComposerCard`'s `accessibilityValue`
        // mirrors `isPanelActive` (editor focus OR non-empty draft; CaptureComposerView.swift).
        app.tabBars.buttons["Add"].tap()
        let captureCard = anyElement("capture.card")
        XCTAssertTrue(captureCard.waitForExistence(timeout: 10), "Expected the composer card on the Add tab")
        XCTAssertEqual(captureCard.value as? String, "idle", "Expected the composer card to start idle")

        let editor = anyElement("capture.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Expected the capture editor to appear")
        editor.tap()
        XCTAssertEqual(captureCard.value as? String, "active", "Expected the composer card to go active once the editor is focused")

        // `.buttons[...]` (not `anyElement`) — the header's "Cancel" text button
        // (`testComposerKeyboardAccessory` documents the F1 rework in full).
        let dismissKeyboard = app.buttons["capture.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 10), "Expected the header's Cancel control while the editor is focused")
        dismissKeyboard.tap()
        // Draft is still empty (no text was typed) — the editor losing focus alone must be
        // enough to drop the card back to idle.
        XCTAssertEqual(captureCard.value as? String, "idle", "Expected the composer card to return to idle once the (empty) editor is blurred")
    }

    /// Plan 12, Task 3 (device notes 6 + 7), rebuilt in plan 16: the "Search your stash" pill is the
    /// first element of the grid's scroll content, so scrolling carries it away with the cards
    /// (fading as it goes, never collapsing over them — Will's screenshot had it half covered by the
    /// first card) and scrolling back to the top brings it back; it never comes to rest part-way out
    /// (a release inside its row snaps to the nearer end); the old item-count row is gone outright;
    /// the pill never moves while its field is focused; and every quiet way of leaving the keyboard
    /// up has a dismissal — Cancel (clears the query too), the clear button, return, and tapping a
    /// card. (`LibraryDetailUITests` samples the pill's frame step by step.) Signs in with
    /// `launchSignedIn` + `--uitest-tab-view` (no tab-bar tap — iOS 26 swallows one while the
    /// sign-in keyboard is still going away), so it runs on the iOS 26 simulators too.
    @MainActor
    func testLibrarySearchBarFadesAndKeyboardDismisses() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()

        func anyElement(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any)[identifier]
        }

        /// Polls `condition` until it holds or `timeout` passes (frames aren't KVO-observable).
        func eventually(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                usleep(200_000)
            }
            return condition()
        }

        // (`launchSignedIn` declines iOS 26's "Save Password?" sheet, so it can't cover the pill.)
        launchSignedIn(app, arguments: ["--uitest-tab-view"], email: email, password: password)

        // Plan 12 removes the item-count row outright (not just its text) — the identifier
        // must be gone from the tree entirely.
        XCTAssertFalse(anyElement("library.itemCount").exists,
                        "library.itemCount should have been removed (Task 3: hide the item count)")

        let searchField = app.textFields["library.search"]
        let pill = anyElement("library.search.pill")
        let grid = anyElement("library.grid")
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        XCTAssertTrue(grid.waitForExistence(timeout: 15), "Library grid did not appear")
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected at least one card")
        XCTAssertTrue(searchField.isHittable, "Expected the search pill visible/hittable at the top of the list")
        let restPillMinY = pill.frame.minY

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: search-fade-top\n".data(using: .utf8)!)
        sleep(2)

        // 1. Scrolling the grid up (swipe up) carries the pill up and away with the cards: it
        // leaves its resting slot and stops taking taps once it has faded out — `isHittable` is
        // the one thing XCUITest can observe of that (SwiftUI opacity isn't exposed directly), so
        // the view is also `allowsHitTesting(false)` once nearly transparent. It stays in the tree.
        grid.swipeUp()
        grid.swipeUp()
        sleep(1) // let the scroll settle before reading hit-testability
        XCTAssertTrue(searchField.exists, "Search field should still exist in the tree once scrolled away (identifier isn't removed, just non-hittable)")
        XCTAssertFalse(searchField.isHittable, "Expected the search pill to stop being hittable once scrolled away")
        XCTAssertLessThan(pill.frame.maxY, restPillMinY, "Expected the pill to have scrolled up out of its resting slot")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: search-fade-mid-scroll\n".data(using: .utf8)!)
        sleep(2)

        // 2. Scrolling back down (toward the top) restores it. Four swipes, not two: two
        // swipe-ups' worth of content can be more than two swipe-downs reliably cancel out
        // (observed flake), whereas over-swiping down is harmless once already at the top — the
        // scroll view just clamps/bounces there (and may pull to refresh, which settles back).
        grid.swipeDown()
        grid.swipeDown()
        grid.swipeDown()
        grid.swipeDown()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field should exist after scrolling back to the top")
        XCTAssertTrue(eventually(10) { searchField.isHittable && abs(pill.frame.minY - restPillMinY) <= 1 },
                      "Expected the search pill back in its resting slot, hittable (at \(pill.frame.minY), rest \(restPillMinY))")

        // 3. It never comes to rest part-way out (plan 16 review M-2 — half faded, half under the
        // clock): a slow drag released inside the search row snaps to the nearer end. Short of the
        // row's middle it springs back to rest; past it, the row goes all the way out. Slow drags
        // with a hold at the end, so nothing flings (the release has no velocity: any snap is the
        // scroll view's own). The drags allow ~10 pt of pan slop: 24 pt moves the list well under
        // half the 60 pt row, 56 pt well over half and short of all of it.
        let window = app.windows.firstMatch.frame
        let dragStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.midX, dy: window.midY + 120))
        // The row is the pill (plan 16: at least 44 pt, was 42) plus its 8 pt top and 10 pt bottom
        // padding (`LibrarySearchRow`).
        let rowHeight = pill.frame.height + 18
        XCTAssertGreaterThanOrEqual(pill.frame.height, 43.5, "Expected the search pill at least 44 pt tall")
        // A slow drag from rest, released without momentum. On a busy simulator a synthesized one
        // can still land as a fling (seen once in LibraryDetailUITests on a cold-booted iOS 26.5
        // sim): the list coasts on past the whole row, which the snap rightly leaves alone. Only
        // momentum carries 24 or 56 pt of drag that far, so that release is retried from rest; a
        // release that ends anywhere within reach of the row is what the assertions below judge.
        func slowDrag(_ distance: CGFloat) {
            for attempt in 1...3 {
                dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -distance)),
                                withVelocity: .slow, thenHoldForDuration: 0.3)
                usleep(800_000)
                guard restPillMinY - pill.frame.minY > rowHeight + 20, attempt < 3 else { return }
                grid.swipeDown()
                grid.swipeDown()
                _ = eventually(10) { searchField.isHittable && abs(pill.frame.minY - restPillMinY) <= 1 }
            }
        }
        slowDrag(24)
        XCTAssertTrue(eventually(3) { abs(pill.frame.minY - restPillMinY) <= 1 },
                      "Released short of the row's middle, the pill should spring back to rest (at \(pill.frame.minY), rest \(restPillMinY))")
        XCTAssertTrue(searchField.isHittable, "Expected the pill back at rest and tappable")
        slowDrag(56)
        XCTAssertTrue(eventually(3) { abs((restPillMinY - pill.frame.minY) - rowHeight) <= 1.5 },
                      "Released past the row's middle, the row should go all the way out (\(restPillMinY - pill.frame.minY) of \(rowHeight) pt)")
        XCTAssertFalse(searchField.isHittable, "Expected the pill gone once its row snapped out")
        attachScreenshot(named: "task-4-fix-snapped-out")
        grid.swipeDown()
        grid.swipeDown()
        XCTAssertTrue(eventually(10) { searchField.isHittable && abs(pill.frame.minY - restPillMinY) <= 1 },
                      "Expected the search pill back in its resting slot (at \(pill.frame.minY), rest \(restPillMinY))")
        searchField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Expected the keyboard up once the search field is focused")

        // 4. Typing never moves it: the grid under it changes (local filter → searching → the
        // server's answer), the pill stays put, focused, with the keyboard up.
        let needle = "zzzunmatchablezzz"
        for chunk in ["zzz", "unmatchable", "zzz"] {
            searchField.typeText(chunk)
            XCTAssertEqual(pill.frame.minY, restPillMinY, accuracy: 1, "The pill moved while typing '\(chunk)'")
            XCTAssertTrue(searchField.isHittable, "The pill stopped being hittable while typing '\(chunk)'")
        }
        XCTAssertTrue(waitForLibrarySearchToSettle(app), "Search for '\(needle)' never settled")
        attachScreenshot(named: "task-4-fix-no-matches")
        XCTAssertEqual(pill.frame.minY, restPillMinY, accuracy: 1, "The pill moved once the results settled")
        XCTAssertTrue(app.keyboards.element.exists, "Expected the keyboard still up while the field is focused")
        XCTAssertEqual(searchField.value as? String, needle, "Expected the typed query intact in the field")

        // 5. Tapping Cancel is the standard-iOS-search way to clear AND dismiss in one tap (device
        // note 7: "no way to hide the keyboard in a smart way after... the user clears the search box").
        let cancelButton = app.buttons["library.search.cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Expected a Cancel affordance while the search field is focused")
        // Plan 16: the shared `StashCancelButton` — a 44 pt target that overhangs the word, so the
        // pill (checked above: it never moved) keeps its height beside it.
        XCTAssertGreaterThanOrEqual(cancelButton.frame.height, 43.5, "Expected Cancel's 44 pt target, got \(cancelButton.frame)")
        XCTAssertEqual(cancelButton.label, "Cancel")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: search-active-cancel\n".data(using: .utf8)!)
        sleep(2)

        cancelButton.tap()
        XCTAssertFalse(app.keyboards.element.exists, "Expected the keyboard dismissed after tapping Cancel")
        // XCUITest quirk (also relied on nowhere else in this file, so spelled out here): a
        // plain `TextField`'s `.value` for an EMPTY field reports its placeholder text, not ""
        // or nil — so "cleared" reads as the placeholder, not emptiness.
        let clearedValue = (searchField.value as? String) ?? ""
        XCTAssertEqual(clearedValue, "Search your stash",
                       "Expected the query cleared after Cancel (placeholder showing), got '\(clearedValue)'")

        // Plan 16 (review M-5): the other three dismissals device note 7 asked for, one assertion each.
        func keyboardGone() -> Bool {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.keyboards.element)
            return XCTWaiter().wait(for: [gone], timeout: 3) == .completed
        }
        // 6. The clear button clears the query AND drops the keyboard in one tap.
        searchField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Expected the keyboard up to type a query")
        searchField.typeText("zz")
        let clearButton = app.buttons["library.search.clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Expected the clear button once a query is typed")
        // Plan 16: a 44×44 pt target around the glyph (`.stashPlain`), and a name for VoiceOver.
        XCTAssertGreaterThanOrEqual(clearButton.frame.width, 43.5, "Expected the clear button's 44 pt target, got \(clearButton.frame)")
        XCTAssertGreaterThanOrEqual(clearButton.frame.height, 43.5, "Expected the clear button's 44 pt target, got \(clearButton.frame)")
        XCTAssertEqual(clearButton.label, "Clear search")
        // 2b review M-4: that target overhangs its glyph, but never the field — a tap at the very
        // end of a long query puts the caret there; it must not clear the search or drop the
        // keyboard. (Typing after it proves the field kept focus, and closes any edit menu.)
        let longQuery = "zz" + String(repeating: "z", count: 48)
        searchField.typeText(String(repeating: "z", count: 48))
        let fieldFrame = searchField.frame, clearFrame = clearButton.frame
        print("M-4 field \(fieldFrame) · clear target \(clearFrame) · overlap \(fieldFrame.maxX - clearFrame.minX) pt")
        XCTAssertGreaterThanOrEqual(clearFrame.minX, fieldFrame.maxX - 0.5,
                                    "The clear button's target must not overlap the field (field \(fieldFrame), clear \(clearFrame))")
        A11yScreens.tap(app, at: CGPoint(x: fieldFrame.maxX - 1, y: fieldFrame.midY))
        sleep(1)
        XCTAssertEqual((searchField.value as? String) ?? "", longQuery,
                       "A tap at the end of the field must not clear the query (field \(fieldFrame), clear target \(clearFrame))")
        XCTAssertTrue(app.keyboards.element.exists, "A tap at the end of the field must not drop the keyboard")
        searchField.typeText("z")
        XCTAssertEqual(searchField.value as? String, longQuery + "z", "The field should keep focus after a tap at its end")
        clearButton.tap()
        XCTAssertTrue(keyboardGone(), "Expected the keyboard dismissed after tapping the clear button")
        XCTAssertEqual((searchField.value as? String) ?? "", "Search your stash", "Expected the query cleared by the clear button")

        // 7. Return (the keyboard's Search key) submits the query and drops the keyboard, query intact.
        searchField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Expected the keyboard up to type a query")
        searchField.typeText("zz\n")
        XCTAssertTrue(keyboardGone(), "Expected the keyboard dismissed after return")
        XCTAssertEqual(searchField.value as? String, "zz", "Return keeps the query")
        clearButton.tap()
        XCTAssertEqual((searchField.value as? String) ?? "", "Search your stash")

        // 8. Tapping a card drops the keyboard before its detail sheet opens (not left up behind it).
        searchField.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Expected the keyboard up before the card tap")
        let card0 = anyElement("card.0")
        XCTAssertTrue(card0.waitForExistence(timeout: 10), "Expected a card under the focused pill")
        // Near the card's top — the keyboard covers its lower part; the whole card is one target.
        card0.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        let close = app.buttons["detail.done"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Expected the card's detail sheet")
        XCTAssertTrue(keyboardGone(), "Expected the keyboard dismissed by the card tap")
        close.tap()
    }

    // MARK: - Onboarding (Task 4, plan 12; carousel rewrite, plan 13 task 1)

    /// "How to easily stash" panel — Will's device note 10: shown ONCE per app install right
    /// after a successful sign-in/sign-up, re-openable any time from Settings → "How to stash".
    /// Plan 13 replaced the single static card with a three-panel swipe carousel (`Next` →
    /// `Got it` on the last panel, plus a `Skip` link) — see `HowToStashView`'s own doc comment
    /// for the full "Skip is not later" semantics this exercises. Six behaviors in one flow (each
    /// needs the prior step's end state, so one test is more failure-legible here than several
    /// that would each re-derive the same setup):
    /// 1. `--uitest-reset-onboarding` (DEBUG launch arg, wired alongside `--uitest-reset-auth` in
    ///    `SessionStore.start()`) forces both of `OnboardingState`'s flags to their defaults
    ///    before this sign-in, so the panel appears on panel 1; tapping `onboarding.gotIt` twice
    ///    (labeled "Next" on panels 1-2) advances to panel 3, where the SAME identifier now reads
    ///    "Got it" — tapping it there dismisses the panel AND marks it permanently seen. Screenshot
    ///    checkpoints fire on all three panels for the visual-parity check against the prototype
    ///    PNGs (`docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe-panel{1,2,3}.png`).
    /// 2. A full app relaunch (real process boundary) with **NO launch arguments at all**: the
    ///    Keychain session from step 1 restores directly to `.signedIn`, landing on the tab bar
    ///    with no sign-in screen, and the panel must NOT reappear — it's genuinely seen now, not
    ///    just deferred.
    /// 3. A second `--uitest-reset-onboarding` + `--uitest-reset-auth` sign-in exercises the
    ///    `Skip` branch instead: the panel appears again on panel 1, `onboarding.skip` dismisses
    ///    it immediately (without advancing through panels 2-3) straight to the tab bar.
    /// 4. Another bare-argument relaunch: the panel must not reappear after Skip either — plan
    ///    13's semantics make Skip mark `hasSeenHowToStash` exactly like Got it does, not defer
    ///    it the way plan 12's "Show me later" used to.
    /// 5. Settings' "How to stash" row (`settings.howToStash`) re-opens the same panel on demand
    ///    regardless of the seen flag; this time `Skip` from panel 1 dismisses it back to Settings.
    @MainActor
    func testOnboardingPanelShowsOnceAfterSignIn() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()

        func signIn(_ emailField: XCUIElement, _ passwordField: XCUIElement) {
            emailField.tap()
            emailField.typeText(email)
            passwordField.tap()
            passwordField.typeText(password)
            app.buttons["signin.submit"].tap()
        }

        // --- 1. Reset both flags; sign in; the panel appears on panel 1; Next ×2 reaches panel 3
        // where the primary button's label has flipped to "Got it"; tapping it marks seen and
        // dismisses.
        app.launchArguments = ["--uitest-reset-auth", "--uitest-reset-onboarding"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        signIn(emailField, app.secureTextFields["signin.password"])

        let primaryButton = app.buttons["onboarding.gotIt"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 15),
                      "Expected the 'How to easily stash' panel to appear after a fresh sign-in with --uitest-reset-onboarding")
        XCTAssertTrue(app.staticTexts["onboarding.title"].exists, "Expected the panel's title to be present")
        XCTAssertTrue(app.buttons["onboarding.skip"].exists, "Expected the 'Skip' link to be present")
        XCTAssertEqual(primaryButton.label, "Next", "Expected panel 1's primary button labeled 'Next'")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: onboarding-panel-1\n".data(using: .utf8)!)
        sleep(2)

        primaryButton.tap()
        XCTAssertEqual(primaryButton.label, "Next", "Expected panel 2's primary button still labeled 'Next'")
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: onboarding-panel-2\n".data(using: .utf8)!)
        sleep(2)

        primaryButton.tap()
        XCTAssertEqual(primaryButton.label, "Got it", "Expected panel 3's primary button label to flip to 'Got it'")
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: onboarding-panel-3\n".data(using: .utf8)!)
        sleep(2)

        primaryButton.tap()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 10),
                      "Expected the tab bar back after dismissing the panel with 'Got it'")

        // --- 2. Relaunch with NO launch arguments — a real cold-launch Keychain restore. The
        // panel must NOT reappear: it's genuinely seen now.
        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15),
                      "Expected a bare relaunch to restore straight to the tab bar via the Keychain session")
        XCTAssertFalse(app.textFields["signin.email"].exists,
                       "Expected no sign-in screen on a Keychain-restore relaunch")
        XCTAssertFalse(app.buttons["onboarding.gotIt"].exists,
                       "Expected the seen panel NOT to reappear on a cold relaunch")

        // --- 3. Reset both flags again (a fresh --uitest-reset-onboarding run, not a sign-out —
        // `hasSeenHowToStash` only ever resets via that DEBUG launch arg) to exercise the Skip
        // branch: the panel appears on panel 1 again, and `onboarding.skip` dismisses it
        // immediately without ever advancing to panel 2/3.
        app.terminate()
        app.launchArguments = ["--uitest-reset-auth", "--uitest-reset-onboarding"]
        app.launch()

        let emailField2 = app.textFields["signin.email"]
        XCTAssertTrue(emailField2.waitForExistence(timeout: 10), "Expected the sign-in screen after resetting auth")
        signIn(emailField2, app.secureTextFields["signin.password"])

        let skipButton = app.buttons["onboarding.skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 15),
                      "Expected the panel to reappear after resetting onboarding again")
        // Task 1 root-cause note (kept for the next time a panel-height change reintroduces
        // this): `skipButton` sits at the very bottom of the card, and an earlier, taller
        // `HowToStashView.panelHeight` (508) put it only ~25pt above the bottom of an iPhone 15
        // Pro's 852pt screen — inside the zone iOS reserves for the home-indicator swipe gesture.
        // XCUITest still reported the element `hittable`, but the OS silently ate the touch
        // before SwiftUI's `Button` ever saw it: `onboarding.skip` appeared to tap fine (no
        // error), yet `OnboardingState.markHowToStashSeen()` never ran, so the panel reappeared
        // on the very next relaunch. Fixed in the view (tighter padding, `panelHeight` 490) so
        // `skipButton` now sits with a real safety margin above that zone — this `sleep(1)` is
        // just the same settle beat step 1's Next/Got it taps already get for free from their
        // screenshot-checkpoint sleeps.
        sleep(1)
        skipButton.tap()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 10),
                      "Expected the tab bar back after dismissing the panel with 'Skip'")

        // --- 4. Another bare relaunch: Skip must mark the panel seen exactly like Got it does —
        // plan 13's "Skip is not later" semantics — so it must not reappear here either.
        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15),
                      "Expected to reach the tab bar directly, with no onboarding panel in the way")
        XCTAssertFalse(app.buttons["onboarding.gotIt"].exists,
                       "Expected the 'How to easily stash' panel NOT to reappear once Skip marked it seen")

        // --- 5. Settings → "How to stash" re-opens it any time regardless of the seen flag;
        // Skip dismisses it back to Settings.
        app.tabBars.buttons["Settings"].tap()
        let howToStashRow = app.buttons["settings.howToStash"]
        XCTAssertTrue(howToStashRow.waitForExistence(timeout: 10), "Expected the 'How to stash' Settings row")
        howToStashRow.tap()

        let skipButton2 = app.buttons["onboarding.skip"]
        XCTAssertTrue(skipButton2.waitForExistence(timeout: 10),
                      "Expected Settings' row to re-open the 'How to easily stash' panel")

        sleep(1)
        skipButton2.tap()
        XCTAssertTrue(howToStashRow.waitForExistence(timeout: 10),
                      "Expected to return to Settings after 'Skip'")
    }

    // MARK: - Plan 15, Task 3: whole-card taps (DESIGN.md §Components "Card note", iOS note)

    /// Inserts throwaway rows straight into `items` (PostgREST, RLS: `user_id == auth.uid()`),
    /// in order, ~150 ms apart so each gets a later `created_at` than the one before — the LAST
    /// row becomes the newest card. Direct inserts rather than `add-note`: this lapsed account's
    /// `add-note` answers 403 `subscription_required` (see `testCaptureSmoke`'s standing-failure
    /// note), and a plain insert triggers no enrichment, so titles stay exactly as seeded. Every
    /// caller deletes what it inserts (`deleteRow(id:)`) on every exit path.
    private func insertThrowawayItems(_ rows: [[String: Any]], email: String, password: String) async throws -> [String] {
        var authRequest = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/auth/v1/token")
                .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        authRequest.httpMethod = "POST"
        authRequest.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        authRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authRequest.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (authData, authResponse) = try await URLSession.shared.data(for: authRequest)
        guard let authHTTP = authResponse as? HTTPURLResponse, (200..<300).contains(authHTTP.statusCode),
              let authObject = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let token = authObject["access_token"] as? String,
              let user = authObject["user"] as? [String: Any],
              let userId = user["id"] as? String
        else {
            throw FixtureRepairError("test-account auth failed while seeding throwaway rows")
        }

        var ids: [String] = []
        for row in rows {
            var body = row
            body["user_id"] = userId
            body["is_public"] = false
            body["attributes"] = body["attributes"] ?? [String: Any]()
            var request = URLRequest(url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items"))
            request.httpMethod = "POST"
            request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let inserted = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let id = inserted.first?["id"] as? String
            else {
                for id in ids { try? await deleteRow(id: id, email: email, password: password) }
                throw FixtureRepairError(
                    "direct items insert failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
            }
            ids.append(id)
            try await Task.sleep(for: .milliseconds(150))
        }
        return ids
    }

    /// Password-grant session for the test account: its access token and user id (for REST
    /// calls that need the owner's folder or id, e.g. Storage paths `<uid>/…`).
    private func testAccountSession(email: String, password: String) async throws -> (token: String, userId: String) {
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/auth/v1/token")
                .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await Self.restData(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              let user = object["user"] as? [String: Any], let userId = user["id"] as? String
        else {
            throw FixtureRepairError("test-account auth failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        return (token, userId)
    }

    /// `URLSession.shared.data(for:)` for the tests' own REST bookkeeping, retried (3 tries, 1 s
    /// apart) on a transport error: a one-off network blip (seen: -1017 "cannot parse response")
    /// must not fail the test it serves. Every request routed here is idempotent (auth, reads,
    /// deletes).
    private static func restData(for request: URLRequest) async throws -> (Data, URLResponse) {
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

    /// A `width`×`height` image (a two-tone diagonal, so a hero isn't a flat block) as JPEG or PNG.
    private func generatedImage(width: Int, height: Int, png: Bool) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor(red: 0.42, green: 0.36, blue: 0.91, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(red: 0.96, green: 0.62, blue: 0.35, alpha: 1).setFill()
            let path = UIBezierPath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: 0))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.close()
            path.fill()
        }
        return (png ? image.pngData() : image.jpegData(compressionQuality: 0.8)) ?? Data()
    }

    /// Uploads `images` to `stash-media/<test-uid>/<folder>/<name>` (the test account's own
    /// storage folder — RLS allows the owner to write and delete there) and returns their paths.
    /// Callers delete them with `deleteStorageObjects` in a teardown block.
    private func uploadThrowawayImages(_ images: [(name: String, data: Data, contentType: String)], folder: String,
                                       email: String, password: String) async throws -> [String] {
        let (token, userId) = try await testAccountSession(email: email, password: password)
        var paths: [String] = []
        for image in images {
            let path = "\(userId)/\(folder)/\(image.name)"
            var request = URLRequest(url: Self.fixtureRepairBaseURL.appending(path: "/storage/v1/object/stash-media/\(path)"))
            request.httpMethod = "POST"
            request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(image.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("true", forHTTPHeaderField: "x-upsert")
            let (_, response) = try await URLSession.shared.upload(for: request, from: image.data)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                try? await deleteStorageObjects(paths, email: email, password: password)
                throw FixtureRepairError("test image upload failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
            }
            paths.append(path)
        }
        return paths
    }

    private func deleteStorageObjects(_ paths: [String], email: String, password: String) async throws {
        guard !paths.isEmpty else { return }
        let (token, _) = try await testAccountSession(email: email, password: password)
        var request = URLRequest(url: Self.fixtureRepairBaseURL.appending(path: "/storage/v1/object/stash-media"))
        request.httpMethod = "DELETE"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prefixes": paths])
        let (_, response) = try await Self.restData(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError("test image cleanup failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
    }

    // MARK: - Share-extension helpers (plan 15, Task 4)

    /// Every item whose note is `marker`: a URL share stores its note in `supplemental_note`
    /// (`add-url`), other kinds in `content` — both are checked.
    private func itemsWithNote(_ marker: String, email: String, password: String) async throws -> [[String: Any]] {
        let (token, _) = try await testAccountSession(email: email, password: password)
        var rows: [String: [String: Any]] = [:]
        for column in ["supplemental_note", "content"] {
            var request = URLRequest(
                url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                    .appending(queryItems: [URLQueryItem(name: column, value: "eq.\(marker)"),
                                            URLQueryItem(name: "select", value: "id,url,type")]))
            request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await Self.restData(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw FixtureRepairError("note lookup failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
            }
            for row in (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? [] {
                if let id = row["id"] as? String { rows[id] = row }
            }
        }
        return Array(rows.values)
    }

    /// Polls `itemsWithNote` until at least one row exists (or `timeout`), then returns them all.
    private func waitForItemsWithNote(_ marker: String, email: String, password: String,
                                      timeout: TimeInterval) async throws -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let rows = try await itemsWithNote(marker, email: email, password: password)
            if !rows.isEmpty { return rows }
            try? await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return []
    }

    /// Deletes a shared item AND its `capture_receipts` row (the receipt is the capture's other
    /// server-side trace; its `item_id` would be nulled, not removed, by deleting the item first).
    private func deleteSharedItem(id: String, email: String, password: String) async throws {
        let (token, _) = try await testAccountSession(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/capture_receipts")
                .appending(queryItems: [URLQueryItem(name: "item_id", value: "eq.\(id)")]))
        request.httpMethod = "DELETE"
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await Self.restData(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError("receipt cleanup failed for \(id)")
        }
        try await deleteRow(id: id, email: email, password: password)
    }

    /// Opens `url` in Safari, shares it to Stash and types `note` into the compose card; returns
    /// the card's Save button. (Same recipe as `testShareExtensionURLSmoke`.) With `checkpoint`,
    /// the card is held for a screenshot (`SCREENSHOT_CHECKPOINT: <checkpoint>`) before the note
    /// field takes focus and the keyboard covers it.
    @MainActor
    private func openStashComposeCard(in safari: XCUIApplication, url: String, note: String?,
                                      checkpoint: String? = nil) -> XCUIElement {
        safari.launch()
        let addressBar = safari.textFields["TabBarItemTitle"]
        XCTAssertTrue(addressBar.waitForExistence(timeout: 10), "Safari address bar not found")
        addressBar.tap()
        let urlField = safari.textFields["URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), "Safari URL edit field not found after tapping the address bar")
        urlField.typeText("\(url)\n")
        // Newer Safari toolbars (wider phones, iOS 26) fold Share into the "•••" More menu — try
        // the bare button first, then the menu (same fallback as StoreScreenshotsUITests).
        let shareButton = safari.buttons["ShareButton"]
        if !shareButton.waitForExistence(timeout: 8) {
            let moreButton = safari.buttons["MoreMenuButton"]
            XCTAssertTrue(moreButton.waitForExistence(timeout: 10), "Neither Safari's Share button nor its More menu appeared")
            // iOS 26 Safari's first launch shows a "… in the ••• menu" tip over the toolbar: the
            // first tap on ••• only dismisses it, so tap until the menu (and Share) shows.
            for _ in 0..<3 where !shareButton.exists {
                moreButton.tap()
                _ = shareButton.waitForExistence(timeout: 4)
            }
            XCTAssertTrue(shareButton.exists, "Expected a Share entry inside Safari's More menu")
        }
        shareButton.tap()
        let stashCell = safari.cells["Stash"]
        XCTAssertTrue(stashCell.waitForExistence(timeout: 20), "Stash did not appear in the share sheet")
        stashCell.tap()
        XCTAssertTrue(safari.staticTexts["share.preview.url"].waitForExistence(timeout: 20),
                      "Compose card's URL preview did not render")
        // The vertical-axis note field surfaces as a TextView on iOS 17 and a TextField on iOS 26.
        let noteAsTextView = safari.textViews["share.note"], noteAsTextField = safari.textFields["share.note"]
        let noteDeadline = Date().addingTimeInterval(10)
        while Date() < noteDeadline, !noteAsTextView.exists, !noteAsTextField.exists { usleep(250_000) }
        let noteField = noteAsTextView.exists ? noteAsTextView : noteAsTextField
        XCTAssertTrue(noteField.exists, "Compose card's note field did not render")
        let saveButton = safari.buttons["share.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Compose card's Save button did not render")
        if let checkpoint {
            sleep(1)
            attachScreenshot(named: checkpoint)
            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: \(checkpoint)\n".data(using: .utf8)!)
        }
        guard let note else { return saveButton }
        // The card's text view sits in a remote (extension) view: tapped too soon after the card
        // appears (observed: ~1 s) it never takes keyboard focus, even on re-taps; after ~3 s it
        // does on the first tap (the original smoke's path spends that long on other checks).
        sleep(3)
        tapUntilFocused(noteField)
        noteField.typeText(note)
        return saveButton
    }

    /// Waits until the Stash compose card (its Save button and its confirmation) is gone.
    @MainActor
    private func waitForShareCardGone(in safari: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !safari.buttons["share.save"].exists, !safari.staticTexts["share.outcome"].exists { return true }
            usleep(250_000)
        }
        return false
    }

    /// A full-screen screenshot kept in the test's result bundle (exported for reports).
    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Every item whose `url` contains `fragment` (a URL share without a note).
    private func itemsWithURL(containing fragment: String, email: String, password: String) async throws -> [[String: Any]] {
        let (token, _) = try await testAccountSession(email: email, password: password)
        var request = URLRequest(
            url: Self.fixtureRepairBaseURL.appending(path: "/rest/v1/items")
                .appending(queryItems: [URLQueryItem(name: "url", value: "like.*\(fragment)*"),
                                        URLQueryItem(name: "select", value: "id,url,type")]))
        request.setValue(Self.fixtureRepairAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await Self.restData(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FixtureRepairError("url lookup failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// Polls `itemsWithURL` until at least one row exists (or `timeout`), then returns them all.
    private func waitForItemsWithURL(containing fragment: String, email: String, password: String,
                                     timeout: TimeInterval) async throws -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let rows = try await itemsWithURL(containing: fragment, email: email, password: password)
            if !rows.isEmpty { return rows }
            try? await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return []
    }

    /// Taps `field` until it has keyboard focus (a tap can land on an overlay that is still
    /// fading out — the launch splash — or on a remote view that isn't ready yet).
    @MainActor
    private func tapUntilFocused(_ field: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts {
            field.tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            if XCTWaiter().wait(for: [focused], timeout: 1.5) == .completed { return }
        }
    }

    /// Launches the app with `arguments` (plus `--uitest-reset-auth`) and signs the test account
    /// in. Tolerates a launch that restores the (same) stored session instead of showing sign-in —
    /// the reset occasionally loses a race with the auth client's initial-session refresh.
    @MainActor
    private func launchSignedIn(_ app: XCUIApplication, arguments: [String], email: String, password: String) {
        app.launchArguments = ["--uitest-reset-auth"] + arguments
        app.launch()
        let emailField = app.textFields["signin.email"]
        let viewTab = app.tabBars.buttons["View"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !emailField.exists, !viewTab.exists { usleep(250_000) }
        var signedIn = false
        if emailField.exists {
            tapUntilFocused(emailField)
            emailField.typeText(email)
            let passwordField = app.secureTextFields["signin.password"]
            tapUntilFocused(passwordField)
            passwordField.typeText(password)
            app.buttons["signin.submit"].tap()
            signedIn = true
        }
        XCTAssertTrue(viewTab.waitForExistence(timeout: 15), "Expected to be signed in")
        // Plan 16: iOS 26's "Save Password?" sheet, declined with the canonical helper.
        if signedIn { A11yScreens.dismissSavePasswordPrompt(app) }
    }

    /// Taps Save and measures how long the confirmation takes to appear, polling as tightly as
    /// XCUITest allows (it is only on screen ~0.8 s). Returns the seconds from just before the
    /// tap to the first snapshot that showed it, and its text — or `nil` if never seen.
    @MainActor
    private func tapSaveAndTimeConfirmation(_ saveButton: XCUIElement, in safari: XCUIApplication,
                                            within timeout: TimeInterval = 4,
                                            screenshot: String? = nil)
        -> (seconds: TimeInterval, text: String, measuredMs: Int?)? {
        let outcome = safari.staticTexts["share.outcome"]
        let tapped = Date()
        saveButton.tap()
        while Date().timeIntervalSince(tapped) < timeout {
            if outcome.exists {
                let seconds = Date().timeIntervalSince(tapped)
                // The DEBUG extension's own Save → confirmation measurement ("<n> ms").
                let measured = (outcome.value as? String)?.split(separator: " ").first.flatMap { Int($0) }
                if let screenshot { attachScreenshot(named: screenshot) }
                return (seconds, outcome.label, measured)
            }
        }
        return nil
    }

    /// Will (plan 15): "when tapping the bottom of the first item in the list, it often chooses the
    /// second item by mistake ... We should just make the entirety of the cards tappable". Root
    /// cause: a `.fill`-scaled hero image — and the 1.25× blurred backdrop behind a portrait photo
    /// — overflows its clipped zone; `.clipped()` clips drawing, not hit testing, and each card is
    /// drawn above the one before it, so card N+1's hero swallowed taps on the bottom of card N.
    /// Reproduced 5/5 on the pre-fix build (task-3 report).
    ///
    /// Seeds five throwaway rows (`UITEST-TAP:`) so the top five cards are, top to bottom: a text
    /// card, a portrait photo (tall hero, backdrop overflows ~190pt up), a square photo (cover,
    /// ~100pt overflow), a link with a portrait preview (cover, ~240pt overflow) and another
    /// portrait photo — every card but the first sits under an overflowing neighbour. Waits for
    /// every hero to finish loading (the overflow only exists once an image is drawn), then taps
    /// 5pt above each card's bottom edge (inside its bottom 10pt: the footer's type chip + the
    /// card's 24pt bottom padding) and asserts the detail sheet that opens is THAT card's, by
    /// title. Deletes its rows on every exit path; never touches `UITEST-FIXTURE` rows.
    @MainActor
    func testCardBottomEdgeTapOpensThatCard() async throws {
        let (email, password) = try testCredentials()
        let epoch = Int(Date().timeIntervalSince1970)
        func title(_ index: Int) -> String { "UITEST-TAP: \(index) \(epoch)" }
        // The hero images this test needs, generated here and uploaded to the TEST account's own
        // storage folder (deleted again in teardown): a 1200×1600 portrait JPEG, a 1024×1024 PNG,
        // and a 361×640 portrait link preview — only their shapes matter.
        let images = try await uploadThrowawayImages([
            ("portrait.jpg", generatedImage(width: 1200, height: 1600, png: false), "image/jpeg"),
            ("square.png", generatedImage(width: 1024, height: 1024, png: true), "image/png"),
            ("preview.jpg", generatedImage(width: 361, height: 640, png: false), "image/jpeg"),
        ], folder: "uitest-tap-\(epoch)", email: email, password: password)
        addTeardownBlock {
            try? await self.deleteStorageObjects(images, email: email, password: password)
        }
        let portrait = images[0], square = images[1], portraitPreview = images[2]
        // Oldest first: the last row inserted is card 0.
        let rows: [[String: Any]] = [
            ["type": "image", "title": title(4), "file_path": portrait, "mime_type": "image/jpeg"],
            ["type": "link", "title": title(3), "file_path": portraitPreview, "url": "https://example.com/uitest-tap"],
            ["type": "image", "title": title(2), "file_path": square, "mime_type": "image/png"],
            ["type": "image", "title": title(1), "file_path": portrait, "mime_type": "image/jpeg"],
            ["type": "text", "title": title(0), "content": ""],
        ]
        let ids = try await insertThrowawayItems(rows, email: email, password: password)
        // A teardown block runs even when an assertion below stops the test (`continueAfterFailure
        // = false` ends the method without unwinding into any Swift `catch`), so these rows can't
        // leak the way plan 14's `UITEST-CARDNOTE:` rows did. (Teardown blocks run last-added
        // first: the rows go before the images they point at.)
        addTeardownBlock {
            for id in ids { try? await self.deleteRow(id: id, email: email, password: password) }
        }

        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func card(_ index: Int) -> XCUIElement { app.descendants(matching: .any)["card.\(index)"] }
        for index in 0..<5 {
            XCTAssertTrue(card(index).waitForExistence(timeout: 20), "Expected card.\(index)")
            // Plan 15: the View tab first shows the disk-cached page (whatever the previous run
            // left), then the refreshed one — wait for the refreshed page to put the seeded row
            // here rather than reading the label once.
            let seeded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", title(index)),
                                                   object: card(index))
            XCTAssertEqual(XCTWaiter().wait(for: [seeded], timeout: 30), .completed,
                           "Expected card.\(index) to be the seeded '\(title(index))', got '\(card(index).label)'")
        }
        // The overflow only exists once each hero is drawn — wait for all four.
        for (index, hero) in [(1, "card.hero.tall"), (2, "card.hero.cover"), (3, "card.hero.cover"), (4, "card.hero.tall")] {
            XCTAssertTrue(card(index).descendants(matching: .any)[hero].waitForExistence(timeout: 20),
                          "Expected card.\(index)'s \(hero) to load")
        }
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: tap-grid\n".data(using: .utf8)!)
        sleep(2)

        let tabBarTop = app.tabBars.firstMatch.frame.minY
        for index in 0..<5 {
            // 5pt above the card's bottom edge: its footer (type chip) + 24pt bottom padding.
            func bottomTapY() -> CGFloat {
                card(index).descendants(matching: .any)["card.typeChip"].frame.maxY + 24 - 5
            }
            // Scroll (slow drag, no fling) until that point is on screen above the tab bar.
            for _ in 0..<5 where bottomTapY() > tabBarTop - 40 {
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: tabBarTop - 60))
                let lift = min(bottomTapY() - (tabBarTop - 160), 360)
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -lift)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            let frame = card(index).frame
            let tapY = bottomTapY()
            XCTAssertTrue(tapY < frame.maxY && tapY > frame.maxY - 10,
                          "Tap point \(tapY) should sit in card.\(index)'s bottom 10pt (frame \(frame))")
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: tapY)).tap()

            let detailTitle = app.descendants(matching: .any)["detail.title"]
            XCTAssertTrue(detailTitle.waitForExistence(timeout: 10), "No detail sheet after tapping card.\(index)'s bottom edge")
            XCTAssertEqual(detailTitle.value as? String, title(index),
                           "Tapping the bottom edge of card.\(index) opened a different card")
            app.buttons["detail.done"].tap()
            XCTAssertTrue(card(index).waitForExistence(timeout: 10), "Expected the grid back after closing the sheet")
            sleep(1)
        }
    }

    // MARK: - Transcribe with speakers + Notes editor footprint (Plan 14 Task 2)

    /// "Transcribe again" only appears in the Transcript section header for items with a
    /// stored media file — asserted against the two permanent UITEST-FIXTURE rows `testDetailSheets`
    /// already relies on (`audio one`/`link one`, found by the same unique-substring search, never
    /// grid position), so this never seeds or mutates any row. Also asserts the Notes editor's own
    /// rendered accessibility frame sits inside the halved 44–110pt footprint (Plan 14 Task 2 —
    /// previously 80–220pt), proving the `@ScaledMetric` frame change actually reads through to a
    /// real laid-out view, not just that it compiles.
    ///
    /// Deliberately doesn't tap the button itself: doing so would call the REAL `transcribe-audio`
    /// function against the permanent "audio one" fixture's real recording, exactly what this
    /// task's brief says never to do ("fixture rows are permanent... their transcript must not
    /// change"). Presence/absence + the busy-vs-idle label text it's capable of are enough to prove
    /// the wiring without ever tapping it live.
    func testTranscribeWithSpeakersButtonAndFootprint() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        func openDetail(search: String) {
            searchLibrary(app, for: search, cardTitled: "UITEST-FIXTURE: \(search)").tap()
            XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10),
                          "Detail sheet did not present for '\(search)'")
        }

        func closeDetailAndClearSearch(_ search: String) {
            app.buttons["detail.done"].tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
            clearLibrarySearch(app)
        }

        // 1. "audio one" — a stored recording — shows the button, and the Notes editor's
        // rendered height sits inside the new halved footprint.
        openDetail(search: "audio one")

        let transcribeButton = app.buttons["detail.transcribeSpeakers"]
        XCTAssertTrue(transcribeButton.waitForExistence(timeout: 10),
                      "Expected 'Transcribe again' on an audio item with a stored media file")
        XCTAssertEqual(transcribeButton.label, "Transcribe again",
                       "Expected the idle label — this test never taps the button, so it should never read 'Transcribing…'")

        let notesEditor = anyElement("detail.notes.editor")
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 5), "Expected the Notes editor to render")
        let editorHeight = notesEditor.frame.height
        XCTAssertGreaterThanOrEqual(editorHeight, 40,
                                    "Expected the halved editor's ~44pt floor, got \(editorHeight)")
        XCTAssertLessThanOrEqual(editorHeight, 130,
                                 "Expected the halved editor's ~110pt ceiling (previously up to 220pt), got \(editorHeight)")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: transcribe-button\n".data(using: .utf8)!)
        sleep(2)

        closeDetailAndClearSearch("audio one")

        // 2. "link one" — no stored media file at all — never shows the button.
        openDetail(search: "link one")
        XCTAssertFalse(app.buttons["detail.transcribeSpeakers"].exists,
                       "Did not expect 'Transcribe again' on a link item")
        closeDetailAndClearSearch("link one")
    }

}
