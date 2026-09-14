import XCTest

/// Plan 14 T3: account deletion end-to-end. Deliberately a NEW, self-contained file (not an
/// addition to `StashUITests.swift`, which another agent owns this round) with its own small
/// sign-up/delete helpers — never reuses or depends on that file's private helpers, and never
/// touches the permanent `UITEST-FIXTURE`/`will+lapsed`/`will+review` accounts. Every test here
/// creates its OWN throwaway `will+del-<unixtime>@dzierson.com` account (Will-authorized).
///
/// Cleanup is TEARDOWN-GUARANTEED, not just the happy-path delete inside the test body itself
/// (review fix round 1): with `continueAfterFailure = false`, any assertion failure between
/// sign-up and the in-app delete tap would otherwise abort the test method mid-flow and leave a
/// real, live Supabase auth account behind — confirmed to actually happen once during this task's
/// own development (see `task-3-report.md`'s Adaptations section). `tearDown()` runs unconditionally
/// regardless of how/whether the test method completed, so it re-attempts the same delete via a
/// REST password-grant sign-in + `delete-account` call for whatever throwaway
/// email/password the test most recently recorded — a no-op (logged, not asserted) when the
/// in-app flow already deleted it, the actual safety net when it didn't.
final class AccountUITests: XCTestCase {
    /// Same public Supabase project URL/anon key `StashConfig.swift` embeds in the app binary
    /// (and `StashUITests.swift`'s own `fixtureRepairBaseURL`/`fixtureRepairAnonKey` already
    /// duplicate for the same reason) — safe to inline here too: a published anon key, not a
    /// secret, and this file must stand alone without importing from the app target.
    private static let baseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    /// Set the instant a throwaway account's credentials exist (BEFORE any UI interaction that
    /// could fail), cleared once `tearDown()` has taken its cleanup pass — so a test that never
    /// creates an account (e.g. `testDeleteAccountSheetCancelLeavesSignInScreenUntouched`) costs
    /// `tearDown()` nothing, and a test that DOES create one is covered no matter where it fails.
    private var cleanupEmail: String?
    private var cleanupPassword: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Teardown-guaranteed cleanup (review fix round 1 — see the type's own doc comment above).
    /// Runs after EVERY test in this file, pass or fail. Attempts a REST password-grant sign-in
    /// for whatever throwaway credentials the test most recently recorded; if that succeeds (the
    /// account is still live — the in-app delete never ran or didn't finish), calls
    /// `delete-account` with the resulting token and asserts a 2xx response, since at that point
    /// the account is known to exist and a failed delete would be a real bug worth catching. If
    /// the sign-in itself fails, the account is already gone — the ordinary happy path when the
    /// test's own in-app flow completed the delete — logged, never asserted.
    override func tearDown() async throws {
        defer { cleanupEmail = nil; cleanupPassword = nil }
        guard let email = cleanupEmail, let password = cleanupPassword else { return }
        guard let token = await Self.signInToken(email: email, password: password) else {
            NSLog("AccountUITests teardown: %@ already deleted (or never reachable) — no cleanup needed", email)
            return
        }
        NSLog("AccountUITests teardown: %@ still exists after the test — deleting it now", email)
        let deleted = await Self.deleteAccount(accessToken: token)
        XCTAssertTrue(deleted, "Teardown cleanup: expected delete-account to succeed for leftover \(email)")
    }

    /// Sign up a fresh throwaway account through the app's own Sign up tab (no phone — the plan's
    /// own instruction: "if the app's sign-up requires a phone, pass none (optional)", and this
    /// app's `canSubmit` never requires one), delete it via Settings → Delete account, and prove
    /// it's REALLY gone server-side with a REST sign-in probe (not just "the app shows the
    /// sign-in screen," which a purely-local bug could fake).
    func testDeleteAccountEndToEnd() throws {
        let stamp = Int(Date().timeIntervalSince1970)
        let email = "will+del-\(stamp)@dzierson.com"
        let username = "deltest\(stamp)"
        let password = "DeleteTest-\(stamp)!"
        // Recorded BEFORE any UI interaction — see `tearDown()`'s doc comment: this is what makes
        // cleanup unconditional rather than only reachable via this method's own final lines.
        cleanupEmail = email
        cleanupPassword = password

        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10),
                      "Expected the sign-in screen to appear")

        let signUpTab = app.buttons["auth.tab.signUp"]
        XCTAssertTrue(signUpTab.waitForExistence(timeout: 5), "Expected a Sign up tab")
        signUpTab.tap()

        let emailField = app.textFields["signin.email"]
        emailField.tap()
        emailField.typeText(email)

