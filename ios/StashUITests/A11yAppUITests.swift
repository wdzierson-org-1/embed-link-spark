import UIKit
import XCTest

/// Plan 16, Task 2c — the accessibility pass over the Add tab (the composer and the voice
/// recorder), Settings (with the delete-account sheet), the "How to stash" onboarding, sign-in, the
/// tab bar and the share sheet.
///
/// - The screenshot matrix: every screen at Large, xxxLarge, AX3 and Bold Text at Large, attached
///   as `a11y-<screen>-<size>` (`a11y-ios26-<screen>-<size>` on iOS 26) and exported to
///   `.superpowers/sdd/plan-16/` with `/tmp/p16/export-shots.sh`.
/// - Xcode's accessibility audit (hit regions, Dynamic Type, contrast, clipped text) on every
///   screen at every size, logged as `A11Y audit …` lines.
/// - The Add tab's Cancel contract: the shared `StashCancelButton` on a paper capsule, a 44 pt
///   target, one line at accessibility sizes, and appearing without moving the header.
///
/// The share sheet is its own process (launched by Safari), so launch arguments can't reach it:
/// `testShareComposeScreenshot` is host-orchestrated — see its doc comment.
final class A11yAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    // MARK: - Simulator state

    /// The two simulator-global knobs are back at their defaults — the text size Large, the real
    /// Bold Text setting off — as read by the type specimen launched WITHOUT any text-size or bold
    /// launch argument, i.e. by what the simulator itself is set to. Run before and after the
    /// share-sheet matrix (which changes both).
    @MainActor
    func testSimulatorTextSettingsAreTheDefaults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-type-specimen"]
        app.launch()
        let state = app.descendants(matching: .any)["specimen.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 15), "The type specimen did not appear")
        print("A11Y global state: \(state.label)")
        XCTAssertTrue(state.label.contains("csc=UICTContentSizeCategoryL;"), "Simulator text size isn't Large: \(state.label)")
        XCTAssertTrue(state.label.contains("boldText=false"), "The real Bold Text setting is on: \(state.label)")
    }

    // MARK: - Add tab

    /// The Add tab at rest and while composing (keyboard up, Cancel showing), then the voice
    /// recorder sheet — idle, and on its preview after a 2 s take (discarded with Close, so nothing
    /// is saved). Microphone access must be pre-granted on the simulator
    /// (`xcrun simctl privacy <udid> grant microphone it.gostash.stash`).
    @MainActor
    func testAddScreensAtEveryTextSize() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in A11yVariant.matrix {
            let app = screens.launch(variant, tab: .add)
            let editor = app.textViews["capture.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10), "\(variant): Add editor missing")
            sleep(2)   // the backdrop's blurred tier fades in
            shoot("add-rest", variant)
            audit(app, "add-rest", variant)
            for id in ["capture.photosPicker", "capture.cameraButton", "capture.fileButton", "capture.voice",
                       "capture.pin", "capture.save"] where Self.element(app, id).exists {
                assertTarget(Self.element(app, id), id, variant)
            }

            A11yScreens.tapUntilFocused(editor)
            editor.typeText("Remember the gallery opening")
            let cancel = app.buttons["capture.dismissKeyboard"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "\(variant): no Cancel while composing")
            sleep(1)
            shoot("add-composing", variant)
            audit(app, "add-composing", variant)
            if cancel.exists { cancel.tap() }
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "\(variant): Cancel should go with the keyboard")

            let voice = Self.element(app, "capture.voice")
            XCTAssertTrue(voice.waitForExistence(timeout: 5), "\(variant): mic button missing")
            voice.tap()
            let record = Self.element(app, "capture.voice.record")
            XCTAssertTrue(record.waitForExistence(timeout: 10), "\(variant): the voice recorder didn't open")
            sleep(1)
            shoot("voice", variant)
            audit(app, "voice", variant)
            assertTarget(record, "capture.voice.record", variant)
            record.tap()
            let stop = Self.element(app, "capture.voice.stop")
            if stop.waitForExistence(timeout: 5) {
                sleep(2)
                stop.tap()
                XCTAssertTrue(Self.element(app, "capture.voice.save").waitForExistence(timeout: 5),
                              "\(variant): no preview after Stop")
                sleep(1)
                shoot("voice-preview", variant)
                audit(app, "voice-preview", variant)
                for id in ["capture.voice.rerecord", "capture.voice.cancel", "capture.voice.save"] {
                    assertTarget(Self.element(app, id), id, variant)
                }
            } else {
                XCTFail("\(variant): recording didn't start (is the microphone granted?)")
            }
            // Close is in the navigation bar at every size; it discards the take.
            let close = app.buttons["capture.voice.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 3), "\(variant): the recorder's Close is missing")
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5), "\(variant): the recorder didn't close")

            // The composer's toast (plan 16: a paper pill with the state's glyph and ink text): a
            // refused pick's, which saves nothing — the DEBUG import hook hands the composer a
            // 30 MB movie (it attaches; nothing is saved) and a 101 MB one, over the limit. The
            // batch's refusal toasts once the loads are done; each load is held 4 s
            // (`--uitest-slow-attachment-load`) so the 3 s toast comes after the relaunch has
            // settled — unslowed, it toasts and goes while the launch is still being waited on.
            let toastApp = screens.launch(variant, tab: .add,
                                          arguments: ["--uitest-slow-attachment-load=4000",
                                                      "--uitest-import-file=clip.mov:30", "--uitest-import-file=lecture.mov:101"])
            let toast = Self.element(toastApp, "capture.toast")
            if toast.waitForExistence(timeout: 20) {
                usleep(700_000)   // past its slide-in, so the shot shows it at rest (it stays 3 s)
                shoot("add-toast", variant)
                print("A11Y toast \(variant) frame=\(toast.frame) label=\(toast.label) "
                      + "tabBarTop=\(toastApp.tabBars.firstMatch.frame.minY)")
                XCTAssertEqual(toast.label, "Couldn't add “lecture.mov” — it's over the 100 MB limit")
                XCTAssertLessThanOrEqual(toast.frame.maxY, toastApp.tabBars.firstMatch.frame.minY + 0.5,
                                         "\(variant): the toast sits under the tab bar")
                assertTarget(toast, "capture.toast", variant)   // before it goes (3 s)
                audit(toastApp, "add-toast", variant)
                // The attached file's ×: a 44 pt target inside its scroll view.
                assertTarget(Self.element(toastApp, "capture.attachment.remove"), "capture.attachment.remove", variant)
            } else {
                XCTFail("\(variant): no toast for the refused file")
            }
        }
    }

    /// Will's first example (plan 16): the Add tab's Cancel is the shared keyboard Cancel
    /// (`StashCancelButton(onWash: true)`): a 44 pt target (VoiceOver's frame is the target), the
    /// word on one line even at AX3, and it appears without moving the header — the wordmark stays
    /// put (≤ 0.5 pt ⇒ the header changed ≤ 1 pt) at Large and at AX3. It hides the keyboard and
    /// keeps the draft, and a tap inside its target but off the word (≈ 10 pt above it) also works.
    @MainActor
    func testAddTabCancelIsTheSharedCancelAndNeverMovesTheHeader() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in [A11yVariant.large, .ax3] {
            let app = screens.launch(variant, tab: .add)
            let editor = app.textViews["capture.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10), "\(variant): Add editor missing")
            let wordmark = app.images.matching(NSPredicate(format: "label == %@", "Stash")).firstMatch
            XCTAssertTrue(wordmark.waitForExistence(timeout: 5), "\(variant): header wordmark missing")
            sleep(1)
            let resting = wordmark.frame

            A11yScreens.tapUntilFocused(editor)
            editor.typeText("draft")
            let cancel = app.buttons["capture.dismissKeyboard"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "\(variant): no Cancel while composing")
            sleep(1)
            let composing = wordmark.frame
            print("A11Y add-cancel \(variant) cancel=\(cancel.frame) wordmark rest=\(resting) composing=\(composing)")
            XCTAssertEqual(cancel.label, "Cancel")
            XCTAssertGreaterThanOrEqual(cancel.frame.width, 43.5, "\(variant): Cancel's target is narrower than 44 pt")
            XCTAssertGreaterThanOrEqual(cancel.frame.height, 43.5, "\(variant): Cancel's target is shorter than 44 pt")
            XCTAssertLessThanOrEqual(abs(composing.midY - resting.midY), 0.5,
                                     "\(variant): the header moved \(composing.midY - resting.midY) pt when Cancel appeared")
            let em = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: variant.traits).rounded()
            XCTAssertLessThan(cancel.frame.height, max(44, 1.7 * em), "\(variant): Cancel wrapped (\(cancel.frame.height) pt tall)")
            XCTAssertGreaterThan(cancel.frame.width, 2.4 * em, "\(variant): Cancel is narrower than the word")

            // A tap ≈ 10 pt above the word — inside the 44 pt target, outside the text.
            let wordTop = cancel.frame.midY - em * 0.6
            A11yScreens.tap(app, at: CGPoint(x: cancel.frame.midX, y: max(cancel.frame.minY + 1.5, wordTop - 8)))
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "\(variant): a tap inside Cancel's target didn't dismiss")
            let unfocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == false"), object: editor)
            XCTAssertEqual(XCTWaiter().wait(for: [unfocused], timeout: 5), .completed, "\(variant): the editor kept the keyboard")
            XCTAssertEqual(editor.value as? String, "draft", "\(variant): Cancel must keep the draft")
        }
    }

    // MARK: - Settings

    /// Settings top to bottom (account, phone, subscription; then How to stash, Sign Out, Delete
    /// account and the footer), and the delete-account confirmation sheet (dismissed with Cancel —
    /// nothing is deleted).
    @MainActor
    func testSettingsScreensAtEveryTextSize() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in A11yVariant.matrix {
            let app = screens.launch(variant, tab: .settings)
            XCTAssertTrue(Self.element(app, "settings.account.email").waitForExistence(timeout: 15),
                          "\(variant): account email missing")
            _ = Self.element(app, "settings.subscription.status").waitForExistence(timeout: 15)
            sleep(1)
            shoot("settings", variant)
            audit(app, "settings", variant)
            for id in ["settings.feedurl.copy", "settings.phone.add"] where Self.element(app, id).exists {
                assertTarget(Self.element(app, id), id, variant)
            }

            let delete = app.buttons["settings.deleteAccount"]
            Self.bringIntoView(app, delete)
            shoot("settings-2", variant)
            audit(app, "settings-2", variant)
            for id in ["settings.howToStash", "settings.signout", "settings.deleteAccount"] where Self.element(app, id).exists {
                assertTarget(Self.element(app, id), id, variant)
            }

            // The footer (links + version) sits below Delete account.
            let version = Self.element(app, "settings.footer.version")
            Self.bringIntoView(app, version)
            shoot("settings-3", variant)
            audit(app, "settings-3", variant)
            for id in ["settings.footer.privacy", "settings.footer.terms"] {
                assertTarget(Self.element(app, id), id, variant)
            }

            Self.bringIntoView(app, delete, up: false)
            delete.tap()
            let field = app.textFields["settings.deleteAccount.field"]
            XCTAssertTrue(field.waitForExistence(timeout: 10), "\(variant): the delete sheet didn't open")
            sleep(1)
            shoot("settings-delete", variant)
            audit(app, "settings-delete", variant)
            for id in ["settings.deleteAccount.field", "settings.deleteAccount.cancel", "settings.deleteAccount.confirm"] {
                assertTarget(Self.element(app, id), id, variant)
            }
            let cancel = app.buttons["settings.deleteAccount.cancel"]
            if cancel.exists, cancel.isHittable {
                cancel.tap()
            } else {
                XCTFail("\(variant): the delete sheet's Cancel isn't reachable")
                app.swipeDown(velocity: .fast)
            }
            XCTAssertTrue(field.waitForNonExistence(timeout: 5), "\(variant): the delete sheet didn't close")
        }
    }

    // MARK: - Onboarding

    /// "How to stash" (Settings › How to stash): panels 1–3, each from the top; at the larger sizes
    /// also scrolled to its buttons.
    @MainActor
    func testOnboardingScreensAtEveryTextSize() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in A11yVariant.matrix {
            let app = screens.launch(variant, tab: .settings)
            let row = app.buttons["settings.howToStash"]
            Self.bringIntoView(app, row)
            row.tap()
            let primary = app.buttons["onboarding.gotIt"]
            XCTAssertTrue(primary.waitForExistence(timeout: 10), "\(variant): the onboarding panel didn't open")
            for panel in 1...3 {
                sleep(1)
                shoot("onboarding-\(panel)", variant)
                audit(app, "onboarding-\(panel)", variant)
                Self.bringIntoView(app, primary)
                if variant != .large, variant != .largeBold {
                    shoot("onboarding-\(panel)-end", variant)
                }
                XCTAssertEqual(primary.label, panel < 3 ? "Next" : "Got it", "\(variant): panel \(panel)'s button")
                if panel < 3 {
                    primary.tap()
                    for _ in 0..<3 { app.swipeDown() }   // back to the top for the next panel's shot
                }
            }
            // Skip is the card's last control: at the larger sizes the card ends below the screen,
            // so it is scrolled to the end — and allowed to come to rest there (`bringIntoView`): a
            // tap on a scroll view that is still settling only stops it.
            let skip = app.buttons["onboarding.skip"]
            Self.bringIntoView(app, skip)
            print("A11Y onboarding skip \(variant): frame=\(skip.frame) screen=\(app.frame)")
            assertTarget(primary, "onboarding.gotIt", variant)
            assertTarget(skip, "onboarding.skip", variant)
            skip.tap()
            // Skip dismisses the panel, back to the tab UI. (Not "the How to stash row exists": that
            // check failed on iOS 26.5 at AX3, where the panel does go away — see the log line.)
            let dismissed = skip.waitForNonExistence(timeout: 10)
            print("A11Y onboarding skip \(variant): dismissed=\(dismissed) howToStash row in the tree=\(row.exists)")
            if !dismissed { shoot("onboarding-after-skip", variant) }
            XCTAssertTrue(dismissed, "\(variant): Skip didn't dismiss the panel")
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "\(variant): Skip didn't return to Settings")
        }
    }

    /// The onboarding panels' pictures — panel 1's share glyph, panel 2's mock share sheet (its
    /// tile and row labels and glyphs), panel 3's screenshot — are art: VoiceOver gets each panel's
    /// step, title and caption, never "Reminders, Copy Photo, AirPlay…" or an image's asset name.
    @MainActor
    func testOnboardingArtIsNotInTheAccessibilityTree() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .settings)
        let row = app.buttons["settings.howToStash"]
        Self.bringIntoView(app, row)
        row.tap()
        let primary = app.buttons["onboarding.gotIt"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10), "The onboarding panel didn't open")
        let artTexts = ["Reminders", "More", "Copy Photo", "Add to Album", "AirPlay"]
        let artImages = ["Share", "checklist", "onboarding.stashTile", "More", "Copy", "rectangle.stack.badge.plus",
                         "Airplay Video", "onboarding.step3"]
        for panel in 1...3 {
            sleep(1)
            let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { artTexts.contains($0) }
            let images = app.images.allElementsBoundByIndex.map(\.label).filter { artImages.contains($0) }
            print("A11Y onboarding-art panel \(panel): texts=\(texts) images=\(images)")
            XCTAssertTrue(texts.isEmpty, "Panel \(panel): art text in the accessibility tree: \(texts)")
            XCTAssertTrue(images.isEmpty, "Panel \(panel): art image in the accessibility tree: \(images)")
            // What VoiceOver does get: the step (drawn in caps, read as words), the title (a
            // heading) and the caption.
            let step = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Step \(panel)")).firstMatch
            XCTAssertTrue(step.exists, "Panel \(panel): its \"Step \(panel)\" label should be readable")
            print("A11Y onboarding-art panel \(panel): step label=\"\(step.exists ? step.label : "-")\"")
            if panel < 3 { primary.tap() }
        }
    }

    // MARK: - Sign-in

    /// The signed-out screen: Sign in, and Sign up (username + phone fields and their helper
    /// lines). Signs out (`--uitest-reset-auth`); nothing is submitted.
    @MainActor
    func testSignInScreensAtEveryTextSize() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        for variant in A11yVariant.matrix {
            app.launchArguments = ["--uitest-reset-auth"] + variant.launchArguments
            app.launch()
            let email = app.textFields["signin.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 15), "\(variant): sign-in screen missing")
            sleep(2)
            shoot("signin", variant)
            audit(app, "signin", variant)
            assertTarget(email, "signin.email", variant)
            assertTarget(app.secureTextFields["signin.password"], "signin.password", variant)
            assertTarget(app.buttons["signin.submit"], "signin.submit", variant)
            assertTarget(Self.element(app, "auth.forgotPassword"), "auth.forgotPassword", variant)

            if variant == .large {
                // Each field takes taps across the whole 44 pt it draws, not only on its text line:
                // 18 pt above / below the line's centre is inside the field's padding (the line is
                // ~20 pt tall, the field 44).
                let password = app.secureTextFields["signin.password"]
                print("A11Y signin fields L: email=\(email.frame) password=\(password.frame)")
                A11yScreens.tap(app, at: CGPoint(x: password.frame.midX, y: password.frame.midY - 18))
                XCTAssertTrue(Self.waitForKeyboardFocus(password), "A tap in the password field's top padding should focus it")
                A11yScreens.tap(app, at: CGPoint(x: email.frame.midX, y: email.frame.midY + 18))
                XCTAssertTrue(Self.waitForKeyboardFocus(email), "A tap in the email field's bottom padding should focus it")
            }

            let signUp = app.buttons["auth.tab.signUp"]
            XCTAssertTrue(signUp.waitForExistence(timeout: 5), "\(variant): Sign up tab missing")
            signUp.tap()
            let username = app.textFields["auth.username"]
            XCTAssertTrue(username.waitForExistence(timeout: 5), "\(variant): username field missing")
            A11yScreens.tapUntilFocused(username)
            username.typeText("abc")   // the "You'll be @abc" helper line; nothing is submitted
            // Put the software keyboard away so the shot shows the whole form: the form dismisses
            // it interactively (`.scrollDismissesKeyboard(.interactively)`), so drag from the card
            // down past the keyboard's top edge (a plain swipe stopped short of it on iOS 26.5).
            // No keyboard at all on a simulator with a hardware keyboard connected (17.5's).
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
            sleep(1)
            shoot("signin-signup", variant)
            audit(app, "signin-signup", variant)
            assertTarget(username, "auth.username", variant)
            assertTarget(app.textFields["auth.phone"], "auth.phone", variant)
        }
    }

    // MARK: - Share sheet (host-orchestrated)

    /// The share sheet's compose card from Safari (Share › Stash) on example.com. The extension is
    /// Safari's child process, so neither launch argument reaches it — the text size is the
    /// SIMULATOR's (`xcrun simctl ui <udid> content_size …`, set by the host before the run and
    /// reset to `large` after) and Bold Text is the real setting (`enableBoldTextSetting`, which
    /// restores itself). Run it once per size, alone, with `TEST_RUNNER_A11Y_SHARE_TOKEN` =
    /// `L` | `xxxL` | `AX3` | `L-bold`; add `TEST_RUNNER_A11Y_SHARE_SIGN_IN=1` on the first run to
    /// sign in (the extension reads the app's stored session). The card is held for its shot,
    /// audited, checked that Save stays reachable, and cancelled — nothing is saved.
    @MainActor
    func testShareComposeScreenshot() throws {
        let environment = ProcessInfo.processInfo.environment
        let token = environment["A11Y_SHARE_TOKEN"] ?? ""
        try XCTSkipIf(token.isEmpty, "Host-orchestrated: run alone with TEST_RUNNER_A11Y_SHARE_TOKEN (see the doc comment)")
        let variant = try XCTUnwrap(A11yVariant.matrix.first { $0.token == token }, "unknown size token \(token)")
        if environment["A11Y_SHARE_SIGN_IN"] == "1" {
            try A11yScreens(self).signIn()
        }
        // Past here a failed check still lets the card be cancelled (nothing left open in Safari).
        continueAfterFailure = true
        if variant.bold { A11yScreens.enableBoldTextSetting(for: self) }
        // The runner follows the simulator's text size too: a host that forgot `simctl ui … content_size`
        // would silently shoot the wrong size.
        let category = UIScreen.main.traitCollection.preferredContentSizeCategory.rawValue
        print("A11Y share \(token): simulator content size \(category), bold text \(UIAccessibility.isBoldTextEnabled)")
        XCTAssertEqual(category, variant.category, "The simulator's text size isn't \(token)'s — set it with simctl first")

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        let save = Self.openStashComposeCard(in: safari, url: "example.com")
        sleep(2)
        shoot("share", variant)
        audit(safari, "share", variant)
        XCTAssertTrue(save.isHittable, "\(token): Save must stay reachable")
        for (element, name) in [(save, "share.save"), (safari.buttons["share.cancel"], "share.cancel")] {
            assertTarget(element, name, variant)
        }
        if safari.descendants(matching: .any)["share.pin"].exists {
            assertTarget(safari.descendants(matching: .any)["share.pin"], "share.pin", variant)
        }
        print("A11Y share \(token): save=\(save.frame) url=\(safari.staticTexts["share.preview.url"].frame)")

        // Writing a note: the keyboard comes up and Save (pinned above it) must still be reachable.
        // (The card's text view is a remote view: tapped within ~1 s of the card appearing it
        // never takes focus, so the wait above comes first; it's a TextView on iOS 17, a
        // TextField on iOS 26.)
        let noteView = safari.textViews["share.note"], noteField = safari.textFields["share.note"]
        let note = noteView.exists ? noteView : noteField
        if note.exists {
            // First a tap in the note card's padding, just above its text line: the whole card is
            // the note's target, not only its line (plan 16).
            let em = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: variant.traits)
            let before = note.frame
            A11yScreens.tap(safari, at: CGPoint(x: before.midX, y: before.midY - (em * 0.6 + 5)))
            let paddingTapFocused = Self.waitForKeyboardFocus(note)
            if !paddingTapFocused { A11yScreens.tapUntilFocused(note) }
            sleep(1)
            shoot("share-note", variant)
            XCTAssertTrue(save.isHittable, "\(token): Save must stay reachable above the keyboard")
            let focused = Self.hasKeyboardFocus(note)
            // No software keyboard at all while a hardware keyboard is connected (the iOS 17.5
            // simulator's): reading a missing element's frame would throw.
            let keyboard = safari.keyboards.firstMatch
            print("A11Y share \(token) note: frame before=\(before) after=\(note.frame) paddingTap=\(paddingTapFocused) "
                  + "focused=\(focused): save=\(save.frame) "
                  + "keyboard=\(keyboard.exists ? "\(keyboard.frame)" : "none (hardware keyboard)")")
            XCTAssertTrue(focused, "\(token): the note should take the keyboard")
            XCTAssertTrue(paddingTapFocused, "\(token): a tap in the note card's padding should focus the note")
        } else {
            XCTFail("\(token): the note field didn't render")
        }
        let cancel = safari.buttons["share.cancel"]
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), "\(token): the card didn't close")
    }

    // MARK: - Tab bar

    /// The tab bar's items are named for VoiceOver (Add, Ask, View, Settings). NOT part of the
    /// normal run: `TEST_RUNNER_A11Y_LCV_PROBE=1` also long-presses the Settings tab for 8 s at AX3
    /// while the host shoots the simulator every second — the system tab bar's own Large Content
    /// Viewer (XCUITest can't look at the screen during a press).
    @MainActor
    func testTabBarItemsAreNamedAndShowTheLargeContentViewer() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.ax3, tab: .add)
        let tabs = app.tabBars.firstMatch.buttons
        let labels = tabs.allElementsBoundByIndex.map(\.label)
        print("A11Y tabs labels=\(labels) identifiers=\(tabs.allElementsBoundByIndex.map(\.identifier))")
        XCTAssertEqual(labels, ["Add", "Ask", "View", "Settings"], "Tab bar items should be named for VoiceOver")
        shoot("tabbar", .ax3)
        guard ProcessInfo.processInfo.environment["A11Y_LCV_PROBE"] == "1" else { return }
        let settings = app.tabBars.buttons["Settings"]
        print("A11Y lcv press tab Settings at \(Date().timeIntervalSince1970)")
        settings.press(forDuration: 8)
        sleep(2)
    }

    // MARK: - Helpers

    /// "ios26-" on iOS 26 and later, so both OSes' shots can sit side by side.
    private static var osPrefix: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? "ios26-" : ""
    }

    /// A full-screen screenshot attached as `a11y-[ios26-]<screen>-<size>`, kept when the test passes.
    @MainActor
    private func shoot(_ screen: String, _ variant: A11yVariant) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "a11y-\(Self.osPrefix)\(screen)-\(variant.token)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Xcode's hit-region, Dynamic Type, contrast and clipped-text findings for what's on screen,
    /// logged as `A11Y audit <screen> <size> | …` (never fails the test; the report lists them).
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String, _ variant: A11yVariant) {
        do {
            try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast, .textClipped]) { issue in
                let element = issue.element
                let label = String((element?.label ?? "").prefix(60)).replacingOccurrences(of: "\n", with: " ")
                print("A11Y audit \(Self.osPrefix)\(screen) \(variant) | \(issue.compactDescription) | "
                      + "id=\(element?.identifier ?? "-") label=\"\(label)\" frame=\(element.map { "\($0.frame.integral)" } ?? "-")")
                return true
            }
        } catch {
            print("A11Y audit \(Self.osPrefix)\(screen) \(variant) | audit error: \(error)")
        }
    }

    @MainActor
    private static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// HIG / DESIGN.md › Controls (iOS): a tappable element takes touches across at least 44 × 44
    /// pt, and its accessibility frame is that target (`stashMinimumHitTarget`, `.stashPlain` and
    /// the shared controls make it so). Logged as `A11Y target …` (the report's controls audit).
    /// `≥ 43.5`: iOS 26.5 can read 43.99999999999994. (Not for `PillTabs`, whose accessibility
    /// frame is the visible pill while its 44 pt target overhangs — 2a proves that one by taps.)
    @MainActor
    private func assertTarget(_ element: XCUIElement, _ name: String, _ variant: A11yVariant,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(variant): \(name) is missing", file: file, line: line)
            return
        }
        let frame = element.frame
        print(String(format: "A11Y target %@%@ %@: %.1f x %.1f pt", Self.osPrefix, name, variant.token,
                     frame.width, frame.height))
        XCTAssertGreaterThanOrEqual(frame.width, 43.5, "\(variant): \(name)'s target is \(frame.width) pt wide",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 43.5, "\(variant): \(name)'s target is \(frame.height) pt tall",
                                    file: file, line: line)
    }

    @MainActor
    private static func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    @MainActor
    private static func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }

    /// Brings `element` well inside the screen and lets the scroll view come to rest before the
    /// caller taps: swipes (up by default, to reveal what's below) until it's in the tree — a List
    /// builds rows lazily — then drags it clear of the edges (100 pt from the top, 120 pt from the
    /// bottom, as `A11yScreens.scrollIntoView`), but stops as soon as a drag no longer moves it —
    /// the end of the content, where more drags only rubber-band — and waits for it to stop
    /// moving: a tap on a scroll view that is still settling only stops it (iOS 26.5's AX3 Skip
    /// tap was lost that way). `isHittable` alone isn't enough either: a button in the
    /// home-indicator zone reports hittable, but the system eats the tap.
    @MainActor
    private static func bringIntoView(_ app: XCUIApplication, _ element: XCUIElement, up: Bool = true, tries: Int = 8) {
        for _ in 0..<tries where !element.exists {
            if up { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
        }
        for _ in 0..<12 {
            guard element.exists else { return }
            let frame = element.frame, screen = app.frame
            let below = frame.maxY - (screen.maxY - 120), above = (screen.minY + 100) - frame.minY
            guard below > 0 || above > 0 else { break }
            // Positive drags the content up (reveals what's below); negative, down.
            let wanted = below > 0 ? frame.maxY - (screen.maxY - 200) : -((screen.minY + 200) - frame.minY)
            let distance = (wanted < 0 ? -1 : 1) * min(max(abs(wanted), 80), screen.height * 0.5)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.75 : 0.25))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            waitUntilAtRest(element)
            if abs(element.frame.minY - frame.minY) < 1 { break }   // the end of the content
        }
        waitUntilAtRest(element)
    }

    /// Waits (≤ `timeout`) until `element`'s frame stops changing between two reads 0.3 s apart.
    @MainActor
    private static func waitUntilAtRest(_ element: XCUIElement, timeout: TimeInterval = 4) {
        guard element.exists else { return }
        var last = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(300_000)
            guard element.exists else { return }
            let now = element.frame
            if abs(now.minY - last.minY) < 0.5, abs(now.minX - last.minX) < 0.5 { return }
            last = now
        }
    }

    /// Opens `url` in Safari and shares it to Stash; returns the compose card's Save button once the
    /// card is up. (The recipe `StashUITests.openStashComposeCard` proved: Share may live in
    /// Safari's ••• menu on newer toolbars, behind a one-time tip on iOS 26.)
    @MainActor
    private static func openStashComposeCard(in safari: XCUIApplication, url: String) -> XCUIElement {
        safari.launch()
        let addressBar = safari.textFields["TabBarItemTitle"]
        XCTAssertTrue(addressBar.waitForExistence(timeout: 10), "Safari address bar not found")
        addressBar.tap()
        let urlField = safari.textFields["URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), "Safari URL field not found")
        urlField.typeText("\(url)\n")
        let shareButton = safari.buttons["ShareButton"]
        if !shareButton.waitForExistence(timeout: 8) {
            let moreButton = safari.buttons["MoreMenuButton"]
            XCTAssertTrue(moreButton.waitForExistence(timeout: 10), "Neither Safari's Share button nor its More menu appeared")
            for _ in 0..<3 where !shareButton.exists {
                moreButton.tap()
                _ = shareButton.waitForExistence(timeout: 4)
            }
        }
        shareButton.tap()
        let stashCell = safari.cells["Stash"]
        // At the accessibility sizes the share sheet's app icons are larger, so Stash can sit past
        // the visible end of its row — not yet in the tree, or in it but off screen. Creep the row
        // along until Stash's centre is on screen: a swipe so slow it carries no fling moves the
        // row by about its own length, a cell or so, so it can't jump over Stash (a normal swipe
        // flings past it — iOS 26.5 at AX3 left it at x = -128, and `.slow` still overshot both
        // ways; a press-and-drag doesn't scroll the row at all).
        _ = stashCell.waitForExistence(timeout: 8)
        let screenWidth = safari.frame.width
        func stashOnScreen() -> Bool {
            stashCell.exists && stashCell.frame.midX > 20 && stashCell.frame.midX < screenWidth - 20
        }
        let rowApps = NSPredicate(format: "label IN %@", ["Messages", "Mail", "Notes", "Reminders", "Freeform", "Journal",
                                                          "AirDrop", "News", "Stash"])
        let rowY = safari.cells.matching(rowApps).allElementsBoundByIndex.first?.frame.midY
        let creep = XCUIGestureVelocity(rawValue: 100)
        for _ in 0..<14 where !stashOnScreen() {
            // Any app on screen in the row is a handle to swipe it by.
            guard let rowY, let handle = safari.cells.allElementsBoundByIndex.first(where: {
                abs($0.frame.midY - rowY) < 30 && $0.frame.midX > 40 && $0.frame.midX < screenWidth - 40
            }) else { break }
            if stashCell.exists && stashCell.frame.midX <= 20 {
                handle.swipeRight(velocity: creep)   // went past it: back
            } else {
                handle.swipeLeft(velocity: creep)
            }
            _ = stashCell.waitForExistence(timeout: 2)
            print("A11Y share row: stash \(stashCell.exists ? "\(stashCell.frame)" : "not in the tree")")
        }
        if !stashOnScreen() {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "debug-share-sheet-without-stash"
            attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "share sheet") { $0.add(attachment) }
        }
        XCTAssertTrue(stashOnScreen(),
                      "Stash did not come on screen in the share sheet (\(stashCell.exists ? "\(stashCell.frame)" : "not in the tree"))")
        stashCell.tap()
        XCTAssertTrue(safari.staticTexts["share.preview.url"].waitForExistence(timeout: 20), "The compose card didn't render")
        let save = safari.buttons["share.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "The compose card's Save button didn't render")
        return save
    }
}
