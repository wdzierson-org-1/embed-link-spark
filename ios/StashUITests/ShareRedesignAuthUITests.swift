import XCTest

/// Run on the dedicated QA simulator with review-account credentials only.
final class ShareRedesignAuthUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPreviewSignInHandsOverToRealSessionAndNewTabOrder() throws {
        let environment = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(environment["STASH_TEST_EMAIL"])
        let password = try XCTUnwrap(environment["STASH_TEST_PASSWORD"])
        let app = XCUIApplication()
        defer { app.terminate() }
        // Preview intentionally leaves any stored session untouched until explicit sign-in.
        app.launchArguments = ["--uitest-preview-signin", "--uitest-reset-auth", "--uitest-reduce-motion"]
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15))
        A11yScreens.tapUntilFocused(emailField)
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        A11yScreens.tapUntilFocused(passwordField)
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        A11yScreens.dismissSavePasswordPrompt(app)
        let dismissOnboarding = app.buttons["onboarding.skip"]
        if dismissOnboarding.waitForExistence(timeout: 5) { dismissOnboarding.tap() }
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 20),
                      "Successful preview authentication must remove the overlay and start the session")
        XCTAssertFalse(app.textFields["signin.email"].exists)
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["View", "Ask", "Add", "Settings"])
        XCTAssertTrue(app.tabBars.buttons["View"].isSelected)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15),
                      "The same authenticated session must restore on an ordinary launch")
        XCTAssertFalse(app.textFields["signin.email"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "share-redesign-native-library"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
