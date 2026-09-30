import UIKit
import XCTest

// Plan 16 — the accessibility screenshot matrix and the hit-area / type-role tests share this.
//
// HOW TO USE (2b: A11yDetailLibraryUITests, 2c: A11yAppUITests)
//
//     override func setUpWithError() throws {
//         continueAfterFailure = false
//         MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }   // see GLOBAL STATE
//     }
//
//     @MainActor
//     func testDetailScreenshots() throws {
//         let screens = A11yScreens(self)
//         try screens.signIn()                        // once per test: the real form, default size
//         for variant in A11yVariant.matrix {         // Large, xxxLarge, AX3, Bold Text at Large
//             let app = screens.launch(variant, tab: .view, arguments: ["--uitest-…"])
//             // … navigate, wait for what you need …
//             screens.attachScreenshot(named: "detail-link")    // attachment "a11y-detail-link-AX3"
//         }
//     }
//
// then export the attachments as PNGs named after them:
//
//     /tmp/p16/export-shots.sh /tmp/p16/results/<run>.xcresult .superpowers/sdd/plan-16
//
// What it takes care of:
// - Signing in through the real form with `--uitest-reset-auth` (the Keychain session survives
//   reinstalls on the Simulator) at the DEFAULT text size — the sign-in form isn't what these
//   tests look at, and at accessibility sizes its button can sit below the keyboard.
// - Relaunching signed in (no `--uitest-reset-auth`: the Keychain session restores) for each
//   variant, straight onto a tab via `--uitest-tab-view` / `-ask` / `-settings` — never a tab-bar
//   tap, which iOS 26 swallows while the sign-in keyboard is still going away.
// - Dynamic Type PER LAUNCH, no global simulator state: `-UIPreferredContentSizeCategoryName
//   <UIContentSizeCategory raw value>` sets the app's content size category, and SwiftUI's
//   `dynamicTypeSize` follows it everywhere — tabs and sheets included (verified in plan 16 by
//   `A11yFoundationUITests.testContentSizeLaunchArgumentReachesSwiftUI` and the AX3 shots).
// - Bold Text PER LAUNCH via the DEBUG `--uitest-bold-text` argument: the app sets the window
//   scene's legibility-weight TRAIT to bold (`UIWindowScene.traitOverrides`, see `StashApp`'s
//   `UITestTraitOverrides`) — what Settings › Bold Text sets — so every hosting controller sees it:
//   MainTabView's tabs, NavigationStack, sheets and covers. (Until the plan-16 fix wave it set the
//   SwiftUI environment at the root, which stopped at the root TabView's tabs and at sheets: L-bold
//   shots of real screens were identical to L.) SF text, `mono`, SF Symbols and SwiftUI-hosted text
//   fields go bold by themselves; Neue Montreal text goes one face heavier only through
//   `.stashFont`. The one thing the hook can't reach is UIKit text that reads the global setting
//   rather than the trait: on iOS 17 the tab bar's item labels stay regular in L-bold shots (they
//   follow only the real setting; iOS 26's tab bar goes bold). Check every L-bold shot really
//   differs from its L shot.
// - iOS 26's "Save Password?" sheet after a sign-in (`dismissSavePasswordPrompt`, the canonical
//   copy — the other suites' copies should point here).
// - `launchSpecimen(_:)`: the DEBUG type specimen (every role, the shared controls, the contrast
//   cases), signed out — the reference sheet to shoot beside a screen.
//
// GLOBAL STATE — two knobs change the WHOLE SIMULATOR, not one launch, and survive the app, the
// test run and a killed runner (a timeout, a stopped run: teardown blocks never run then):
// - the REAL Bold Text setting (`enableBoldTextSetting(for:)` / `setBoldTextSetting(_:)`);
// - `xcrun simctl ui <udid> content_size <size>` (the host-side Dynamic Type fallback).
// So: never run two suites that use them on the same simulator at once (2b and 2c each have their
// own), always pair them with a restore (`enableBoldTextSetting(for:)` registers its own teardown;
// `simctl ui <udid> content_size large` afterwards), and start every a11y test with
// `A11yScreens.restoreRealBoldTextIfLeftOn()` (the setUp above), which switches a leaked Bold Text
// back off. A leaked content size doesn't affect launches that pass the launch argument (all of
// `A11yScreens`'), but does affect the share extension and every other suite: reset it with
// `xcrun simctl ui <udid> content_size large`.
//
// The SHARE EXTENSION is its own process, launched by the host app, so neither launch argument
// reaches it. Shoot it with the real settings: `A11yScreens.enableBoldTextSetting(for: self)`, and
// for text size the global `simctl` fallback above, reset to `large` afterwards.
//
// Xcode's own audit is worth running on each screen too (it caught the old detail sheet's faint
// section labels and 17 pt-tall hit areas):
//   try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast, .textClipped]) { … }
// It only audits what is on screen.
//
// Credentials come from the test runner's environment (`STASH_TEST_EMAIL` / `STASH_TEST_PASSWORD`,
// passed as `TEST_RUNNER_…` to xcodebuild); they are never printed.

