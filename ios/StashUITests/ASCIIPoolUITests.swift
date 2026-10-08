import XCTest
import UIKit

/// Real sign-in UI without restoring or clearing stored auth. Never submits credentials.
/// Injected Core Motion samples use the production mapping, simulation and drawing path;
/// physical sensor delivery itself still requires an iPhone.
final class ASCIIPoolUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPoolRendersBothMotionDirectionsBehindTheForm() throws {
        let left = try capturePool(arguments: ["--uitest-pool-tilt-left"], name: "ascii-pool-left")
        let right = try capturePool(arguments: ["--uitest-pool-tilt-right"], name: "ascii-pool-right")
        assertVisibleDifference(left, right, "Opposite tilts must visibly change the exposed liquid")
    }

    @MainActor
    func testPoolMovesUpWhenPhoneIsUpsideDown() throws {
        let down = try capturePool(arguments: [], name: "ascii-pool-upright")
        let up = try capturePool(arguments: ["--uitest-pool-upside-down"], name: "ascii-pool-upside-down")
        assertVisibleDifference(down, up, "Inverting gravity must visibly move liquid toward the top")
        XCTAssertLessThan(try XCTUnwrap(up.inkCenterY), try XCTUnwrap(down.inkCenterY) - 0.08,
                          "Upside-down liquid must rise; a different random frame is insufficient")
    }

    @MainActor
    func testGyroscopeRotationChangesPoolInBothDirections() throws {
        let clockwise = try capturePool(arguments: ["--uitest-pool-gyro-clockwise"], name: "ascii-pool-gyro-clockwise")
        let counterclockwise = try capturePool(arguments: ["--uitest-pool-gyro-counterclockwise"], name: "ascii-pool-gyro-counterclockwise")
        assertVisibleDifference(clockwise, counterclockwise, "Opposite gyroscope rotation must visibly change the fluid")
    }

    @MainActor
    func testReducedMotionPoolIsStillAndFormRemainsUsable() throws {
        let app = previewApp(arguments: ["--uitest-pool-motion-demo", "--uitest-reduce-motion"])
        defer { app.terminate() }
        let email = app.textFields["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        let first = try poolPixels(app.screenshot())
        Thread.sleep(forTimeInterval: 1)
        let second = try poolPixels(app.screenshot())
        XCTAssertEqual(first.rgb, second.rgb, "Reduce Motion must freeze exposed pixels even with injected movement")
        attach(app.screenshot(), named: "ascii-pool-reduced-motion")
        A11yScreens.tapUntilFocused(email)
        email.typeText("pool-preview@example.com")
        XCTAssertEqual(email.value as? String, "pool-preview@example.com")
        let password = app.secureTextFields["signin.password"]
        A11yScreens.tapUntilFocused(password)
        password.typeText("preview-only")
        XCTAssertTrue(app.buttons["signin.submit"].isEnabled)
        XCTAssertFalse(app.staticTexts["signin.error"].exists)
    }

    @MainActor
    func testPoolFreezesWhileEnteringCredentials() throws {
        // Upper liquid remains visible above the form. The narrow side gutters sit outside
        // the simulation's particle boundary, and the keyboard covers the bottom liquid.
        let app = previewApp(arguments: ["--uitest-pool-upside-down"])
        defer { app.terminate() }
        let email = app.textFields["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        let movingRegion = try exposedTopRegion(app)
        let movingBefore = try poolPixels(app.screenshot(), exposedTop: movingRegion)
        Thread.sleep(forTimeInterval: 0.4)
        let movingAfter = try poolPixels(app.screenshot(), exposedTop: movingRegion)
        assertVisibleDifference(movingBefore, movingAfter, "The upper pool must visibly move before focus")

        A11yScreens.tapUntilFocused(email)
        email.typeText("pool-preview@example.com")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5) // keyboard/form layout must finish before the crop
        let frozenRegion = try exposedTopRegion(app)
        let focusedScreenshot = app.screenshot()
        attach(focusedScreenshot, named: "ascii-pool-editing-paused")
        let first = try poolPixels(focusedScreenshot, exposedTop: frozenRegion)
        XCTAssertGreaterThan(first.inkPixelCount, 10, "The frozen crop must contain liquid glyphs")
        Thread.sleep(forTimeInterval: 0.8)
        let second = try poolPixels(app.screenshot(), exposedTop: frozenRegion)
        XCTAssertEqual(first.rgb, second.rgb, "Editing must freeze the pool without needing Reduce Motion")
        XCTAssertEqual(email.value as? String, "pool-preview@example.com")
    }

    /// Read the actual form geometry after keyboard scrolling. The space to the right of
    /// the wordmark, below the status UI, and above the ink address bar contains only pool.
    @MainActor
    private func exposedTopRegion(_ app: XCUIApplication) throws -> CGRect {
        let window = app.windows.firstMatch.frame
        let wordmark = app.images.matching(NSPredicate(format: "label == %@", "Stash")).firstMatch
        let address = app.staticTexts["stash://sign-in"]
        XCTAssertTrue(wordmark.exists)
        XCTAssertTrue(address.exists)
        let left = max(wordmark.frame.maxX + 24, window.minX + window.width * 0.5)
        let top = window.minY + window.height * 0.08
        var bottom = address.frame.minY - 20 // 12pt address-bar padding, then 8pt clear space
        if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
        let rect = CGRect(x: left, y: top, width: window.maxX - 24 - left, height: bottom - top)
        guard rect.width > 12, rect.height > 12 else {
            throw XCTSkip("The focused form leaves no exposed top pool region on this screen size")
        }
        return CGRect(x: (rect.minX - window.minX) / window.width,
                      y: (rect.minY - window.minY) / window.height,
                      width: rect.width / window.width, height: rect.height / window.height)
    }

    @MainActor
    func testSignInPreviewPreservesSavedSession() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--uitest-tab-view"]
        app.launch()
        guard app.tabBars.buttons["View"].waitForExistence(timeout: 15) else {
            throw XCTSkip("No saved session is available; this check never signs in or clears auth")
        }
        app.terminate()
        app.launchArguments = ["--uitest-preview-signin", "--uitest-reduce-motion"]
        app.launch()
        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["View"].exists)
        app.terminate()
        app.launchArguments = ["--uitest-tab-view"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15),
                      "A normal launch after the preview must restore the saved session")
        XCTAssertFalse(app.textFields["signin.email"].exists)
    }

    @MainActor
    private func previewApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-preview-signin"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func capturePool(arguments: [String], name: String) throws -> PoolPixels {
        let app = previewApp(arguments: arguments)
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        let screenshot = app.screenshot()
        attach(screenshot, named: name)
        XCTAssertTrue(app.buttons["signin.submit"].isHittable)
        let pixels = try poolPixels(screenshot)
        XCTAssertGreaterThan(pixels.inkPixelCount, 10, "The exposed region must contain liquid glyphs")
        return pixels
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private struct PoolPixels {
        let rgb: [UInt8]
        let inkPixelCount: Int
        /// Normalized vertical center of dark glyphs, excluding lighter paper texture.
        let inkCenterY: Double?
    }

    private func assertVisibleDifference(_ first: PoolPixels, _ second: PoolPixels, _ message: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(first.rgb.count, second.rgb.count, "Pixel regions must match", file: file, line: line)
        guard first.rgb.count == second.rgb.count, !first.rgb.isEmpty else { return }
        var changed = 0
        for index in stride(from: 0, to: first.rgb.count, by: 3) {
            if (0..<3).contains(where: { abs(Int(first.rgb[index + $0]) - Int(second.rgb[index + $0])) > 12 }) {
                changed += 1
            }
        }
        XCTAssertGreaterThan(Double(changed) / Double(first.rgb.count / 3), 0.002, message, file: file, line: line)
    }

    private func poolPixels(_ screenshot: XCUIScreenshot, exposedTop: CGRect? = nil) throws -> PoolPixels {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        var rgb: [UInt8] = []
        var inkCount = 0
        var inkY = 0.0
        // Capture the exposed top/bottom bands as well as side gutters. A gutter alone can
        // contain no glyphs because particles stay inward of the physics wall. The top band
        // is below the status UI and above the unfocused logo; focused tests supply real bounds.
        for y in Int(Double(height) * 0.08)..<Int(Double(height) * 0.95) {
            let relativeY = Double(y) / Double(height)
            for x in Int(Double(width) * 0.005)..<Int(Double(width) * 0.995) {
                let relativeX = Double(x) / Double(width)
                let isGutter = relativeX < 0.035 || relativeX > 0.965
                let included = exposedTop.map { $0.contains(CGPoint(x: relativeX, y: relativeY)) }
                    ?? (isGutter || relativeY < 0.12 || relativeY >= 0.91)
                guard included else { continue }
                let offset = (y * width + x) * 4
                rgb.append(contentsOf: rgba[offset..<(offset + 3)])
                // Paper texture is translucent (green >= 190); liquid glyphs are darker.
                if rgba[offset + 1] < 160 {
                    inkCount += 1
                    inkY += relativeY
                }
            }
        }
        return PoolPixels(rgb: rgb, inkPixelCount: inkCount,
                          inkCenterY: inkCount > 0 ? inkY / Double(inkCount) : nil)
    }
}
