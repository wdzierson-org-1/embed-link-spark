import XCTest
import UIKit

/// The real sign-in form over the native renderer. All runs stay signed out and
/// never submit credentials. Physical sensor delivery needs an iPhone; the simulator
/// uses explicit injected forces to exercise the same fluid and drawing path.
final class ASCIIPoolUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPoolRendersBothMotionDirectionsBehindTheForm() {
        let app = XCUIApplication()
        for direction in ["left", "right"] {
            app.launchArguments = ["--uitest-reset-auth", "--uitest-pool-tilt-\(direction)"]
            app.launch()
            XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "ascii-pool-\(direction)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTAssertTrue(app.buttons["signin.submit"].isHittable)
            app.terminate()
        }
    }

    @MainActor
    func testReducedMotionPoolIsStillAndFormRemainsUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-auth", "--uitest-pool-motion-demo", "--uitest-reduce-motion"]
        app.launch()
        let email = app.textFields["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        let first = try poolPixels(app.screenshot())
        Thread.sleep(forTimeInterval: 1)
        let second = try poolPixels(app.screenshot())
        XCTAssertEqual(first, second, "Reduce Motion must freeze the exposed ASCII pool, even with injected movement")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ascii-pool-reduced-motion"
        shot.lifetime = .keepAlways
        add(shot)
        A11yScreens.tapUntilFocused(email)
        email.typeText("pool-preview@example.com")
        XCTAssertEqual(email.value as? String, "pool-preview@example.com")
        let password = app.secureTextFields["signin.password"]
        A11yScreens.tapUntilFocused(password)
        password.typeText("preview-only")
        XCTAssertTrue(app.buttons["signin.submit"].isEnabled)
        XCTAssertFalse(app.staticTexts["signin.error"].exists)
        app.terminate()
    }

    private func poolPixels(_ screenshot: XCUIScreenshot) throws -> Data {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        // Exclude the status bar and home indicator; this exposed bottom strip
        // contains liquid but no blinking insertion point or system clock.
        let region = CGRect(x: 0, y: Double(image.height) * 0.91,
                            width: Double(image.width), height: Double(image.height) * 0.04)
        let crop = try XCTUnwrap(image.cropping(to: region))
        return try XCTUnwrap(UIImage(cgImage: crop).pngData())
    }
}