/// One text-size (+ optional Bold Text) setting for a launch, with the stable token screenshot
/// names end in.
struct A11yVariant: Hashable, CustomStringConvertible {
    /// `UIContentSizeCategory` raw value, e.g. `UICTContentSizeCategoryL`.
    let category: String
    /// Stable screenshot-name token: `L`, `xxxL`, `AX3`, `L-bold`, …
    let token: String
    /// Launch with the DEBUG `--uitest-bold-text` hook: the window scene's legibility-weight trait
    /// is bold, as with Settings › Bold Text, on every screen of this launch.
    var bold = false

    /// Large — the default text size.
    static let large = A11yVariant(category: "UICTContentSizeCategoryL", token: "L")
    /// The largest standard size (Settings › Display & Text Size, slider all the way right).
    static let xxxLarge = A11yVariant(category: "UICTContentSizeCategoryXXXL", token: "xxxL")
    /// Accessibility size 3 of 5 ("Larger Accessibility Sizes" on, third step).
    static let ax3 = A11yVariant(category: "UICTContentSizeCategoryAccessibilityXL", token: "AX3")
    /// The largest accessibility size — for spot checks; not part of the standard matrix.
    static let ax5 = A11yVariant(category: "UICTContentSizeCategoryAccessibilityXXXL", token: "AX5")
    /// Bold Text at the default size.
    static let largeBold = A11yVariant(category: "UICTContentSizeCategoryL", token: "L-bold", bold: true)

    /// The plan-16 screenshot matrix: Large, xxxLarge, AX3, and Bold Text at Large.
    static let matrix: [A11yVariant] = [.large, .xxxLarge, .ax3, .largeBold]

    var launchArguments: [String] {
        ["-UIPreferredContentSizeCategoryName", category] + (bold ? ["--uitest-bold-text"] : [])
    }

    /// The trait collection this variant's text size renders with — for `UIFontMetrics`
    /// expectations (`UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: …)`).
    var traits: UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(rawValue: category))
    }

    var description: String { token }
}

/// The tab a relaunch lands on (`MainTabView` reads these DEBUG arguments; Add is the default).
enum A11yTab {
    case add, ask, view, settings

    var launchArguments: [String] {
        switch self {
        case .add: []
        case .ask: ["--uitest-tab-ask"]
        case .view: ["--uitest-tab-view"]
        case .settings: ["--uitest-tab-settings"]
        }
    }
}

/// Launch/sign-in/screenshot helper for one test. Create one per test method.
@MainActor
final class A11yScreens {
    let app: XCUIApplication
    /// The variant of the most recent `launch` / `launchSpecimen` — `attachScreenshot` appends its
    /// token.
    private(set) var variant: A11yVariant = .large
    private unowned let testCase: XCTestCase

    init(_ testCase: XCTestCase, app: XCUIApplication? = nil) {
        self.testCase = testCase
        self.app = app ?? XCUIApplication()
    }

