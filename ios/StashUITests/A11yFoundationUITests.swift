import UIKit
import XCTest

/// Plan 16, Task 2a — the accessibility foundation: shared controls take taps across a 44×44 pt
/// target without their visuals moving; every `StashType` role renders at its contract size,
/// scales with its own text style and draws one face heavier under Bold Text (the real setting
/// too, live); Xcode's hit-region, Dynamic Type and contrast audits pass the specimen; the Dynamic
/// Type launch argument the screenshot matrix relies on reaches SwiftUI; and the baseline screens
/// come up at every size. Most checks run on the DEBUG type specimen (`--uitest-type-specimen`:
/// signed out, no network); the Ask checks run on the real screen with scripted answers.
final class A11yFoundationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Hit areas

    /// Will: "Some elements … appear smaller than iOS standard guidelines". Ask's header circles
    /// stay 36 pt (`CircleIcon(size: 36)`), exactly where they were, and now report their 44×44 pt
    /// tap target as their accessibility frame; a tap 3.5 pt past the History circle's right edge
    /// opens Conversations. (On its own this screen can't fail without the fix — over empty space
    /// SwiftUI's touch-radius tolerance reaches the circle anyway — so the RED/GREEN proof is the
    /// specimen test below; this one pins the real header's layout and target.)
    @MainActor
    func testAskHeaderCirclesKeepTheirLayoutAndReportA44PointTarget() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat"])
        let newChat = app.buttons["ask.newChat"]
        let history = app.buttons["ask.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), "History circle missing")
        screens.attachScreenshot(named: "2a-ask-header")

        XCTAssertEqual(history.frame.width, 44, accuracy: 0.5, "History's target should be 44 pt wide")
        XCTAssertEqual(history.frame.height, 44, accuracy: 0.5, "History's target should be 44 pt tall")
        // Layout unchanged: 36 pt circles 8 pt apart, History 16 pt in from the trailing edge. Had
        // the circles grown to 44 in layout, both distances would be 4–8 pt larger.
        XCTAssertEqual(history.frame.midX - newChat.frame.midX, 18 + 8 + 18, accuracy: 0.5,
                       "The header circles moved apart — a circle's layout size changed")
        XCTAssertEqual(app.frame.maxX - history.frame.midX, 16 + 18, accuracy: 0.5,
                       "History moved away from the trailing edge — its layout size changed")

        A11yScreens.tap(app, at: CGPoint(x: history.frame.midX + 18 + 3.5, y: history.frame.midY))
        XCTAssertTrue(app.textFields["convos.search"].waitForExistence(timeout: 5),
                      "A tap 3.5 pt past the History circle's edge should open Conversations")
    }

    /// Hardware keyboards: ⌘. is the keyboard Cancel (`StashCancelButton`'s `.cancelAction`) — on
    /// Ask, as anywhere it shows, the keyboard goes and the draft stays. (Plain Esc, the other
    /// `.cancelAction` key, never reaches the shortcut: the focused text field keeps it — probed on
    /// iOS 17.0, where a typed "z" landed in the field and Esc changed nothing.)
    @MainActor
    func testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat"])
        let input = Self.element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask composer missing")
        input.tap()
        input.typeText("Keep this draft")
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing")

        app.typeKey(".", modifierFlags: .command)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "⌘. should put the keyboard away like Cancel")
        XCTAssertEqual(input.value as? String, "Keep this draft", "⌘. must keep the draft")
        XCTAssertTrue(app.buttons["ask.history"].waitForExistence(timeout: 5), "The header circles should be back")
    }

    /// The shared controls in `Design/` — `CircleIcon` (36 pt and its 40 pt default),
    /// `CircleSubmitIcon` at the composer's 40 pt, and `PillTabs` — take every tap inside a
    /// 44×44 pt target centred on them, even over a tappable surface; a tap past that target goes
    /// to the surface. (Over empty space SwiftUI's touch-radius tolerance, ~16 pt with a
    /// synthesized XCUITest touch, would hide the difference — hence the specimen's surface.)
    @MainActor
    func testSharedControlsTakeEveryTapInsideA44PointTarget() throws {
        continueAfterFailure = true   // report every control, not just the first miss
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        let taps = app.staticTexts["specimen.taps"]
        XCTAssertTrue(taps.waitForExistence(timeout: 5), "Tap counter missing")
        screens.attachScreenshot(named: "2a-specimen-controls")

        // Layout unchanged: the circles' centres are exactly radius + 48 pt spacing + radius
        // apart, as drawn; a circle whose layout had grown to 44 pt would push them further apart.
        let circle36 = app.buttons["specimen.circle36"], circle40 = app.buttons["specimen.circle40"]
        let submit40 = app.buttons["specimen.submit40"]
        XCTAssertEqual(circle36.label, "Specimen 36 pt circle", "stashIconControl should give the control its VoiceOver label")
        XCTAssertEqual(circle40.frame.midX - circle36.frame.midX, 18 + 48 + 20, accuracy: 0.5, "A circle's layout size changed")
        XCTAssertEqual(submit40.frame.midX - circle40.frame.midX, 20 + 48 + 20, accuracy: 0.5, "A circle's layout size changed")

        /// Taps `gap` pt past the visual edge of the round control `identifier` (a circle of
        /// `diameter` centred on its frame), to its right or below it.
        func tapPast(_ identifier: String, diameter: CGFloat, gap: CGFloat, below: Bool = false,
                     expect expected: String, line: UInt = #line) {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(identifier) missing", line: line)
            // Its accessibility frame is its tap target (VoiceOver's outline, Xcode's hit-region
            // audit): at least 44×44 pt, centred on the circle.
            XCTAssertEqual(control.frame.width, max(diameter, 44), accuracy: 0.5, "\(identifier)'s target width", line: line)
            XCTAssertEqual(control.frame.height, max(diameter, 44), accuracy: 0.5, "\(identifier)'s target height", line: line)
            let r = diameter / 2
            A11yScreens.tap(app, at: below ? CGPoint(x: control.frame.midX, y: control.frame.midY + r + gap)
                                           : CGPoint(x: control.frame.midX + r + gap, y: control.frame.midY))
            usleep(300_000)
            XCTAssertTrue(taps.label.contains(expected), "Tap \(gap) pt past \(identifier): expected \(expected), got \(taps.label)",
                          line: line)
        }

        tapPast("specimen.circle36", diameter: 36, gap: 3.5, expect: "circle36=1")
        tapPast("specimen.circle36", diameter: 36, gap: 3.5, below: true, expect: "circle36=2")
        tapPast("specimen.circle36", diameter: 36, gap: 6, expect: "surface=1")   // past the 44 pt target
        tapPast("specimen.circle40", diameter: 40, gap: 1.5, expect: "circle40=1")
        tapPast("specimen.submit40", diameter: 40, gap: 1.5, below: true, expect: "submit40=1")

        // PillTabs: the selected tab's frame includes its capsule (the tab's visual extent); the
        // unselected tab reports either its text's frame or the same padded extent.
        let summary = app.buttons["specimen.tab.one"]
        let notes = app.buttons["specimen.tab.two"]
        XCTAssertTrue(notes.exists && summary.exists, "Pill tabs missing")
        let tabHeight = summary.frame.height
        XCTAssertLessThan(tabHeight, 40, "The pill tab is already 44 pt tall — nothing to prove")
        let notesTab = notes.frame.height < tabHeight - 4
            ? notes.frame.insetBy(dx: -12, dy: -(tabHeight - notes.frame.height) / 2)
            : notes.frame
        // Inside the Notes tab, beside its text: the whole tab is the target, not just the word.
        A11yScreens.tap(app, at: CGPoint(x: notesTab.minX + 5, y: notesTab.midY))
        usleep(300_000)
        XCTAssertTrue(taps.label.hasSuffix("tab=two"), "A tap beside the tab's word should select it, got \(taps.label)")
        summary.tap()
        usleep(300_000)
        XCTAssertTrue(taps.label.hasSuffix("tab=one"), "Summary should be selected again, got \(taps.label)")
        // Just above the pill: inside a 44 pt target centred on the tab.
        A11yScreens.tap(app, at: CGPoint(x: notesTab.midX, y: notesTab.minY - 3))
        usleep(300_000)
        XCTAssertEqual(taps.label, "circle36=2 circle40=1 submit40=1 surface=1 tab=two")
    }

    /// Xcode's own accessibility audit agrees: no shared control is flagged for its hit region
    /// (before plan 16 the unselected pill tab was — "Hit area is too small", its frame just the
    /// word) and no role for Dynamic Type (chip, micro-label and kicker at 11 pt were "partially
    /// unsupported"); `StashCancelButton(onWash: true)` over the gradient wash and a `muted`
    /// `prompt:` placeholder pass contrast. The decorative row and the fixed-size yardsticks are
    /// exempt by design, and the pill tabs' deliberate xxxLarge cap reads as "partially
    /// unsupported". Everything else the audit says is logged (`A11Y audit …`).
    @MainActor
    func testSpecimenPassesXcodesHitRegionDynamicTypeAndContrastAudits() throws {
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        var flagged: [String] = []
        var sawVioletOnWash = false
        try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast]) { issue in
            let id = issue.element?.identifier ?? ""
            print("A11Y audit \(issue.compactDescription) | \(id) \"\(issue.element?.label ?? "")\"")
            if issue.auditType == .contrast, id == "specimen.wash.violet600" { sawVioletOnWash = true }
            let isControl = id.hasPrefix("specimen.circle") || id.hasPrefix("specimen.submit") || id.hasPrefix("specimen.tab.")
                || id == "specimen.cancel.wash"
            let isRole = id.hasPrefix("specimen.role.") && !id.hasPrefix("specimen.role.decorative")
            switch issue.auditType {
            case .hitRegion where isControl || isRole,
                 .dynamicType where isRole,
                 .contrast where id == "specimen.cancel.wash" || id == "specimen.placeholder.muted":
                flagged.append("\(issue.compactDescription): \(id)")
            default:
                break
            }
            return true   // collected here, asserted below
        }
        XCTAssertTrue(flagged.isEmpty, "Audit issues:\n" + flagged.joined(separator: "\n"))
        XCTAssertTrue(sawVioletOnWash, "The contrast audit should flag violet-600 set straight on the wash — "
                      + "if it doesn't, it never looked at the wash strip and the Cancel check above proves nothing")
    }

    // MARK: - Dynamic Type

    /// The screenshot matrix sets Dynamic Type per launch with `-UIPreferredContentSizeCategoryName`
    /// (no global simulator state). It must reach SwiftUI's `dynamicTypeSize`, not just UIKit.
    @MainActor
    func testContentSizeLaunchArgumentReachesSwiftUI() throws {
        let screens = A11yScreens(self)
        for (variant, expected) in [(A11yVariant.large, "large"), (.xxxLarge, "xxxLarge"), (.ax3, "accessibility3")] {
            let app = screens.launchSpecimen(variant)
            let state = app.descendants(matching: .any)["specimen.state"].label
            XCTAssertTrue(state.contains("dts=\(expected);"), "\(variant): expected dynamicTypeSize \(expected), got \(state)")
        }
    }

    /// DESIGN.md's iOS type roles (plan 16): each renders at its contract size at Large and scales
    /// with its OWN text style's curve (`Font.custom(_:size:relativeTo:)`, i.e. `UIFontMetrics` for
    /// that style) at xxxLarge and AX3 — measured on the specimen by rendered width against a
    /// fixed-size reference in the same face (width is proportional to point size for a string).
    @MainActor
    func testTypeRolesRenderAtTheirContractSizeAndScaleWithTheirTextStyle() throws {
        let screens = A11yScreens(self)
        var failures: [String] = []
        for variant in [A11yVariant.large, .xxxLarge, .ax3] {
            let app = screens.launchSpecimen(variant)
            screens.attachScreenshot(named: "2a-specimen")
            print("A11Y metrics \(variant) \(app.staticTexts["specimen.metrics"].label)")
            for name in ["body", "footnote"] {
                let sys = app.staticTexts["specimen.sys.\(name)"].frame.width
                let ref = app.staticTexts["specimen.ref.system"].frame.width
                print("A11Y system \(variant) \(name) measured=\(Self.fmt(20 * sys / ref))")
            }
            failures += Self.offContractRoles(app, variant: variant) { $0.face }
        }
        XCTAssertTrue(failures.isEmpty, "Type roles off contract:\n" + failures.joined(separator: "\n"))
    }

    // MARK: - Bold Text

    /// Bold Text (Settings › Accessibility › Display & Text Size) draws each role in the next
    /// heavier bundled face — Book → Medium, Medium → Semibold; Semibold and Book Italic have no
    /// heavier bundled face and stay — at the same size. `--uitest-bold-text` sets SwiftUI's
    /// `legibilityWeight` to `.bold` at the root, which is what the setting does. The specimen's
    /// lab rows (logged) show what SwiftUI itself does with each way of naming a face.
    @MainActor
    func testBoldTextDrawsEachRoleOneFaceHeavier() throws {
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.largeBold)
        let state = app.descendants(matching: .any)["specimen.state"].label
        XCTAssertTrue(state.contains("lw=bold;"), "--uitest-bold-text should set legibilityWeight .bold, got \(state)")
        screens.attachScreenshot(named: "2a-specimen")
        Self.logBoldLab(app)

        let heavier = ["book": "medium", "medium": "semibold", "semibold": "semibold", "bookItalic": "bookItalic"]
        let failures = Self.offContractRoles(app, variant: .largeBold) { role in
            role.style == "fixed" ? role.face : heavier[role.face] ?? role.face
        }
        XCTAssertTrue(failures.isEmpty, "Under Bold Text:\n" + failures.joined(separator: "\n"))
    }

    /// The real setting, end to end and live: with the specimen running, Bold Text is switched on
    /// in Settings › Accessibility › Display & Text Size; back in the app — no relaunch, no rebuild
    /// of the view tree — the reading role now draws Medium at the same size, and switching it off
    /// again brings Book back. Restores the setting afterwards whatever happens.
    @MainActor
    func testTheRealBoldTextSettingRedrawsRolesLive() throws {
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        addTeardownBlock { @MainActor in A11yScreens.setBoldTextSetting(false) }
        let state = app.descendants(matching: .any)["specimen.state"]

        A11yScreens.setBoldTextSetting(true)
        app.activate()
        let bold = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "lw=bold;boldText=true"), object: state)
        XCTAssertEqual(XCTWaiter().wait(for: [bold], timeout: 10), .completed, "The app never saw Bold Text: \(state.label)")
        screens.attachScreenshot(named: "2a-specimen-bold-setting-on")
        let inMedium = Self.measuredSize(app, element: "specimen.role.reading", face: "medium") ?? 0
        XCTAssertEqual(inMedium, 17, accuracy: 0.4, "With Bold Text on, reading should draw Medium 17")

        A11yScreens.setBoldTextSetting(false)
        app.activate()
        let regular = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "boldText=false"), object: state)
        XCTAssertEqual(XCTWaiter().wait(for: [regular], timeout: 10), .completed, "The app never saw Bold Text go off: \(state.label)")
        let inBook = Self.measuredSize(app, element: "specimen.role.reading", face: "book") ?? 0
        XCTAssertEqual(inBook, 17, accuracy: 0.4, "With Bold Text off, reading should draw Book 17 again")
    }

    // MARK: - Baseline for the surface passes

    /// The plan-16 starting point for 2b/2c: Ask (a scripted exchange with a citation), Add, View
    /// and the permanent link fixture's detail sheet, at Large, xxxLarge, AX3 and Bold Text — the
    /// foundation in, no surface migrated yet. Attached as `a11y-2a-<screen>-<size>`; Xcode's audit
    /// findings per screen are logged (`A11Y audit …`) at Large and AX3 for the surface passes'
    /// lists. Asserts only that every screen comes up at every size.
    @MainActor
    func testBaselineScreensComeUpAtEveryTextSize() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in A11yVariant.matrix {
            var app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-seed-citation-bubble"])
            XCTAssertTrue(Self.element(app, "ask.input").waitForExistence(timeout: 10), "\(variant): Ask composer missing")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ask.bubble.1").firstMatch
                .waitForExistence(timeout: 10), "\(variant): seeded answer missing")
            sleep(1)
            screens.attachScreenshot(named: "2a-ask")
            try Self.logAudit(app, screen: "ask", variant: variant)

            app = screens.launch(variant, tab: .add)
            XCTAssertTrue(app.textViews["capture.editor"].waitForExistence(timeout: 10), "\(variant): Add editor missing")
            sleep(2)   // the backdrop's blurred tier fades in
            screens.attachScreenshot(named: "2a-add")
            try Self.logAudit(app, screen: "add", variant: variant)

            app = screens.launch(variant, tab: .view)
            XCTAssertTrue(Self.element(app, "card.0").waitForExistence(timeout: 20), "\(variant): no library cards")
            sleep(2)
            screens.attachScreenshot(named: "2a-view")
            try Self.logAudit(app, screen: "view", variant: variant)

            let search = app.textFields["library.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "\(variant): library search missing")
            A11yScreens.tapUntilFocused(search)
            search.typeText("link one")
            let fixture = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#,
                                      "UITEST-FIXTURE: link one"))
                .firstMatch
            XCTAssertTrue(fixture.waitForExistence(timeout: 20), "\(variant): the link fixture didn't list")
            fixture.tap()
            XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10), "\(variant): detail sheet missing")
            sleep(2)
            screens.attachScreenshot(named: "2a-detail-link")
            try Self.logAudit(app, screen: "detail-link", variant: variant)
        }
    }

    @MainActor
    private static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Logs Xcode's hit-region, Dynamic Type, contrast and clipped-text findings for the screen on
    /// show (Large and AX3 only — the audit takes a few seconds per screen).
    @MainActor
    private static func logAudit(_ app: XCUIApplication, screen: String, variant: A11yVariant) throws {
        guard variant == .large || variant == .ax3 else { return }
        try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast, .textClipped]) { issue in
            let element = issue.element
            let label = String((element?.label ?? "").prefix(48)).replacingOccurrences(of: "\n", with: " ")
            print("A11Y audit \(screen) \(variant) | \(issue.compactDescription) | id=\(element?.identifier ?? "-") "
                  + "label=\"\(label)\" frame=\(element.map { "\($0.frame.integral)" } ?? "-")")
            return true
        }
    }

    // MARK: - Measuring

    /// Every contract role whose rendered size (measured in the face `face(role)` names) is off
    /// its contract size at `variant`.
    @MainActor
    private static func offContractRoles(_ app: XCUIApplication, variant: A11yVariant,
                                         face: (Role) -> String) -> [String] {
        var failures: [String] = []
        for role in contract {
            let expected = expectedSize(role.size, style: role.style, category: variant.category)
            guard !expected.isNaN else {
                failures.append("\(variant) \(role.name): no \(role.style) size for \(variant.category) in the table")
                continue
            }
            guard let measured = measuredSize(app, element: "specimen.role.\(role.name)", face: face(role)) else {
                failures.append("\(variant) \(role.name): not on the specimen")
                continue
            }
            print("A11Y role \(variant) \(role.name) [\(face(role))] measured=\(fmt(measured)) expected=\(fmt(expected))")
            // Measuring error is ≤ 0.1 pt; a role on the wrong curve, or in the wrong face, is off
            // by ≥ 1 pt at AX3 (and ≥ 3.5 % at any size for the face).
            if abs(measured - expected) > 0.4 {
                failures.append("\(variant) \(role.name): \(fmt(measured)) pt in \(face(role)), expected \(fmt(expected)) (\(role.size) pt · .\(role.style))")
            }
        }
        return failures
    }

    /// Logs each lab row's width with regular vs bold legibility weight (`A11Y lab …` lines).
    @MainActor
    private static func logBoldLab(_ app: XCUIApplication) {
        for name in ["custom.book", "custom.bookItalic", "custom.medium", "custom.semibold",
                     "family.regular", "family.medium", "system"] {
            let regular = app.staticTexts["specimen.lab.regular.\(name)"].frame.width
            let bold = app.staticTexts["specimen.lab.bold.\(name)"].frame.width
            print("A11Y lab \(name) regular=\(fmt(regular)) bold=\(fmt(bold))")
        }
        for face in ["book", "bookItalic", "medium", "semibold"] {
            print("A11Y ref \(face) width=\(fmt(app.staticTexts["specimen.ref.\(face)"].frame.width))")
        }
    }

    private static func fmt(_ value: CGFloat) -> String { String(format: "%.2f", value) }

    // MARK: - Contract

    private struct Role {
        let name: String
        let face: String
        let size: CGFloat
        let style: String
    }

    /// DESIGN.md › Typography › iOS type roles.
    private static let contract: [Role] = [
        Role(name: "display", face: "semibold", size: 32, style: "largeTitle"),
        Role(name: "panelTitle", face: "medium", size: 28, style: "title"),
        Role(name: "screenTitle", face: "medium", size: 22, style: "title2"),
        Role(name: "cardTitle", face: "medium", size: 20, style: "title3"),
        Role(name: "reading", face: "book", size: 17, style: "body"),
        Role(name: "readingMedium", face: "medium", size: 17, style: "body"),
        Role(name: "readingSemibold", face: "semibold", size: 17, style: "body"),
        Role(name: "readingItalic", face: "bookItalic", size: 17, style: "body"),
        Role(name: "secondary", face: "book", size: 15, style: "subheadline"),
        Role(name: "secondaryMedium", face: "medium", size: 15, style: "subheadline"),
        Role(name: "secondaryItalic", face: "bookItalic", size: 15, style: "subheadline"),
        Role(name: "meta", face: "book", size: 13, style: "footnote"),
        Role(name: "metaMedium", face: "medium", size: 13, style: "footnote"),
        Role(name: "chip", face: "medium", size: 12, style: "caption"),
        Role(name: "microLabel", face: "semibold", size: 12, style: "caption"),
        Role(name: "kicker", face: "semibold", size: 12, style: "caption"),
        Role(name: "textButton", face: "book", size: 17, style: "body"),
        Role(name: "textButtonProminent", face: "medium", size: 17, style: "body"),
        Role(name: "inlineButton", face: "medium", size: 15, style: "subheadline"),
        // Arbitrary sizes default to the nearest text style; the decorative helper never scales.
        Role(name: "font.book.14", face: "book", size: 14, style: "subheadline"),
        Role(name: "font.medium.24", face: "medium", size: 24, style: "title2"),
        Role(name: "font.book.9", face: "book", size: 9, style: "caption2"),
        Role(name: "font.semibold.11.caption", face: "semibold", size: 11, style: "caption"),
        Role(name: "decorative.book.9", face: "book", size: 9, style: "fixed"),
    ]

    private static let textStyles: [String: UIFont.TextStyle] = [
        "largeTitle": .largeTitle, "title": .title1, "title2": .title2, "title3": .title3,
        "body": .body, "subheadline": .subheadline, "footnote": .footnote,
        "caption": .caption1, "caption2": .caption2,
    ]

    /// The size a role of default `size` scaling with `style` renders at for `category` (a
    /// `UIContentSizeCategory` raw value): iOS scales custom fonts with `UIFontMetrics` — a curve a
    /// little flatter than the system text styles' own sizes at the top end (body 17 → 22.3 at
    /// xxxLarge where SF body is 23; 37 at AX3 where SF is 40) — and SwiftUI draws the nearest
    /// whole point. Measured to match on iOS 17.0 and 26.5 (plan 16). `fixed` never scales.
    private static func expectedSize(_ size: CGFloat, style: String, category: String) -> CGFloat {
        if style == "fixed" { return size }
        guard let textStyle = textStyles[style] else { return .nan }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(rawValue: category))
        return UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size, compatibleWith: traits).rounded()
    }

    /// The point size `element` renders at: 20 × its width ÷ the width of the same sample in
    /// `face` at a fixed 20 pt (`specimen.ref.<face>`, pinned to regular legibility weight).
    @MainActor
    private static func measuredSize(_ app: XCUIApplication, element: String, face: String) -> CGFloat? {
        let sample = app.staticTexts[element]
        let reference = app.staticTexts["specimen.ref.\(face)"]
        guard sample.exists, reference.exists, reference.frame.width > 0 else { return nil }
        return 20 * sample.frame.width / reference.frame.width
    }
}