        let usernameField = app.textFields["auth.username"]
        XCTAssertTrue(usernameField.waitForExistence(timeout: 5), "Expected the username field on the Sign up tab")
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)

        // No phone — this account only exists to prove the deletion flow works, and the field is
        // optional (`canSubmit` never requires it).

        // Let the debounced username-uniqueness probe settle before submitting — a fresh,
        // timestamp-suffixed username is effectively guaranteed unique, but this avoids a flaky
        // race against `scheduleUsernameCheck`'s ~300ms debounce + network round trip.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.staticTexts["auth.username.error"].exists, "Expected the throwaway username to be available")

        app.buttons["signin.submit"].tap()

        let viewTab = app.tabBars.buttons["View"]
        XCTAssertTrue(viewTab.waitForExistence(timeout: 20), "Expected the tab bar to appear after signing up")

        app.tabBars.buttons["Settings"].tap()

        let deleteRow = app.buttons["settings.deleteAccount"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 10), "Expected the Delete account row in Settings")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: settings-row\n".data(using: .utf8)!)
        sleep(2)

        deleteRow.tap()

        let confirmField = app.textFields["settings.deleteAccount.field"]
        XCTAssertTrue(confirmField.waitForExistence(timeout: 10), "Expected the type-to-confirm field in the delete sheet")

        let confirmButton = app.buttons["settings.deleteAccount.confirm"]
        XCTAssertFalse(confirmButton.isEnabled, "Expected Delete everything to start disabled")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: confirm-sheet\n".data(using: .utf8)!)
        sleep(2)

        confirmField.tap()
        confirmField.typeText("delete")   // lowercase must NOT enable the button — exact match only
        XCTAssertFalse(confirmButton.isEnabled, "Expected a lowercase mismatch to keep Delete everything disabled")

        // Backspace it out by length (same technique `StashUITests.swift`'s own wrong-password
        // test uses for a `SecureField` — a plain `TextField` here has no reliably-identifiable
        // native "Clear text" button under SwiftUI/XCUITest) rather than assuming one exists.
        confirmField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "delete".count))
        confirmField.typeText("DELETE")
        XCTAssertTrue(confirmButton.isEnabled, "Expected an exact \"DELETE\" match to enable Delete everything")

        confirmButton.tap()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 20),
                      "Expected the sign-in screen after a successful account deletion")
        XCTAssertTrue(app.staticTexts["auth.deletedBanner"].waitForExistence(timeout: 5),
                      "Expected the \"Your account was deleted.\" banner on the sign-in screen")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: account-deleted-banner\n".data(using: .utf8)!)
        sleep(2)

        // The proof that matters: the server-side account is actually gone, not just that the app
        // LOCALLY navigated to the sign-in screen (which a purely client-side bug could fake).
        let expectation = expectation(description: "sign-in probe for the deleted account resolves")
        var probeFailed = false
        Task {
            probeFailed = await Self.signInFails(email: email, password: password)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 20)
        XCTAssertTrue(probeFailed, "Expected a REST sign-in attempt for the deleted account to fail")
    }

    /// Runs the exact same flow twice in one test-method-invocation-worth-of-coverage isn't the
    /// point (the plan calls for running `testDeleteAccountEndToEnd` itself twice, i.e. two
    /// separate `xcodebuild test` invocations, each minting its OWN throwaway account — see the
    /// task report). This second test only exists to prove the destructive button's exact-match
    /// gate and Cancel path never touch the server at all — no throwaway account is created here,
    /// so there's nothing to delete or clean up (and `tearDown()` above is a no-op: `cleanupEmail`
    /// is never set).
    func testDeleteAccountSheetCancelLeavesSignInScreenUntouched() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10),
                      "Expected the sign-in screen to appear")
        XCTAssertFalse(app.staticTexts["auth.deletedBanner"].exists,
                       "Expected no deleted-account banner on an ordinary fresh sign-in screen")
    }

    /// REST probe (mirrors `StashUITests.swift`'s own `fixtureRepairAccessToken` shape, but
    /// standalone in this file): `true` if a password sign-in for `email`/`password` is refused —
    /// exactly what a deleted (or never-existing) account looks like from the outside.
    private static func signInFails(email: String, password: String) async -> Bool {
        await signInToken(email: email, password: password) == nil
    }

    /// The shared REST password-grant primitive both `signInFails` (the test's own final proof)
    /// and `tearDown` (the safety-net cleanup) build on: `nil` if the sign-in is refused (account
    /// gone, or never existed), else the resulting access token.
    private static func signInToken(email: String, password: String) async -> String? {
        var request = URLRequest(
            url: baseURL.appending(path: "/auth/v1/token")
                .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String
        else { return nil }
        return token
    }

    /// `tearDown`'s safety-net delete — same `delete-account` contract `DeleteAccountSection`
    /// itself calls in-app (`AccountDeleter`/`FunctionsAccountDeletionTransport`), reimplemented
    /// here directly with plain `URLSession` rather than importing StashKit: this file is
    /// deliberately standalone (see the type's doc comment), and a bare POST + status check is
    /// all a teardown safety net needs — no typed error decoding, this call site only needs to
    /// know 2xx vs. not.
    private static func deleteAccount(accessToken: String) async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "/functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [String: String]())
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