    /// Signs in through the real form (`--uitest-reset-auth`, default text size), declines iOS
    /// 26's "Save Password?" sheet, and leaves the app terminated, ready for `launch`.
    func signIn(file: StaticString = #filePath, line: UInt = #line) throws {
        let (email, password) = try Self.credentials()
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "Sign-in email field did not appear", file: file, line: line)
        Self.tapUntilFocused(emailField)
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        Self.tapUntilFocused(passwordField)
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "Expected the tab bar after sign-in",
                      file: file, line: line)
        Self.dismissSavePasswordPrompt(app)
        app.terminate()
    }

    /// Relaunches signed in (after `signIn`) at `variant`, straight onto `tab`, and waits for the
    /// tab bar. `arguments` are extra DEBUG launch arguments (`--uitest-scripted-chat`, …).
    @discardableResult
    func launch(_ variant: A11yVariant, tab: A11yTab, arguments: [String] = [],
                file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        self.variant = variant
        app.launchArguments = variant.launchArguments + tab.launchArguments + arguments
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20),
                      "Expected to relaunch signed in (did `signIn()` run first?)", file: file, line: line)
        return app
    }

    /// Launches the DEBUG type specimen (`--uitest-type-specimen`: every `StashType` role, the
    /// shared controls, and the text-size / Bold Text state) at `variant`. Signed out; no network.
    /// `arguments`: extra specimen arguments (`--uitest-specimen-tabbed`: inside a root `TabView`).
    @discardableResult
    func launchSpecimen(_ variant: A11yVariant, arguments: [String] = [],
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        self.variant = variant
        app.launchArguments = ["--uitest-type-specimen"] + variant.launchArguments + arguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["specimen.state"].waitForExistence(timeout: 15),
                      "The type specimen did not appear", file: file, line: line)
        return app
    }

    /// Attaches a full-screen screenshot named `a11y-<screen>-<variant token>` (e.g.
    /// `a11y-detail-link-AX3`), kept even when the test passes.
    func attachScreenshot(named screen: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "a11y-\(screen)-\(variant.token)"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    // MARK: - Shared recipes

    /// iOS 26 offers "Save Password?" 2–8 s after a sign-in form submits; left up, it swallows the
    /// test's next tap. Declines it with the button labelled exactly "Not Now" — never "Save",
    /// which would store the test password in the simulator's keychain — looking in the app and
    /// in SpringBoard, and gives up after `timeout` (no wait at all before iOS 26, where it has
    /// never been seen). The canonical copy for every suite (plan 16).
    static func dismissSavePasswordPrompt(_ app: XCUIApplication, timeout: TimeInterval = 12) {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return }
        let notNowLabel = NSPredicate(format: "label == %@", "Not Now")
        let hosts = [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let notNow = hosts.lazy.map({ $0.buttons.matching(notNowLabel).firstMatch }).first(where: { $0.exists }) {
                // A tap while the sheet is still animating in or out is ignored: settle, tap, and
                // confirm it went, a bounded number of times.
                for _ in 0..<3 {
                    sleep(1)
                    guard notNow.exists else { break }
                    notNow.tap()
                    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notNow)
                    if XCTWaiter().wait(for: [gone], timeout: 3) == .completed { break }
                }
                sleep(1)
                return
            }
            usleep(250_000)
        }
    }

    /// Turns the REAL Bold Text setting on (Settings › Accessibility › Display & Text Size) for the
    /// rest of `testCase`, and registers the teardown that turns it back off FIRST, so a failure
    /// anywhere after this line still restores it. For what `--uitest-bold-text` can't reach, like
    /// the share extension (its own process, launched by the host app). Simulator-global — see
    /// GLOBAL STATE above; a killed runner skips teardown, which `restoreRealBoldTextIfLeftOn()`
    /// at the next test's start repairs.
    static func enableBoldTextSetting(for testCase: XCTestCase) {
        testCase.addTeardownBlock { @MainActor in A11yScreens.setBoldTextSetting(false) }
        setBoldTextSetting(true)
    }

    /// Switches the REAL Bold Text setting. The raw switch: turn it ON only through
    /// `enableBoldTextSetting(for:)`, which pairs it with its restore. Verified on iOS 17.0 and
    /// 26.5; the app picks the change up live.
    static func setBoldTextSetting(_ on: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        settings.launch()
        let accessibility = settings.staticTexts["Accessibility"]
        for _ in 0..<4 where !accessibility.isHittable { settings.swipeUp() }
        accessibility.tap()
        let displayAndText = settings.staticTexts["Display & Text Size"]
        XCTAssertTrue(displayAndText.waitForExistence(timeout: 5), "Settings: no Display & Text Size row")
        displayAndText.tap()
        let toggle = settings.switches["Bold Text"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Settings: no Bold Text switch")
        func isOn() -> Bool { (toggle.value as? String) == "1" }
        if isOn() != on { toggle.tap() }
        // Some Settings layouts only toggle when the switch itself is hit, not the row's middle.
        if isOn() != on { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(isOn(), on, "Settings: Bold Text didn't switch \(on ? "on" : "off")")
        settings.terminate()
    }

    /// Start-of-test guard for the simulator-global Bold Text setting: an interrupted earlier run
    /// (a timeout, a stopped runner) never ran its teardown and may have left it ON, which would
    /// silently turn every "regular" measurement and L shot bold. Reads the setting in the test
    /// runner's own process (`UIAccessibility.isBoldTextEnabled` is the system-wide value) and, if
    /// it's on, switches it off through Settings — logged as `A11Y state …` — and asserts it went.
    static func restoreRealBoldTextIfLeftOn(file: StaticString = #filePath, line: UInt = #line) {
        guard UIAccessibility.isBoldTextEnabled else { return }
        print("A11Y state: the REAL Bold Text setting was left ON by an earlier run — switching it off")
        setBoldTextSetting(false)
        let off = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !UIAccessibility.isBoldTextEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [off], timeout: 10), .completed,
                       "The real Bold Text setting is still on — every regular-weight check would be wrong",
                       file: file, line: line)
    }

    /// Taps `field` until it has keyboard focus (a tap can land while the screen is still settling).
    static func tapUntilFocused(_ field: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts {
            field.tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            if XCTWaiter().wait(for: [focused], timeout: 1.5) == .completed { return }
        }
    }

    /// Waits (a predicate, not a fixed sleep) until `element`'s label satisfies `condition`
    /// (`CONTAINS`, `ENDSWITH`, `==` — an `NSPredicate` operator) `text`; true if it did in time.
    @discardableResult
    static func waitForLabel(_ element: XCUIElement, _ text: String, condition: String = "CONTAINS",
                             timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label \(condition) %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
            == .completed
    }

    /// Taps the screen at `point` (screen coordinates, points) — for taps that must land outside
    /// any element's frame, e.g. just past a control's visual edge.
    static func tap(_ app: XCUIApplication, at point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    /// Drags the screen's scroll view until `element` sits well inside the visible area (100 pt
    /// clear of the top, 120 pt of the bottom), with no fling — for element screenshots and taps on
    /// something off screen. Gives up after a few drags.
    static func scrollIntoView(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<12 {
            guard element.exists else { return }
            let frame = element.frame, screen = app.frame
            let below = frame.maxY - (screen.maxY - 120), above = (screen.minY + 100) - frame.minY
            guard below > 0 || above > 0 else { return }
            // Positive drags the content up (reveals what's below); negative, down.
            let wanted = below > 0 ? frame.maxY - (screen.maxY - 200) : -((screen.minY + 200) - frame.minY)
            let distance = (wanted < 0 ? -1 : 1) * min(max(abs(wanted), 80), screen.height * 0.5)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.75 : 0.25))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    private static func credentials() throws -> (String, String) {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["STASH_TEST_EMAIL"], let password = environment["STASH_TEST_PASSWORD"],
              !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        return (email, password)
    }
}
