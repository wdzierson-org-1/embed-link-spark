import UIKit
import XCTest

/// Plan 16, Task 2a — the accessibility foundation: shared controls take taps across a 44×44 pt
/// target without their visuals moving; every `StashType` role renders at its contract size,
/// scales with its own text style and draws one face heavier under Bold Text (the real setting
/// too, live, and the DEBUG hook on every screen); Xcode's hit-region, Dynamic Type and contrast
/// audits pass the specimen; the Dynamic Type launch argument the screenshot matrix relies on
/// reaches SwiftUI; and the baseline screens come up at every size. Most checks run on the DEBUG
/// type specimen (`--uitest-type-specimen`: signed out, no network); the Ask checks run on the real
/// screen with scripted answers.
///
/// Fix wave (2a review): the Bold Text hook reaches tabs and sheets; `StashCancelButton` never
/// breaks mid-word and never moves its header; markdown emphasis renders in the role's faces;
/// selection and toggle state reach VoiceOver; `.stashPlain` and `stashLeading`.
final class A11yFoundationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The real Bold Text setting is simulator-global; a killed earlier run can leave it on.
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    // MARK: - Hit areas

    /// Will: "Some elements … appear smaller than iOS standard guidelines". Ask's header circles
    /// stay 36 pt (`CircleIcon(size: 36)`), exactly where they were, and now report their 44×44 pt
    /// tap target as their accessibility frame; a tap 2.5 pt past the History circle's right edge
    /// (1.5 pt inside the target) opens Conversations. (On its own this screen can't fail without
    /// the fix — over empty space SwiftUI's touch-radius tolerance reaches the circle anyway — so
    /// the RED/GREEN proof is the specimen test below; this one pins the real header's layout and
    /// target.)
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

        A11yScreens.tap(app, at: CGPoint(x: history.frame.midX + 18 + 2.5, y: history.frame.midY))
        XCTAssertTrue(app.textFields["convos.search"].waitForExistence(timeout: 5),
                      "A tap 2.5 pt past the History circle's edge should open Conversations")
    }

    /// Hardware keyboards: ⌘. is the keyboard Cancel (`StashCancelButton`'s `.cancelAction`) — on
    /// Ask, as anywhere it shows, the keyboard goes and the draft stays. (Plain Esc, the other
    /// `.cancelAction` key, never reaches the shortcut: the focused text field keeps it — probed on
    /// iOS 17.0, where a typed "z" landed in the field and Esc changed nothing.)
    ///
    /// SIDE EFFECT ON THE SIMULATOR (polish batch, item 6; measured on iOS 17.5 and 26.5): `typeKey`
    /// is a hardware-keyboard event, and after one iOS records it in the simulator's own
    /// `com.apple.keyboard.preferences` — `AutomaticMinimizationEnabled` (and, on iOS 17,
    /// `KeyboardHardwareKeyboardsSeen`). The on-screen keyboard still comes up for the rest of that
    /// boot, so nothing fails at once; from the simulator's NEXT boot it is minimized — in the tree
    /// but parked below the screen (y 897 on an 852 pt screen) — in every app, every launch, and
    /// every test that asserts the keyboard's frame fails "Expected the keyboard on screen"
    /// (`AskUITests.testALongThreadKeepsItsEndWhenTheKeyboardComesUp`, …). Restarting the simulator
    /// does not undo it; it is where the damage shows, which is why the failures look intermittent.
    /// Restore, with the simulator booted (the next app launch picks it up):
    ///
    ///     xcrun simctl spawn <udid> defaults delete com.apple.keyboard.preferences AutomaticMinimizationEnabled
    ///
    /// So: keep this test out of the main run of a simulator that keyboard suites share
    /// (`-skip-testing:StashUITests/A11yFoundationUITests/testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel`),
    /// run it last, and restore afterwards. `ios/README.md` › UI tests has the runner recipe. This
    /// test itself still passes on a simulator in that state (measured on 17.5), so it doesn't
    /// explain this test's own failures. (Other `typeKey` callers — ⌘A in `testEditSmoke`'s title
    /// clear and in `A11yDetailLibraryUITests.openDetail` — send the same kind of event; only ⌘. was
    /// measured.) Never toggle the Simulator app's own "Connect Hardware Keyboard": it is shared with
    /// every other session on the Mac.
    @MainActor
    func testCommandPeriodOnAHardwareKeyboardIsTheKeyboardCancel() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat"])
        let input = Self.element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask composer missing")
        A11yScreens.tapUntilFocused(input)
        input.typeText("Keep this draft")
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing")

        app.typeKey(".", modifierFlags: .command)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "⌘. should put the keyboard away like Cancel")
        XCTAssertEqual(input.value as? String, "Keep this draft", "⌘. must keep the draft")
        XCTAssertTrue(app.buttons["ask.history"].waitForExistence(timeout: 5), "The header circles should be back")
        // Said here, where the failures it causes will be read (see the doc comment above).
        print("A11Y state: this test sent a hardware-keyboard event (⌘.). From this simulator's next boot its on-screen "
              + "keyboard stays minimized until: xcrun simctl spawn <udid> defaults delete "
              + "com.apple.keyboard.preferences AutomaticMinimizationEnabled (ios/README.md › UI tests)")
    }

    /// The shared controls in `Design/` — `CircleIcon` (36 pt and its 40 pt default),
    /// `CircleSubmitIcon` at the composer's 40 pt, and `PillTabs` — take every tap inside a
    /// 44×44 pt target centred on them, even over a tappable surface; a tap past that target goes
    /// to the surface. (Over empty space SwiftUI's touch-radius tolerance, ~16 pt with a
    /// synthesized XCUITest touch, would hide the difference — hence the specimen's surface.) Taps
    /// land 1.5 pt inside the target's edge where the geometry allows; a 40 pt circle leaves only
    /// 2 pt between its edge and the target's, so its taps split that (1 pt past, 1 pt inside).
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
            XCTAssertTrue(A11yScreens.waitForLabel(taps, expected),
                          "Tap \(gap) pt past \(identifier): expected \(expected), got \(taps.label)", line: line)
        }

        tapPast("specimen.circle36", diameter: 36, gap: 2.5, expect: "circle36=1")
        tapPast("specimen.circle36", diameter: 36, gap: 2.5, below: true, expect: "circle36=2")
        tapPast("specimen.circle36", diameter: 36, gap: 6, expect: "surface=1")   // 2 pt past the 44 pt target
        tapPast("specimen.circle40", diameter: 40, gap: 1, expect: "circle40=1")
        tapPast("specimen.submit40", diameter: 40, gap: 1, below: true, expect: "submit40=1")

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
        XCTAssertTrue(A11yScreens.waitForLabel(taps, "tab=two", condition: "ENDSWITH"),
                      "A tap beside the tab's word should select it, got \(taps.label)")
        summary.tap()
        XCTAssertTrue(A11yScreens.waitForLabel(taps, "tab=one", condition: "ENDSWITH"), "Summary should be selected again, got \(taps.label)")
        // Just above the pill: inside a 44 pt target centred on the tab (the pill is ~32 pt tall,
        // so this is ~3 pt inside the target's edge).
        A11yScreens.tap(app, at: CGPoint(x: notesTab.midX, y: notesTab.minY - 3))
        let expected = "circle36=2 circle40=1 submit40=1 glyph=0 cancel=0 surface=1 tab=two"
        XCTAssertTrue(A11yScreens.waitForLabel(taps, expected, condition: "=="), "Expected \(expected), got \(taps.label)")
    }

    /// The text and glyph controls (fix wave, M4 + I2): a bare glyph button on
    /// `.buttonStyle(.stashPlain)` — the style that builds the 44 pt target in, so it can't be put
    /// on the wrong view — and `StashCancelButton`, whose 44 pt target now overhangs the word
    /// instead of growing its layout, each take a tap 1.5 pt inside their target's edge over a
    /// tappable surface, and a tap 2 pt past it goes to the surface. Each reports its target as its
    /// accessibility frame (T1's "Cancel ≥ 44×44" holds with the overhang).
    @MainActor
    func testGlyphAndTextButtonsTakeTapsAcrossA44PointTarget() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        let taps = app.staticTexts["specimen.taps"]
        XCTAssertTrue(taps.waitForExistence(timeout: 5), "Tap counter missing")

        let glyph = app.buttons["specimen.glyph"]
        XCTAssertTrue(glyph.exists, "The .stashPlain glyph button is missing")
        print("A11Y controls glyph frame=\(glyph.frame)")
        XCTAssertGreaterThanOrEqual(glyph.frame.width, 43.5, ".stashPlain: the glyph's target should be 44 pt wide")
        XCTAssertGreaterThanOrEqual(glyph.frame.height, 43.5, ".stashPlain: the glyph's target should be 44 pt tall")
        // 20.5 pt right of its centre: ~12 pt past the 17 pt glyph, 1.5 pt inside the target.
        A11yScreens.tap(app, at: CGPoint(x: glyph.frame.midX + 20.5, y: glyph.frame.midY))
        XCTAssertTrue(A11yScreens.waitForLabel(taps, "glyph=1"), "A tap inside the .stashPlain target: got \(taps.label)")
        A11yScreens.tap(app, at: CGPoint(x: glyph.frame.midX, y: glyph.frame.midY + 24))   // 2 pt past it
        XCTAssertTrue(A11yScreens.waitForLabel(taps, "surface=1"), "A tap past the .stashPlain target: got \(taps.label)")

        let cancel = app.buttons["specimen.cancel.surface"]
        XCTAssertTrue(cancel.exists, "The surface Cancel is missing")
        print("A11Y controls cancel frame=\(cancel.frame)")
        // 43.5, not 44: frames sit on the 1/3 pt pixel grid, and a fractional origin reads back
        // as e.g. 43.99999999999994 (measured on iOS 26.5).
        XCTAssertGreaterThanOrEqual(cancel.frame.width, 43.5, "Cancel's hit area is narrower than 44 pt")
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 43.5, "Cancel's hit area is shorter than 44 pt")
        // 20.5 pt above the word's centre: ~10 pt above the 17 pt word, 1.5 pt inside the target.
        A11yScreens.tap(app, at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY - 20.5))
        XCTAssertTrue(A11yScreens.waitForLabel(taps, "cancel=1"), "A tap inside Cancel's target: got \(taps.label)")
        A11yScreens.tap(app, at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY + 24))   // 2 pt past it
        XCTAssertTrue(A11yScreens.waitForLabel(taps, "surface=2"), "A tap past Cancel's target: got \(taps.label)")
    }

    /// VoiceOver (fix wave, I4; WCAG 4.1.2): the selected pill tab carries the Selected trait and
    /// the other doesn't, following the selection; a toggle icon control
    /// (`stashIconControl(_:systemImage:isOn:)` — the location pin, the public globe) reports "Off" /
    /// "On" as its value and carries the toggle trait.
    @MainActor
    func testSelectionAndToggleStateReachVoiceOver() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        let summary = app.buttons["specimen.tab.one"], notes = app.buttons["specimen.tab.two"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Pill tabs missing")
        XCTAssertTrue(summary.isSelected, "The selected tab (Summary) should carry the Selected trait")
        XCTAssertFalse(notes.isSelected, "An unselected tab (Notes) must not carry the Selected trait")
        notes.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: notes)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 3), .completed, "Notes should carry Selected once chosen")
        XCTAssertFalse(summary.isSelected, "Summary should lose Selected once Notes is chosen")

        let pin = app.descendants(matching: .any)["specimen.pin"]
        XCTAssertTrue(pin.exists, "The toggle circle is missing")
        print("A11Y toggle type=\(pin.elementType.rawValue) value=\(String(describing: pin.value)) label=\(pin.label)")
        XCTAssertEqual(pin.label, "Specimen location pin")
        XCTAssertEqual(pin.value as? String, "Off", "A toggle icon control should report Off")
        pin.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "On"), object: pin)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 3), .completed, "…and On once toggled, got \(String(describing: pin.value))")
        print("A11Y toggle after tap type=\(pin.elementType.rawValue) value=\(String(describing: pin.value)) "
              + "toggles=\(app.toggles["specimen.pin"].exists) switches=\(app.switches["specimen.pin"].exists) "
              + "buttons=\(app.buttons["specimen.pin"].exists)")
        XCTAssertTrue(app.toggles["specimen.pin"].exists || app.switches["specimen.pin"].exists,
                      "A toggle icon control should carry the toggle trait (element type \(pin.elementType.rawValue))")
    }

    /// Xcode's own accessibility audit agrees: no shared control is flagged for its hit region
    /// (before plan 16 the unselected pill tab was — "Hit area is too small", its frame just the
    /// word) and no role for Dynamic Type (chip, micro-label and kicker at 11 pt were "partially
    /// unsupported"); `StashCancelButton` on paper and over the gradient wash (`onWash`) and a
    /// `muted` `prompt:` placeholder pass contrast. The decorative row and the fixed-size
    /// yardsticks are exempt by design, and the pill tabs' deliberate xxxLarge cap reads as
    /// "partially unsupported". Everything else the audit says is logged (`A11Y audit …`).
    @MainActor
    func testSpecimenPassesXcodesHitRegionDynamicTypeAndContrastAudits() throws {
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        var flagged: [String] = []
        var sawVioletOnWash = false
        let controls: Set<String> = ["specimen.cancel.wash", "specimen.cancel.plain", "specimen.cancel.surface",
                                     "specimen.glyph", "specimen.pin"]
        try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast]) { issue in
            let id = issue.element?.identifier ?? ""
            print("A11Y audit \(issue.compactDescription) | \(id) \"\(issue.element?.label ?? "")\"")
            if issue.auditType == .contrast, id == "specimen.wash.violet600" { sawVioletOnWash = true }
            let isControl = id.hasPrefix("specimen.circle") || id.hasPrefix("specimen.submit") || id.hasPrefix("specimen.tab.")
                || controls.contains(id)
            let isRole = id.hasPrefix("specimen.role.") && !id.hasPrefix("specimen.role.decorative")
            switch issue.auditType {
            case .hitRegion where isControl || isRole,
                 .dynamicType where isRole,
                 .contrast where id.hasPrefix("specimen.cancel.") || id == "specimen.placeholder.muted":
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

    // MARK: - StashCancelButton

    /// Fix wave (I1 + I2). Layout: `StashCancelButton` appearing in a `StashHeader` (the Add tab's)
    /// moves nothing — its 44 pt target overhangs the word (and `onWash`'s capsule is drawn past
    /// it) instead of growing the row, so the header's LAYOUT height (`specimen.header.heights`,
    /// measured with `onGeometryChange`) is within 1 pt of its resting height. Words: at AX3 and
    /// AX5, squeezed by big neighbours, each Cancel — over the wash and on paper — is still one
    /// line holding the whole word, never "Canc / el" (the review's AX3 shots).
    @MainActor
    func testStashCancelButtonStaysOneWordAndNeverMovesItsHeader() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        var app = screens.launchSpecimen(.large)
        let heights = app.staticTexts["specimen.header.heights"]
        XCTAssertTrue(A11yScreens.waitForLabel(heights, "composing=", timeout: 5), "No StashHeader heights on the specimen")
        let values = Self.numbers(in: heights.label)   // resting, composing
        print("A11Y cancel header \(heights.label)")
        if values.count == 2 {
            XCTAssertGreaterThan(values[0], 0, "The resting header has no height")
            XCTAssertLessThanOrEqual(values[1] - values[0], 1,
                                     "The header grew \(values[1] - values[0]) pt when Cancel appeared — it must not jump")
        } else {
            XCTFail("Unreadable header heights: \(heights.label)")
        }

        for variant in [A11yVariant.ax3, .ax5] {
            app = screens.launchSpecimen(variant)
            screens.attachScreenshot(named: "2a-specimen-cancel")
            let line = app.staticTexts["specimen.role.textButton"].frame.height      // one line of the role
            let word = app.staticTexts["specimen.ref.cancelWord"].frame.width        // the whole word, one line
            XCTAssertGreaterThan(line, 0, "No textButton reference line")
            for (identifier, padding) in [("specimen.cancel.wash", CGFloat(24)), ("specimen.cancel.plain", 0)] {
                let cancel = app.buttons[identifier]
                XCTAssertTrue(cancel.exists, "\(identifier) missing")
                print("A11Y cancel \(variant) \(identifier) frame=\(cancel.frame) line=\(Self.fmt(line)) word=\(Self.fmt(word))")
                XCTAssertLessThan(cancel.frame.height, 1.5 * line, "\(identifier) wrapped at \(variant): "
                                  + "\(Self.fmt(cancel.frame.height)) pt tall, one line is \(Self.fmt(line))")
                XCTAssertGreaterThanOrEqual(cancel.frame.width, word + padding - 0.5,
                                            "\(identifier) is narrower than the word itself at \(variant) — broken or truncated")
            }
        }
    }

    /// Empirical check (2a review, check 4): Ask's own Cancel, beside the wrapping 41 pt title at
    /// AX3 with the composer focused, is one line (≈1.2 em tall; two lines would be ≈2.4 em) and
    /// holds the whole word (≈2.9 em wide; "Canc" alone is ≈2.2).
    @MainActor
    func testAskCancelStaysOneLineAtAccessibilitySizes() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.ax3, tab: .ask, arguments: ["--uitest-scripted-chat"])
        let input = Self.element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask composer missing")
        A11yScreens.tapUntilFocused(input)
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing")
        screens.attachScreenshot(named: "2a-ask-cancel")
        let em = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: A11yVariant.ax3.traits).rounded()
        print("A11Y cancel ask AX3 frame=\(cancel.frame) em=\(Self.fmt(em))")
        XCTAssertLessThan(cancel.frame.height, 1.7 * em, "Ask's Cancel wrapped at AX3 (\(Self.fmt(cancel.frame.height)) pt tall)")
        XCTAssertGreaterThan(cancel.frame.width, 2.4 * em, "Ask's Cancel is narrower than the word at AX3")
    }

    // MARK: - Markdown emphasis and leading

    /// Fix wave (I3): inline emphasis in text set with a role — markdown `**strong**` / `*emphasis*`
    /// runs (`AttributedString(markdown:)`; TipTap's bold/italic marks and headings carry the same
    /// `inlinePresentationIntent`) in a `Text` with `.stashFont(.reading)` — renders in the bundled
    /// faces: strong in Semibold, emphasis in Book Italic, the rest in the role's face, at regular
    /// weight and under Bold Text (where the base is Medium; Semibold and Book Italic have nothing
    /// heavier). A heading that passes its role to the Text (`.stashFont(.readingSemibold)`) is
    /// Semibold. Measured, not assumed: SwiftUI resolves the intents against the custom face itself,
    /// so no styling helper is needed — the rule is only where the role goes. Logged too: `***both***`,
    /// inline code, `.bold()` / `.italic()`, and the dead-heading pattern (a role set outside a view
    /// whose Text sets its own stays Book). Strong is told apart by width (the faces differ by
    /// ≥ 3.5 %); italic by 1:1 crops, since Book Italic and Book are the same width (attached as
    /// `a11y-2af-md-*`).
    @MainActor
    func testMarkdownEmphasisRendersInTheRoleFaces() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        var failures: [String] = []
        for variant in [A11yVariant.large, .largeBold] {
            let app = screens.launchSpecimen(variant)
            let base = variant.bold ? "medium" : "book"
            A11yScreens.scrollIntoView(app, app.staticTexts["specimen.md.deadHeading"])
            let crops = Self.crops(app, variant: variant, rows: [
                "md.ref.reading", "md.ref.readingItalic", "md.ref.readingSemibold",
                "md.strong", "md.emphasis", "md.strongEmphasis", "md.code", "md.bold", "md.italic",
                "md.heading", "md.deadHeading",
            ])
            func italicDistances(_ row: String) -> (italic: Double, upright: Double) {
                (Self.inkDistance(crops[row], crops["md.ref.readingItalic"]),
                 Self.inkDistance(crops[row], crops["md.ref.reading"]))
            }
            let apart = Self.inkDistance(crops["md.ref.reading"], crops["md.ref.readingItalic"])
            print("A11Y md calibration \(variant): upright \(base) vs Book Italic=\(Self.fmt(apart))")

            // Asserted: what the surfaces rely on.
            for (row, face) in [("md.strong", "semibold"), ("md.heading", "semibold")] {
                let size = Self.measuredSize(app, element: "specimen.\(row)", face: face) ?? 0
                print("A11Y md \(variant) \(row): \(Self.fmt(size)) pt in \(face) "
                      + "(nearest upright face \(Self.nearestFace(app, "specimen.\(row)", size: 17)))")
                if abs(size - 17) > 0.3 { failures.append("\(variant) \(row): \(Self.fmt(size)) pt measured in \(face), expected 17") }
            }
            let d = italicDistances("md.emphasis")
            print("A11Y md \(variant) md.emphasis: ink distance to Book Italic=\(Self.fmt(d.italic)) to upright \(base)=\(Self.fmt(d.upright))")
            if !(d.italic < 0.15 && d.italic < d.upright / 3) {
                failures.append("\(variant) md.emphasis: not Book Italic (distance \(Self.fmt(d.italic)) to it, "
                                + "\(Self.fmt(d.upright)) to upright \(base))")
            }

            // Logged: the rest of the picture for DESIGN.md.
            for row in ["md.bold", "md.strongEmphasis", "md.deadHeading"] {
                let italic = italicDistances(row)
                print("A11Y md \(variant) \(row): nearest upright face \(Self.nearestFace(app, "specimen.\(row)", size: 17)); "
                      + "ink distance to Book Italic=\(Self.fmt(italic.italic))")
            }
            let italic = italicDistances("md.italic")
            print("A11Y md \(variant) md.italic: ink distance to Book Italic=\(Self.fmt(italic.italic)) to upright \(base)=\(Self.fmt(italic.upright))")
            let code = app.staticTexts["specimen.md.code"].frame.width, mono = app.staticTexts["specimen.md.ref.monoBody"].frame.width
            print("A11Y md \(variant) md.code: width=\(Self.fmt(code)) vs SF Mono body=\(Self.fmt(mono)); "
                  + "nearest upright face \(Self.nearestFace(app, "specimen.md.code", size: 17))")
        }
        XCTAssertTrue(failures.isEmpty, "Markdown emphasis off the role faces:\n" + failures.joined(separator: "\n"))
    }

    /// Fix wave (M3): `.stashLeading(0.55, role: .reading)` adds 0.55 em of the role's size between
    /// lines and scales it with the role's text style, like the text — 9.35 pt at Large — where the
    /// old `lineSpacing(14 * 0.55)` constant stayed 7.7 pt at every size. 2b fix wave: at the
    /// accessibility sizes the gap tapers to at most 0.35 em (12.95 pt at AX3; it was 20.35).
    @MainActor
    func testStashLeadingScalesWithTheRolesTextStyle() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        for variant in [A11yVariant.large, .ax3] {
            let app = screens.launchSpecimen(variant)
            let none = app.staticTexts["specimen.leading.none"], leading = app.staticTexts["specimen.leading.reading055"]
            XCTAssertTrue(none.exists && leading.exists, "\(variant): leading rows missing")
            let measured = leading.frame.height - none.frame.height
            // The taper keys on SwiftUI's `isAccessibilitySize` (AX1–AX5), so any AX variant expects 0.35.
            let em: CGFloat = variant.category.contains("Accessibility") ? 0.35 : 0.55
            let expected = UIFontMetrics(forTextStyle: .body).scaledValue(for: em * 17, compatibleWith: variant.traits)
            print("A11Y leading \(variant) measured=\(Self.fmt(measured)) expected=\(Self.fmt(expected))")
            XCTAssertEqual(measured, expected, accuracy: 0.5, "\(variant): the line spacing should be \(em) em of the scaled reading size")
        }
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
    /// heavier bundled face and stay — at the same size. `--uitest-bold-text` sets the window
    /// scene's legibility-weight trait, which is what the setting does, so it reaches every hosting
    /// controller: the specimen's own state line, the same line in a NavigationStack and in a
    /// sheet, and both state lines of the specimen inside a root `TabView` — where `MainTabView`
    /// puts every real screen (fix wave, C1: the old SwiftUI-environment hook stopped at the root
    /// TabView's tabs and at sheets — RED on both — so no real screen's L-bold shot was bold). The
    /// specimen's lab rows (logged) show what SwiftUI itself does with each way of naming a face.
    @MainActor
    func testBoldTextDrawsEachRoleOneFaceHeavier() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.largeBold)
        let state = app.descendants(matching: .any)["specimen.state"].label
        XCTAssertTrue(state.contains("lw=bold;boldText=false"), "--uitest-bold-text should set legibilityWeight .bold "
                      + "(and leave the real setting off), got \(state)")
        screens.attachScreenshot(named: "2a-specimen")
        Self.logBoldLab(app)

        let heavier = ["book": "medium", "medium": "semibold", "semibold": "semibold", "bookItalic": "bookItalic"]
        let failures = Self.offContractRoles(app, variant: .largeBold) { role in
            role.style == "fixed" ? role.face : heavier[role.face] ?? role.face
        }
        XCTAssertTrue(failures.isEmpty, "Under Bold Text:\n" + failures.joined(separator: "\n"))

        // Across hosting boundaries: a NavigationStack (Ask), a sheet (the detail sheet)…
        let nav = app.descendants(matching: .any)["specimen.nav.state"]
        A11yScreens.scrollIntoView(app, nav)
        XCTAssertTrue(nav.waitForExistence(timeout: 5), "The NavigationStack probe is missing")
        print("A11Y bold hook specimen.nav.state: \(nav.label)")
        XCTAssertTrue(nav.label.contains("lw=bold;"), "--uitest-bold-text must reach a NavigationStack, got \(nav.label)")
        let open = app.buttons["specimen.sheet.open"]
        A11yScreens.scrollIntoView(app, open)
        open.tap()
        let sheetState = app.descendants(matching: .any)["specimen.sheet.state"]
        XCTAssertTrue(sheetState.waitForExistence(timeout: 5), "The sheet probe didn't open")
        print("A11Y bold hook specimen.sheet.state: \(sheetState.label)")
        XCTAssertTrue(sheetState.label.contains("lw=bold;"), "--uitest-bold-text must reach a sheet, got \(sheetState.label)")
        screens.attachScreenshot(named: "2a-specimen-sheet-probe")
        app.buttons["specimen.sheet.close"].tap()

        // …and a root TabView's tabs, where MainTabView puts every real screen: the specimen's own
        // state line in the first tab, a bare one in the second.
        let tabbedApp = screens.launchSpecimen(.largeBold, arguments: ["--uitest-specimen-tabbed"])
        for (probe, tab) in [("specimen.state", "Specimen"), ("specimen.tabbed.state", "Probe")] {
            tabbedApp.tabBars.buttons[tab].tap()
            let state = tabbedApp.descendants(matching: .any)[probe]
            XCTAssertTrue(state.waitForExistence(timeout: 5), "\(probe) is missing (root TabView, tab \(tab))")
            print("A11Y bold hook root TabView \(probe): \(state.label)")
            XCTAssertTrue(state.label.contains("lw=bold;"), "--uitest-bold-text must reach a root TabView tab (\(probe)), got \(state.label)")
        }
    }

    /// The real setting, end to end and live: with the specimen running, Bold Text is switched on
    /// in Settings › Accessibility › Display & Text Size; back in the app — no relaunch, no rebuild
    /// of the view tree — the reading role now draws Medium at the same size, and switching it off
    /// again brings Book back. `enableBoldTextSetting(for:)` registers the restore before it
    /// switches anything, so it runs whatever happens.
    @MainActor
    func testTheRealBoldTextSettingRedrawsRolesLive() throws {
        let screens = A11yScreens(self)
        let app = screens.launchSpecimen(.large)
        let state = app.descendants(matching: .any)["specimen.state"]
        XCTAssertTrue(state.label.contains("boldText=false"), "The real setting should start off: \(state.label)")

        A11yScreens.enableBoldTextSetting(for: self)
        app.activate()
        let bold = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "lw=bold;boldText=true"), object: state)
        XCTAssertEqual(XCTWaiter().wait(for: [bold], timeout: 10), .completed, "The app never saw Bold Text: \(state.label)")
        // The suite-start guard reads the setting in the runner's own process; it must see it too.
        print("A11Y state runner sees boldText=\(UIAccessibility.isBoldTextEnabled) while it is on")
        XCTAssertTrue(UIAccessibility.isBoldTextEnabled, "The test runner doesn't see the real setting — "
                      + "restoreRealBoldTextIfLeftOn() couldn't detect a leak")
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

            try Self.openLinkFixture(app, variant: variant)
            sleep(2)
            screens.attachScreenshot(named: "2a-detail-link")
            try Self.logAudit(app, screen: "detail-link", variant: variant)
        }
    }

    // MARK: - Large Content Viewer (host-driven probe)

    /// Empirical check (2a review, check 3) — NOT part of the normal run: XCUITest can't look at
    /// the screen while `press(forDuration:)` holds, so the host has to. Run it alone with
    /// `TEST_RUNNER_A11Y_LCV_PROBE=1` while the host shoots the simulator every second
    /// (`xcrun simctl io <udid> screenshot …`); each `A11Y lcv press …` line marks an 8 s press at
    /// AX3 on: a specimen pill tab, the specimen's 36 pt circle, the detail sheet's "Original
    /// Content" tab, and Ask's History circle.
    @MainActor
    func testLargeContentViewerProbe() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["A11Y_LCV_PROBE"] == "1",
                          "Host-driven probe: run alone with TEST_RUNNER_A11Y_LCV_PROBE=1 (see the doc comment)")
        let screens = A11yScreens(self)
        var app = screens.launchSpecimen(.ax3)
        for identifier in ["specimen.tab.two", "specimen.circle36"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(identifier) missing")
            print("A11Y lcv press \(identifier) at \(Date().timeIntervalSince1970)")
            control.press(forDuration: 8)
            sleep(2)
        }

        try screens.signIn()
        app = screens.launch(.ax3, tab: .view)
        try Self.openLinkFixture(app, variant: .ax3)
        let original = app.buttons["Original Content"]
        XCTAssertTrue(original.waitForExistence(timeout: 10), "no Original Content tab")
        A11yScreens.scrollIntoView(app, original)
        print("A11Y lcv press detail Original Content at \(Date().timeIntervalSince1970)")
        original.press(forDuration: 8)
        sleep(2)

        app = screens.launch(.ax3, tab: .ask, arguments: ["--uitest-scripted-chat"])
        let history = app.buttons["ask.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), "History missing")
        print("A11Y lcv press ask.history at \(Date().timeIntervalSince1970)")
        history.press(forDuration: 8)
        sleep(2)
    }

    @MainActor
    private static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// On the View tab: searches for the permanent link fixture ("UITEST-FIXTURE: link one") and
    /// opens its detail sheet. The shared test account's first page is often all freshly seeded
    /// rows, so the fixture lists only once the server search answers; one fixture miss in the fix
    /// wave's runs (20 s, a busy account) passed on the next run, so a miss retypes the query once.
    @MainActor
    private static func openLinkFixture(_ app: XCUIApplication, variant: A11yVariant,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "\(variant): library search missing", file: file, line: line)
        let fixture = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#,
                                  "UITEST-FIXTURE: link one"))
            .firstMatch
        A11yScreens.tapUntilFocused(search)
        search.typeText("link one")
        if !fixture.waitForExistence(timeout: 20) {
            print("A11Y fixture: not listed after 20 s at \(variant) — retyping the query once")
            A11yScreens.tapUntilFocused(search)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "link one")
        }
        XCTAssertTrue(fixture.waitForExistence(timeout: 20), "\(variant): the link fixture didn't list", file: file, line: line)
        fixture.tap()
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10), "\(variant): detail sheet missing",
                      file: file, line: line)
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
            // Measuring error is ≤ 0.1 pt; a role on the wrong curve is off by ≥ 1 pt at AX3, and
            // one in the wrong face by ≥ 3.5 % at any size. So the tolerance is 0.4 pt, and 2.5 %
            // below 16 pt, where 0.4 pt would no longer tell faces apart (9 pt Book vs Medium
            // measures 9.00 vs 9.32).
            if abs(measured - expected) > min(0.4, 0.025 * expected) {
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
    private static func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    /// The decimal numbers in a probe label, in order (`resting=32.00;composing=33.00` → [32, 33]).
    private static func numbers(in label: String) -> [CGFloat] {
        label.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }.map { CGFloat($0) }
    }

    /// The upright face whose width puts `element` closest to `size` pt — which face a row drew in.
    @MainActor
    private static func nearestFace(_ app: XCUIApplication, _ element: String, size: CGFloat) -> String {
        let sizes = ["book", "medium", "semibold"].compactMap { face in
            measuredSize(app, element: element, face: face).map { (face, $0) }
        }
        guard let best = sizes.min(by: { abs($0.1 - size) < abs($1.1 - size) }) else { return "?" }
        return "\(best.0) (" + sizes.map { "\($0.0) \(fmt($0.1))" }.joined(separator: ", ") + ")"
    }

    // MARK: - 1:1 crops

    /// A row's pixels, grey, from an element screenshot (the rows must be on screen).
    private struct Crop {
        let width: Int, height: Int
        let pixels: [UInt8]
    }

    /// Element screenshots of `specimen.<row>` for each row, as grey pixels, each also attached
    /// (`a11y-2af-md-<row>-<variant>`) for 1:1 inspection.
    @MainActor
    private static func crops(_ app: XCUIApplication, variant: A11yVariant, rows: [String]) -> [String: Crop] {
        var result: [String: Crop] = [:]
        for row in rows {
            let element = app.staticTexts["specimen.\(row)"]
            guard element.exists else { continue }
            let image = element.screenshot().image
            let attachment = XCTAttachment(image: image)
            attachment.name = "a11y-2af-\(row.replacingOccurrences(of: ".", with: "-"))-\(variant.token)"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "crop \(row) \(variant)") { $0.add(attachment) }
            guard let cg = image.cgImage else { continue }
            let w = cg.width, h = cg.height
            var pixels = [UInt8](repeating: 255, count: w * h)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            if drawn { result[row] = Crop(width: w, height: h, pixels: pixels) }
        }
        return result
    }

    /// How differently two crops lay down ink: Σ|a − b| ÷ (ink(a) + ink(b)) over their common
    /// top-left area — 0 for identical glyphs, near 1 when the ink doesn't overlap at all. Crops
    /// whose widths differ by more than 2 % drew different metrics, so they're maximally apart (1).
    private static func inkDistance(_ a: Crop?, _ b: Crop?) -> Double {
        guard let a, let b else { return 1 }
        guard abs(a.width - b.width) <= max(2, Int(Double(max(a.width, b.width)) * 0.02)) else { return 1 }
        let w = min(a.width, b.width), h = min(a.height, b.height)
        var difference = 0.0, ink = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let pa = Double(a.pixels[y * a.width + x]), pb = Double(b.pixels[y * b.width + x])
                difference += abs(pa - pb)
                ink += (255 - pa) + (255 - pb)
            }
        }
        return ink > 0 ? difference / ink : 0
    }

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
