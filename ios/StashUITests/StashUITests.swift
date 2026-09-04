import XCTest

/// Drives the real sign-in screen against production Supabase (test account creds are
/// injected via TEST_RUNNER_ environment variables, never hardcoded). Covers both the
/// wrong-password error path and the successful sign-in path in one launch so the two
/// scenarios can't drift out of order across reruns.
final class StashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
    @discardableResult
    private func signInAndReachLibrary(_ app: XCUIApplication, email: String, password: String) -> Bool {
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        let emailField = app.textFields["signin.email"]
        guard emailField.waitForExistence(timeout: 10) else { return false }
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        let viewTab = app.tabBars.buttons["View"]
        let reached = viewTab.waitForExistence(timeout: 15)
        if reached { viewTab.tap() }
        return reached
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

        // 2. Local search narrows to nothing for an unmatchable query, then clears back.
        // (Type chips and the tag filter are gone — the 2026-08-28 UI pass removed the chip
        // row and hid tags from the View tab entirely, pending product-wide tag deprecation.
        // Search is the custom pill field now, a plain text field, not `.searchable` — so no
        // system "Cancel" button appears and no dismissal dance is needed.)
        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.tap()
        let needle = "zzzunmatchablezzz"
        searchField.typeText(needle)
        XCTAssertTrue(anyElement("library.empty").waitForExistence(timeout: 10), "Expected an empty state for an unmatchable search")
        XCTAssertFalse(anyElement("card.0").exists, "No cards should be visible for an unmatchable search")

        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: needle.count))
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected cards to return after clearing the search")

        // The pill field spawns no system Cancel button (unlike `.searchable`), so the keyboard
        // would still be covering the tab bar here — return ("Search") dismisses it.
        searchField.typeText("\n")

        // 5. Sign out via the Settings tab (Task 7: relocated from the library toolbar's avatar
        // menu, which no longer exists — `library.menu`/`library.signOut` are gone).
        app.tabBars.buttons["Settings"].tap()
        let signOutButton = app.buttons["settings.signout"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 10), "Sign Out row not found in Settings")
        signOutButton.tap()

        let confirmButton = app.buttons["settings.signout.confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Sign-out confirmation dialog did not appear")
        confirmButton.tap()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10), "Expected the sign-in screen after signing out")
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

        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        func openAndCheck(search: String, expectedTabs: [String], forbiddenTabs: [String],
                           checkpoint: String, extra: () -> Void = {}) {
            searchField.tap()
            searchField.typeText(search)
            XCTAssertTrue(card0().waitForExistence(timeout: 10), "Expected a card for search '\(search)'")
            // Task 7: a plain `.tap()` (XCUITest's geometric center of the card) can land on the
            // link kicker's own tap target now that one exists — for a card as compact as the
            // `example.com` fixture (short favicon-plate hero + one-line description, no
            // annotation), the card's vertical center sits almost exactly on the kicker's single
            // line, so the tap opens Safari instead of this sheet (bisected live: dy 0.30-0.45
            // and 0.55-0.70 all open the sheet; only dy≈0.50 hits the kicker and backgrounds the
            // app). A near-bottom offset reliably clears the kicker for every type this loop
            // searches (link/text/image/audio all place their footer there).
            card0().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()

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
            searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: search.count))
        }

        openAndCheck(search: "link one", expectedTabs: ["Summary", "Original Content", "Notes"],
                     forbiddenTabs: ["Transcript"], checkpoint: "link")

        // Plan 7 Task 6: pill tabs only render when a type has more than one
        // (`ItemDetailContent.sectionHead`, web parity — `EditItemContentSection.tsx`'s own
        // `config.tabs.length > 1` gate). Single-"Notes"-tab types (text/image) now show the
        // "NOTES" micro-label with no tab buttons at all, not a lone "Notes" button.
        openAndCheck(search: "note one", expectedTabs: [],
                     forbiddenTabs: ["Summary", "Original Content", "Transcript", "Notes"], checkpoint: "text")

        openAndCheck(search: "image one", expectedTabs: [],
                     forbiddenTabs: ["Summary", "Original Content", "Transcript", "Notes"], checkpoint: "image")

        openAndCheck(search: "audio one", expectedTabs: ["Notes", "Transcript"],
                     forbiddenTabs: ["Summary", "Original Content"], checkpoint: "audio") {
            app.buttons["Transcript"].tap()
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

        /// Narrows the grid to one fixture via a unique local-search substring (never grid
        /// position — same reasoning `testDetailSheets` documents), waits for its card, runs
        /// `assert`, screenshots, then clears the search back out and waits for the grid to
        /// return before the next iteration types into the (shared) field — same clear-then-
        /// confirm technique `testLibrarySmoke`'s own search step already established.
        func isolateAndCheck(search: String, checkpoint: String, assert: () -> Void) {
            searchField.tap()
            searchField.typeText(search)
            XCTAssertTrue(card0().waitForExistence(timeout: 10), "Expected a card for search '\(search)'")

            assert()

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: anatomy-\(checkpoint)\n".data(using: .utf8)!)
            sleep(2)

            searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: search.count))
            XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the grid back after clearing '\(search)'")
        }

        // 1. Repo link (Task 9 fixture) → dark repo plate, mono "owner/repo" label.
        isolateAndCheck(search: "repo link", checkpoint: "repo") {
            let plate = anyElement("card.repoplate")
            XCTAssertTrue(plate.waitForExistence(timeout: 10), "Expected a repo plate for the repo-link fixture")
            XCTAssertTrue(plate.label.contains("supabase/supabase-swift"),
                          "Expected the repo plate's label to contain 'supabase/supabase-swift', got '\(plate.label)'")
        }

        // 2. Located note (Task 9 fixture) → footer location badge, "posted from <label>".
        isolateAndCheck(search: "located note", checkpoint: "location") {
            let location = anyElement("card.location")
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
        isolateAndCheck(search: "video link", checkpoint: "video") {
            let tallHero = anyElement("card.hero.tall")
            let favicon = anyElement("card.faviconplate")
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
        isolateAndCheck(search: "document one", checkpoint: "document") {
            let plate = anyElement("card.fileplate")
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
        func clearField(_ field: XCUIElement, placeholder: String) {
            for _ in 0..<5 {
                let current = (field.value as? String) ?? ""
                if current.isEmpty || current == placeholder { return }
                field.tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
        }

        func replaceText(_ field: XCUIElement, placeholder: String, with newValue: String) {
            clearField(field, placeholder: placeholder)
            field.tap()
            field.typeText(newValue)
        }

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText("note one")
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected a card for 'note one'")
        card0().tap()

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
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the edited card to still be findable")
        card0().tap()

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

        XCTAssertTrue(card0().waitForExistence(timeout: 15),
                      "Expected the card to still be findable after the immediate-dismiss round trip")
        card0().tap()

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

    /// Delete flow: creates a disposable item via the add-note REST endpoint before this test
    /// runs (never touches the permanent UITEST-FIXTURE rows — see task-8-report.md for the
    /// exact seed/verify commands), opens it from the grid, deletes it through the in-app
    /// confirmation dialog, and asserts it's gone from the grid. Absence from the server is
    /// verified separately via REST in the shell after this test runs.
    func testDeleteSmoke() throws {
        guard let marker = ProcessInfo.processInfo.environment["STASH_DELETE_MARKER"], !marker.isEmpty else {
            XCTFail("STASH_DELETE_MARKER was not set — seed a disposable item via REST before running this test")
            throw XCTSkip("missing STASH_DELETE_MARKER")
        }
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText(marker)
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the disposable item's card to appear")
        card0().tap()

        let deleteButton = app.buttons["detail.delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Delete button not found in detail sheet")
        deleteButton.tap()

        let confirmButton = app.buttons["Delete"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Delete confirmation dialog did not appear")
        confirmButton.tap()

        XCTAssertTrue(anyElement("library.empty").waitForExistence(timeout: 15),
                      "Expected no results for the deleted item's marker search after deletion")
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
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText("note two")
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected a card for 'note two'")
        card0().tap()

        XCTAssertTrue(anyElement("detail.done").waitForExistence(timeout: 10), "Detail sheet did not present")

        // --- Public toggle ON, sticky note text, toggle OFF (un-share confirm since a sticky
        // note is now present), assert the sticky field disappears once confirmed. ---
        let publicToggle = anyElement("detail.public.toggle")
        XCTAssertTrue(publicToggle.waitForExistence(timeout: 10), "Public toggle not found")
        publicToggle.tap()

        let stickyField = anyElement("detail.public.sticky")
        XCTAssertTrue(stickyField.waitForExistence(timeout: 10), "Sticky note field did not appear after enabling public")
        stickyField.tap()
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

    /// Ask tab: streaming Q&A against production (one real model call per attempt — normally one
    /// per run, two on the RAG-variance retry path below; expected and budgeted), citation chip,
    /// detail sheet. Deliberately does NOT assume `ask.bubble.0` is the user question /
    /// `ask.bubble.1` is the assistant reply: chat history is durable (Task 2 persists every
    /// exchange to `conversations`/`messages`), so a second run of this same test against the
    /// same account restores prior turns first and appends after them — the indices this run
    /// lands on depend on how much history already exists. Instead this finds whichever
    /// `ask.bubble.*`/`ask.sources.*` elements are LAST in the tree right after sending, which are
    /// always the freshly-appended ones regardless of any earlier accumulated history.
    ///
    /// Asks about the permanent document fixture ("persimmons") per the plan's own note that its
    /// extracted `page_body` guarantees retrievable content, so a source chip is expected. Includes
    /// a one-shot RAG-variance retry (Task 8 hardening) — see the comment at its call site below.
    func testAskSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        app.tabBars.buttons["Ask"].tap()

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
            input.tap()
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
            let assistantBubble = anyElement(bubbleId)

            // Poll for the bubble's label to stabilize (stream completion), capped at 30s total.
            var previousLabel: String?
            var stableStreak = 0
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                let currentLabel = assistantBubble.label
                let meaningful = currentLabel.trimmingCharacters(in: .whitespaces)
                if !meaningful.isEmpty, currentLabel == previousLabel {
                    stableStreak += 1
                    if stableStreak >= 3 { break }   // stable across 3 consecutive 0.5s polls (~1.5s quiet)
                } else {
                    stableStreak = 0
                }
                previousLabel = currentLabel
                usleep(500_000)
            }
            let finalLabel = assistantBubble.label.trimmingCharacters(in: .whitespaces)
            XCTAssertFalse(finalLabel.isEmpty, "Expected a non-empty assistant answer")
            return bubbleId
        }

        func sourcesRow(forBubble bubbleId: String) -> XCUIElement {
            anyElement("ask.sources.\(bubbleId.replacingOccurrences(of: "ask.bubble.", with: ""))")
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
        if !sourcesRow(forBubble: bubbleId).waitForExistence(timeout: 10) {
            bubbleId = askAndAwaitStableReply(question)
            XCTAssertTrue(
                sourcesRow(forBubble: bubbleId).waitForExistence(timeout: 10),
                "Expected at least one source chip for the persimmons question — sourceless on both the initial attempt and the RAG-variance retry")
        }

        // Screenshot rig (same checkpoint technique as testDetailSheets/testPublicSmoke):
        // holds here so an external `xcrun simctl io <udid> screenshot` can capture the streamed
        // answer with its source chip(s) visible before this test moves on to tapping one.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: ask\n".data(using: .utf8)!)
        sleep(3)

        // ≥1 source chip, derived from the SAME bubble's index (not assumed/hardcoded) — whichever
        // attempt (initial or retry) actually produced sources.
        let indexSuffix = bubbleId.replacingOccurrences(of: "ask.bubble.", with: "")
        let firstChip = anyElement("ask.sources.\(indexSuffix).chip.0")
        XCTAssertTrue(firstChip.waitForExistence(timeout: 5), "Expected a tappable source chip")
        firstChip.tap()

        let done = app.buttons["detail.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for the tapped source")
        done.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Expected the Ask tab after dismissing the detail sheet")
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
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5), "Expected a Notes tab for the voice note")
        XCTAssertTrue(app.buttons["Transcript"].waitForExistence(timeout: 5),
                      "Expected a Transcript tab — the signal that this card is type audio")
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

    /// One-shot existence check for `testShareExtensionURLSmoke`'s gate-CLOSED branch. Unlike
    /// `pollForRow` above (which retries until a row APPEARS — correct for "this save should have
    /// landed eventually"), a gate-blocked Save must never create a row AT ALL, so there is nothing
    /// to wait for: the correct check for an expected ABSENCE is a single fetch, taken only after
    /// the caller has already given the (non-)event a generous settle window — polling-until-absent
    /// would just race a save that was never going to happen, and could only ever time out, not
    /// confirm anything sooner.
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

        let searchField = app.textFields["library.search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText(marker)
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected a card for the seeded location item")
        card0().tap()

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

        // Let SubscriptionStore.refresh() resolve + write the gate cache before switching to
        // Safari — see doc comment above.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.subscription.status"].waitForExistence(timeout: 15),
                      "Subscription status line not found")
        sleep(3)

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()

        let addressBar = safari.textFields["TabBarItemTitle"]
        XCTAssertTrue(addressBar.waitForExistence(timeout: 10), "Safari address bar not found")
        addressBar.tap()
        let urlField = safari.textFields["URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5),
                      "Safari URL edit field not found after tapping the address bar")
        urlField.typeText("example.com\n")

        let shareButton = safari.buttons["ShareButton"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 15), "Safari's Share button did not appear")
        shareButton.tap()

        // Springboard/activity-sheet timing is the finicky part (brief) — budgeted generously.
        // Stash appeared in the first row with no "More" step in every prior live check (T5/T7).
        let stashCell = safari.cells["Stash"]
        XCTAssertTrue(stashCell.waitForExistence(timeout: 20), "Stash did not appear in the share sheet")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: share-sheet\n".data(using: .utf8)!)
        sleep(2)

        stashCell.tap()

        // --- Unconditional pre-gate flow: the compose card renders with the URL preview + note
        // field, regardless of gate state. ---
        let urlPreview = safari.staticTexts["share.preview.url"]
        XCTAssertTrue(urlPreview.waitForExistence(timeout: 20), "Compose card's URL preview did not render")
        XCTAssertTrue(urlPreview.label.contains("example.com"),
                      "Expected the URL preview to reference example.com, got '\(urlPreview.label)'")

        let noteField = safari.textViews["share.note"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 10), "Compose card's note field did not render")

        let saveButton = safari.buttons["share.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Compose card's Save button did not render")

        // Plan 7 Task 2: the extension-side font proof — an appex has its own bundle (separate
        // from the host app's), so this is the only way to confirm PP Neue Montreal actually
        // registered INSIDE the running share-extension process, not just the app's.
        let fontStatus = safari.descendants(matching: .any)["share.fontStatus"]
        XCTAssertTrue(fontStatus.waitForExistence(timeout: 5), "share.fontStatus label not found in the compose card")
        XCTAssertEqual(fontStatus.label, "font:neue-montreal",
                       "Expected PP Neue Montreal to load in the share-extension target, not fall back to SF Pro")

        let marker = "UITEST-SHARE: \(Int(Date().timeIntervalSince1970))"
        noteField.tap()
        noteField.typeText(marker)

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: share-compose\n".data(using: .utf8)!)
        sleep(3)

        if safari.staticTexts["share.gate"].waitForExistence(timeout: 3) {
            // --- Gate visible (this account's current lapsed-trial state): Save disabled, no item
            // created. ---
            XCTAssertFalse(saveButton.isEnabled, "Expected Save to be disabled while the gate is showing")

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: share-gate-closed\n".data(using: .utf8)!)
            sleep(3)

            safari.buttons["share.cancel"].tap()
            XCTAssertTrue(shareButton.waitForExistence(timeout: 15), "Expected to return to Safari after Cancel")

            // Generous settle window before the REST check — this is an ABSENCE assertion, so
            // there's nothing to poll-until; a fixed wait then a single check is the correct shape
            // (see `rowExists`'s own doc comment).
            sleep(5)
            let exists = try await rowExists(matchingContent: marker, email: email, password: password)
            XCTAssertFalse(exists, "Expected NO item to be created while the share-extension gate was showing")
        } else {
            // --- Gate absent (fail-open / a post-comp future): Save, REST-verify, clean up. ---
            XCTAssertTrue(saveButton.isEnabled, "Expected Save to be enabled while the gate is absent")
            saveButton.tap()

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: share-gate-open-saving\n".data(using: .utf8)!)

            // Do NOT assert on the transient "share.outcome" text — T7's own disclosed ~0.8s
            // window is too narrow to reliably catch (task-7-report.md's own Concerns section).
            // Assert on the durable REST effect instead, with a generous poll.
            let row = try await pollForRow(matchingContent: marker, email: email, password: password, timeout: 20)
            XCTAssertNotNil(row["id"], "Expected the shared URL to have landed as a real item")
            if let id = row["id"] as? String {
                try await deleteRow(id: id, email: email, password: password)
            }

            // The extension auto-dismisses ~0.8s after a successful save and hands focus back to
            // Safari — belt confirmation, not the primary assertion (which is the REST check above).
            _ = shareButton.waitForExistence(timeout: 15)
        }
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

        let confirmButton = app.buttons["settings.signout.confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Sign-out confirmation dialog did not appear")
        confirmButton.tap()

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
    /// two round icon buttons, right-aligned above the thread, with no wordmark/title above them.
    /// Same accessibility identifiers as before (`ask.newChat`/`ask.history`), so
    /// `testConversationsSmoke`'s navigation keeps working unchanged; this test proves the NEW
    /// position (above the intro bubble, not below the composer) and that the "Ask Stash" title
    /// block's item-count subtitle (`ask.itemCount`) is gone.
    func testAskHeaderButtonsOpenConversations() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        app.tabBars.buttons["Ask"].tap()

        let input = anyElement("ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")

        let newChatButton = app.buttons["ask.newChat"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 10), "New-chat header button missing")
        let historyButton = app.buttons["ask.history"]
        XCTAssertTrue(historyButton.exists, "History header button missing")

        // Above the intro bubble (the restored pre-plan-7 position), not below the composer (the
        // plan-7 footer-link position this reverses).
        let bubble = anyElement("ask.emptyState")
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "Intro bubble did not appear")
        XCTAssertLessThan(newChatButton.frame.maxY, bubble.frame.minY,
                          "Expected the new-chat button above the intro bubble")
        XCTAssertLessThan(historyButton.frame.maxY, bubble.frame.minY,
                          "Expected the history button above the intro bubble")

        // The "Ask Stash" title block (and its item-count subtitle) is gone — no wordmark, no title.
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
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText("link one")
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected a card for 'link one'")
        card0().tap()

        XCTAssertTrue(anyElement("detail.done").waitForExistence(timeout: 10), "Detail sheet did not present")

        let eyebrow = anyElement("detail.eyebrow")
        XCTAssertTrue(eyebrow.waitForExistence(timeout: 10), "Eyebrow not found")
        XCTAssertTrue(eyebrow.label.contains("LINK"), "Expected the eyebrow to read the type LINK, got '\(eyebrow.label)'")
        XCTAssertTrue(eyebrow.label.contains("example.com"),
                      "Expected the eyebrow to include the domain 'example.com', got '\(eyebrow.label)'")

        let urlBar = anyElement("detail.urlBar")
        XCTAssertTrue(urlBar.waitForExistence(timeout: 10), "URL bar not found")

        for label in ["Summary", "Original Content", "Notes"] {
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
        let titleField = anyElement("detail.title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        titleField.tap()

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

    // MARK: - Composer keyboard accessory (Plan 8 fix round 1, Task 3)

    /// Device-review fix: while typing, the keyboard toolbar's text "Done" button used to read as
    /// a second primary action competing with the violet send button. Replaced with an icon-only
    /// minimize-keyboard control (`keyboard.chevron.compact.down`) — this proves the "Done" text
    /// button is gone, the icon control appears (with an accessible label) once the editor is
    /// focused, and tapping it actually dismisses the keyboard (the accessory itself disappears,
    /// since it's only shown via the `.keyboard` toolbar placement). Also proves the composer's
    /// old public/lock toggle (`capture.toggle.public`) is gone entirely — sharing now lives only
    /// on the detail sheet's `detail.public.toggle` (see `testDetailSheets`), and captures default
    /// private (`CaptureViewModel.isPublic == false`, unchanged in StashKit by this fix). Also
    /// screenshots CaptureAttachmentsRow's clipped-× fix: picks a photo via the real PhotosPicker
    /// (the simulator's own default Photos library) and holds with the chip visible.
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

        // The composer's own lock/public toggle is gone entirely — sharing lives on the detail
        // sheet only now.
        XCTAssertFalse(anyElement("capture.toggle.public").exists,
                       "Expected the composer's public/lock toggle to be removed")

        editor.tap()
        editor.typeText("x")

        // `.buttons[...]` (not the file's usual `anyElement` helper) — the `.keyboard` toolbar
        // placement renders an extra non-button "other" accessibility container that inherits the
        // same identifier/label (confirmed live: `descendants(matching: .any)` matched two
        // elements), so this scopes the query to the actual button, same convention already used
        // for `capture.save`/`signin.submit` elsewhere in this file.
        let dismissKeyboard = app.buttons["capture.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 10),
                      "Expected the minimize-keyboard accessory control to appear while the editor is focused")
        XCTAssertEqual(dismissKeyboard.label, "Hide keyboard",
                       "Expected the accessory control's a11y label to read 'Hide keyboard', got '\(dismissKeyboard.label)'")
        XCTAssertFalse(app.buttons["Done"].exists,
                       "Expected the keyboard toolbar's text 'Done' button to be gone")

        // Screenshot rig (same checkpoint technique as testCaptureSmoke/testLocationPinSmoke):
        // holds here, keyboard up with "x" typed, so an external `xcrun simctl io <udid>
        // screenshot` can capture the violet send button (primary) alongside the icon-only
        // minimize accessory (secondary) — no competing "Done" text button.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: composer-keyboard\n".data(using: .utf8)!)
        sleep(3)

        dismissKeyboard.tap()

        let accessoryGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                        object: dismissKeyboard)
        XCTAssertEqual(XCTWaiter().wait(for: [accessoryGone], timeout: 10), .completed,
                       "Expected the keyboard accessory to disappear once the keyboard is dismissed")

        // Attachment × clipping fix (CaptureAttachmentsRow): drives the real PhotosPicker against
        // the simulator's own default Photos library (seeded content every sim ships with, no
        // fixture needed) rather than screenshotting manually — PHPickerViewController runs
        // out-of-process, so no photo-library permission prompt is even in the way here.
        app.buttons["capture.photosPicker"].tap()

        let firstPhoto = app.images.matching(NSPredicate(format: "label CONTAINS 'Photo'")).firstMatch
        let photoCell = firstPhoto.exists ? firstPhoto : app.scrollViews.firstMatch.images.firstMatch
        XCTAssertTrue(photoCell.waitForExistence(timeout: 10), "Expected the system photo picker to show at least one photo")
        photoCell.tap()

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

        // Same narrow-assert-clear technique `testCardAnatomySmoke`'s `isolateAndCheck` already
        // established: a unique local-search substring isolates one fixture card so
        // `card.typeChip` (a shared identifier across every card in the grid) unambiguously
        // refers to that one card's chip, never a sibling's.
        func isolateAndCheck(search: String, assert: () -> Void) {
            searchField.tap()
            searchField.typeText(search)
            XCTAssertTrue(card0().waitForExistence(timeout: 10), "Expected a card for search '\(search)'")

            assert()

            searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: search.count))
            XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the grid back after clearing '\(search)'")
        }

        // (a) Type chip present, correct label: audio fixture -> "voice note" (under the ten-
        // minute recording/voice-note threshold, CardChips.swift's `audioSubtype`), document
        // fixture -> "pdf" (lowercased extension, CardChips.swift's `typeChip(for:)`).
        isolateAndCheck(search: "audio one") {
            let chip = anyElement("card.typeChip")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Expected a type chip for the audio fixture")
            XCTAssertEqual(chip.label, "voice note", "Expected the audio fixture's type chip to read 'voice note', got '\(chip.label)'")
        }

        isolateAndCheck(search: "document one") {
            let chip = anyElement("card.typeChip")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "Expected a type chip for the document fixture")
            XCTAssertEqual(chip.label, "pdf", "Expected the document fixture's type chip to read 'pdf', got '\(chip.label)'")
        }

        // (a) Type chip absent: DESIGN.md "Photos, videos, and link covers use real imagery —
        // no field, no tint" — `typeChip(for:)` returns nil for `.link`/`.video`, which covers
        // both the repo-link and video-link fixtures (Task 9's own link-flavor fixtures).
        isolateAndCheck(search: "repo link") {
            XCTAssertFalse(anyElement("card.typeChip").exists, "Expected no type chip for the repo-link fixture")
        }

        isolateAndCheck(search: "video link") {
            XCTAssertFalse(anyElement("card.typeChip").exists, "Expected no type chip for the video-link fixture")
        }

        // The pill field spawns no system Cancel button (unlike `.searchable`), so the keyboard
        // would still be covering the tab bar here — same fix `testLibrarySmoke` documents.
        searchField.typeText("\n")

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

        // `.buttons[...]` (not `anyElement`) — same collision `testComposerKeyboardAccessory`
        // documents: the `.keyboard` toolbar placement renders an extra non-button container
        // that inherits the same identifier.
        let dismissKeyboard = app.buttons["capture.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 10), "Expected the minimize-keyboard accessory while the editor is focused")
        dismissKeyboard.tap()
        // Draft is still empty (no text was typed) — the editor losing focus alone must be
        // enough to drop the card back to idle.
        XCTAssertEqual(captureCard.value as? String, "idle", "Expected the composer card to return to idle once the (empty) editor is blurred")
    }
}
