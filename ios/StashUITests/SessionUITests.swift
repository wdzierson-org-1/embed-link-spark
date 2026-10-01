import XCTest

/// Plan 15 Task 6C: session behavior at launch and on the sign-in form, against production
/// Supabase with the permanent UI-test account (`STASH_TEST_EMAIL`/`STASH_TEST_PASSWORD`, injected
/// as exported `TEST_RUNNER_*` variables — never hardcoded). Self-contained: no helpers shared with
/// `StashUITests.swift`. Creates no rows and no accounts.
final class SessionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Plan 16: the simulator-global Bold Text setting may have been left on by an interrupted
        // accessibility run (see `A11yScreenshotSupport`'s GLOBAL STATE note).
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    /// iOS 26 offers "Save Password?" after the sign-in form submits; left up, it swallows the
    /// test's next tap. The canonical plan-16 recipe (`A11yScreens`, taps exactly "Not Now"); a
    /// no-op before iOS 26. Test methods run on the main thread.
    private func dismissSavePasswordPrompt(_ app: XCUIApplication) {
        MainActor.assumeIsolated { A11yScreens.dismissSavePasswordPrompt(app) }
    }

    private func credentials() throws -> (email: String, password: String) {
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

    private func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }

    /// H1: the app was evicted and is relaunched more than an hour after its last token refresh,
    /// with Auth unreachable (no signal for the refresh; the rest of the network happens to work).
    /// It must come up in the tab UI — never the sign-in screen — with the View tab showing its
    /// cached cards, and stay there while the refresh keeps failing. Before plan 15 the launch
    /// refreshed first and treated the failure as "signed out".
    ///
    /// DEBUG launch hooks: `--uitest-expire-session` marks the stored session's access token as
    /// expired (the app stops if it can't, so this can't pass vacuously) and
    /// `--uitest-auth-unreachable` fails every Supabase Auth request as if offline.
    func testExpiredTokenColdLaunchWithAuthUnreachableStaysSignedIn() throws {
        let (email, password) = try credentials()
        let app = XCUIApplication()
        let viewTab = app.tabBars.buttons["View"]
        let firstCard = app.descendants(matching: .any)["card.0"]
        let signInEmail = app.textFields["signin.email"]

        // 1. A fresh sign-in: a stored session, and a View tab that has cached its first page.
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 15), "Sign-in email field did not appear")
        signInEmail.tap()
        signInEmail.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(viewTab.waitForExistence(timeout: 20), "Expected the tab bar after signing in")
        dismissSavePasswordPrompt(app)
        viewTab.tap()
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "Expected the library's first card")
        sleep(2)   // the disk-cache write is coalesced (~250 ms); let it land before the kill
        let cachedFirstCard = firstCard.label
        app.terminate()

        // 2. Cold launch with an expired token while Auth can't be reached.
        app.launchArguments = ["--uitest-expire-session", "--uitest-auth-unreachable"]
        app.launch()
        XCTAssertTrue(viewTab.waitForExistence(timeout: 10),
                      "An expired token with Auth unreachable must still open the app, not the sign-in screen")
        XCTAssertFalse(signInEmail.exists, "The sign-in screen must not appear")
        viewTab.tap()
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "The View tab should show its cached page")
        XCTAssertEqual(firstCard.label, cachedFirstCard, "The View tab should show its cached page")
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: offline-cold-launch\n".data(using: .utf8)!)
        // Long enough for the SDK's refresh and its retry to fail, and for the library's own
        // refresh to run without a user token: neither may bounce the app to sign-in or replace
        // the cached page. (Without a user token the refresh used to go out with the anon key; RLS
        // then returns only this account's PUBLIC items — its newest item is private — and that
        // page replaced the cache. It now fails instead: `SignedInAnonFallbackGuard`.)
        sleep(8)
        XCTAssertFalse(signInEmail.exists, "A refresh that can't reach Auth must not sign the app out")
        XCTAssertTrue(viewTab.exists)
        XCTAssertTrue(firstCard.exists, "The cached cards must survive the failed refresh")
        XCTAssertEqual(firstCard.label, cachedFirstCard,
                       "A refresh without a user token must not replace the cached page")
        app.terminate()

        // 3. Auth reachable again: the stored refresh token (never spent above) still works.
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(viewTab.waitForExistence(timeout: 20), "Expected the app to open signed in")
        viewTab.tap()
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20))
        sleep(3)
        XCTAssertFalse(signInEmail.exists, "The refreshed session must keep the app signed in")
    }

    /// A local sign-out must stick even while the SDK is refreshing the session it removes. At a
    /// launch whose stored access token has expired, the SDK refreshes it straight away; when that
    /// refresh lands after the sign-out it stores a fresh session again, which used to bounce the
    /// app back into the account (this is how the first `--uitest-reset-auth` launch after a
    /// simulator sat idle for over an hour came up signed in). Here: an expired stored session,
    /// then a `--uitest-reset-auth` launch with Auth reachable — the sign-in screen must appear and
    /// stay.
    func testSignOutAtLaunchIsNotUndoneByTheExpiredSessionsRefresh() throws {
        let (email, password) = try credentials()
        let app = XCUIApplication()
        let viewTab = app.tabBars.buttons["View"]
        let signInEmail = app.textFields["signin.email"]

        // A stored session…
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 15), "Sign-in email field did not appear")
        signInEmail.tap()
        signInEmail.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(viewTab.waitForExistence(timeout: 20), "Expected the tab bar after signing in")
        dismissSavePasswordPrompt(app)
        app.terminate()

        // …whose access token has expired (Auth unreachable, so nothing refreshes it here).
        app.launchArguments = ["--uitest-expire-session", "--uitest-auth-unreachable"]
        app.launch()
        XCTAssertTrue(viewTab.waitForExistence(timeout: 10))
        app.terminate()

        // Sign out at launch while the SDK refreshes that expired session.
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 10), "Expected the sign-in screen after the sign-out")
        sleep(6)   // long enough for any refresh that was in flight to land
        XCTAssertTrue(signInEmail.exists, "A refresh that lands after the sign-out must not sign the app back in")
        XCTAssertFalse(viewTab.exists)
        app.terminate()

        // And it stays signed out at the next launch (nothing was re-stored behind the screen).
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 10), "The Keychain must not hold a resurrected session")
    }

    /// L8: on the sign-in form, Return moves from email to password, and Return on the password
    /// signs in — no tap on the button.
    func testReturnKeyWalksTheSignInFormAndSignsIn() throws {
        let (email, password) = try credentials()
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email + "\n")

        let passwordField = app.secureTextFields["signin.password"]
        XCTAssertTrue(waitForKeyboardFocus(passwordField), "Return on the email field should focus the password field")
        passwordField.typeText(password + "\n")

        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 20),
                      "Return on the password field should sign in")
        dismissSavePasswordPrompt(app)
    }

    /// L8: on the sign-up form, Return walks email → password → username → phone. Nothing is
    /// submitted (the phone pad has no Return key), so no account is created.
    func testReturnKeyWalksTheSignUpForm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10), "Sign-in screen did not appear")
        let signUpTab = app.buttons["auth.tab.signUp"]
        XCTAssertTrue(signUpTab.waitForExistence(timeout: 5))
        signUpTab.tap()

        let stamp = Int(Date().timeIntervalSince1970)
        let emailField = app.textFields["signin.email"]
        emailField.tap()
        emailField.typeText("will+returnchain-\(stamp)@dzierson.com\n")

        let passwordField = app.secureTextFields["signin.password"]
        XCTAssertTrue(waitForKeyboardFocus(passwordField), "Return on the email field should focus the password field")
        passwordField.typeText("ReturnChain-\(stamp)!\n")

        let usernameField = app.textFields["auth.username"]
        XCTAssertTrue(waitForKeyboardFocus(usernameField), "Return on the sign-up password should focus the username")
        usernameField.typeText("returnchain\(stamp)\n")

        let phoneField = app.textFields["auth.phone"]
        XCTAssertTrue(waitForKeyboardFocus(phoneField), "Return on the username should focus the phone field")
        XCTAssertFalse(app.tabBars.buttons["View"].exists, "Nothing should have been submitted")
    }
}
