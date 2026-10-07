import XCTest

/// Read-only simulator acceptance for the redesign. Uses the existing test account;
/// no capture, edit, delete, chat send, or production fixture mutation.
final class DesignV2UITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testRedesignScreensAndKeyboard() throws {
        let screens = A11yScreens(self)
        screens.app.launchArguments = ["--uitest-reset-auth"]
        screens.app.launch()
        XCTAssertTrue(screens.app.textFields["signin.email"].waitForExistence(timeout: 15))
        screens.attachScreenshot(named: "v2-sign-in")
        screens.app.terminate()
        try screens.signIn()

        for tab in [A11yTab.add, .view, .ask, .settings] {
            let app = screens.launch(.large, tab: tab)
            switch tab {
            case .add:
                screens.attachScreenshot(named: "v2-add")
            case .view:
                let card = app.buttons["card.0"]
                XCTAssertTrue(card.waitForExistence(timeout: 20), "The test account's library should load")
                screens.attachScreenshot(named: "v2-library")
                card.tap()
                XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10))
                screens.attachScreenshot(named: "v2-detail")
                app.buttons["detail.done"].tap()
                let search = app.textFields["library.search"]
                A11yScreens.tapUntilFocused(search)
                search.typeText("link")
                XCTAssertTrue(app.buttons["library.search.cancel"].waitForExistence(timeout: 5))
                app.buttons["library.search.cancel"].tap()
            case .ask:
                XCTAssertTrue(app.textFields["ask.input"].waitForExistence(timeout: 10))
                screens.attachScreenshot(named: "v2-ask")
                A11yScreens.tapUntilFocused(app.textFields["ask.input"])
                XCTAssertTrue(app.buttons["ask.dismissKeyboard"].waitForExistence(timeout: 5))
                screens.attachScreenshot(named: "v2-ask-keyboard")
                app.buttons["ask.dismissKeyboard"].tap()
            case .settings:
                XCTAssertTrue(app.staticTexts["settings.account.email"].waitForExistence(timeout: 10))
                screens.attachScreenshot(named: "v2-settings")
                let fonts = app.staticTexts["design.fontStatus"]
                for _ in 0..<6 where !fonts.isHittable { app.swipeUp() }
                XCTAssertEqual(fonts.label, "font:neue-montreal departure:loaded jetbrains:loaded")
            }
            app.terminate()
        }

        for tab in [A11yTab.add, .view, .ask] {
            let app = screens.launch(.ax3, tab: tab)
            screens.attachScreenshot(named: "v2-\(tab)-large-text")
            app.terminate()
        }
        _ = screens.launch(.large, tab: .view)
    }
}
