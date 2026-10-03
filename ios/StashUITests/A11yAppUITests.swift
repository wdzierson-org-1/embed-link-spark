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
/// - Fix round 1 (the 2c review): targets proven by taps where a frame can't show them (the
///   attachment ×'s top edge, Next's bottom edge, a tap through a refusal toast), the onboarding
///   card's height, the Outbox badge's place, and a phone number that wraps instead of truncating.
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
            let toastApp = screens.launch(variant, tab: .add, arguments: Self.refusedImportArguments)
            let toast = Self.element(toastApp, "capture.toast")
            var toastLiesOverTheMic = false
            if toast.waitForExistence(timeout: 20) {
                usleep(700_000)   // past its slide-in, so the shot shows it at rest (it stays 3 s)
                shoot("add-toast", variant)
                let toastFrame = toast.frame, tabBarTop = toastApp.tabBars.firstMatch.frame.minY
                print("A11Y toast \(variant) frame=\(toastFrame) label=\(toast.label) tabBarTop=\(tabBarTop)")
                XCTAssertEqual(toast.label, "Couldn't add “lecture.mov” — it's over the 100 MB limit")
                XCTAssertLessThanOrEqual(toastFrame.maxY, tabBarTop + 0.5, "\(variant): the toast sits under the tab bar")
                assertTarget(toast, "capture.toast", variant)   // before it goes (3 s)
                audit(toastApp, "add-toast", variant)
                // The bottom bar's circles the toast lies over: at AX3, the lower part of all of them.
                let covered = Self.bottomBarControls.filter { id in
                    let control = Self.element(toastApp, id)
                    return control.exists && Self.overlaps(toastFrame, control.frame)
                }
                print("A11Y toast \(variant) lies over: \(covered)")
                toastLiesOverTheMic = covered.contains("capture.voice")
                // The attached file's ×: a 44 pt target inside its scroll view — measured, then
                // (once the toast has gone) tapped at its top edge.
                assertTarget(Self.element(toastApp, "capture.attachment.remove"), "capture.attachment.remove", variant)
                _ = toast.waitForNonExistence(timeout: 6)
                assertAttachmentRemoveTargetTakesATapAtItsTopEdge(toastApp, variant)
            } else {
                XCTFail("\(variant): no toast for the refused file")
            }
            if toastLiesOverTheMic {
                assertARefusalToastLetsTapsThroughToTheMic(screens, variant)
            }
        }
    }

    /// The Outbox badge (fix round 1, M-4): at rest it sits at the header's trailing edge — the
    /// hidden "Cancel" line beside it holds the header's height, not its width — and while composing
    /// it sits 12 pt before Cancel at its own width (at AX3 it used to be squeezed 3.3 pt there), the
    /// wordmark unmoved. The DEBUG `--uitest-outbox-badge=2` shows
    /// the badge as if 2 captures were waiting to sync (nothing is queued). Shot as `add-badge` /
    /// `add-badge-composing`: the badge's look — orange with ink digits — is read off those.
    @MainActor
    func testOutboxBadgeRestsAtTheHeaderEdge() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in [A11yVariant.large, .ax3] {
            let app = screens.launch(variant, tab: .add, arguments: ["--uitest-outbox-badge=2"])
            let editor = app.textViews["capture.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10), "\(variant): Add editor missing")
            let badge = Self.element(app, "capture.outboxBadge")
            XCTAssertTrue(badge.waitForExistence(timeout: 5), "\(variant): the Outbox badge didn't show")
            let wordmark = app.images.matching(NSPredicate(format: "label == %@", "Stash")).firstMatch
            XCTAssertTrue(wordmark.waitForExistence(timeout: 5), "\(variant): header wordmark missing")
            sleep(2)   // the backdrop's blurred tier fades in
            shoot("add-badge", variant)
            let restingBadge = badge.frame, restingMark = wordmark.frame
            // The header's trailing edge: `StashHeader`'s 16 pt inset plus the Add tab's own 2 pt.
            let headerTrailing = app.frame.maxX - 18
            print("A11Y badge \(variant) rest: badge=\(restingBadge) wordmark=\(restingMark) headerTrailing=\(headerTrailing)")
            XCTAssertEqual(badge.label, "2 captures waiting to sync")
            XCTAssertEqual(restingBadge.maxX, headerTrailing, accuracy: 1,
                           "\(variant): at rest the badge should sit at the header's trailing edge")
            XCTAssertEqual(restingBadge.midY, restingMark.midY, accuracy: 1, "\(variant): the badge should centre on the header row")

            A11yScreens.tapUntilFocused(editor)
            editor.typeText("draft")
            let cancel = app.buttons["capture.dismissKeyboard"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "\(variant): no Cancel while composing")
            sleep(1)
            shoot("add-badge-composing", variant)
            let composingBadge = badge.frame, composingMark = wordmark.frame, cancelFrame = cancel.frame
            print("A11Y badge \(variant) composing: badge=\(composingBadge) cancel=\(cancelFrame) wordmark=\(composingMark)")
            XCTAssertLessThanOrEqual(composingBadge.maxX, cancelFrame.minX - 11.5,
                                     "\(variant): while composing the badge should sit 12 pt before Cancel")
            XCTAssertEqual(composingBadge.width, restingBadge.width, accuracy: 0.5,
                           "\(variant): the badge is squeezed beside Cancel (\(composingBadge.width) pt wide, \(restingBadge.width) at rest)")
            XCTAssertEqual(composingMark.midY, restingMark.midY, accuracy: 0.5,
                           "\(variant): the header moved when Cancel appeared beside the badge")
            if cancel.exists { cancel.tap() }
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "\(variant): Cancel should go with the keyboard")
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

    /// A registered phone number is never cut off (fix round 1, M-3): on one line beside its
    /// "Verified" note and remove button while they fit, and at the larger sizes on its own line
    /// under them, where it wraps rather than truncating ("+1 (555) 123-45…" at AX3 before). The
    /// DEBUG `--uitest-phone-fixture` shows one made-up, verified number in place of the account's
    /// (none is registered on the shared test account, and nothing is written). Shot as
    /// `settings-phone`.
    @MainActor
    func testPhoneNumberIsNeverTruncated() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        let shown = "+1 (555) 123-4567"
        for variant in [A11yVariant.large, .ax3, .ax5] {
            let app = screens.launch(variant, tab: .settings, arguments: ["--uitest-phone-fixture"])
            let number = app.staticTexts.matching(NSPredicate(format: "label == %@", shown)).firstMatch
            // At the largest sizes the row starts below the fold, where the List hasn't built it yet.
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 15)
            Self.bringIntoView(app, number)
            XCTAssertTrue(number.waitForExistence(timeout: 5), "\(variant): the fixture number's row didn't show")
            sleep(1)
            shoot("settings-phone", variant)
            // The number's own width on one line, in the font the row sets (`.mono(.subheadline)`,
            // SF Mono at this size), against the frame it was given.
            let size = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: variant.traits).pointSize
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let oneLine = (shown as NSString).size(withAttributes: [.font: font]).width
            let frame = number.frame
            print(String(format: "A11Y phone %@: frame=(%.1f, %.1f, %.1f, %.1f) one-line width=%.1f line height=%.1f",
                         variant.token, frame.minX, frame.minY, frame.width, frame.height, oneLine, font.lineHeight))
            if oneLine > frame.width + 1 {
                // Narrower than the number: it must have wrapped onto a second line.
                XCTAssertGreaterThanOrEqual(frame.height, 1.6 * font.lineHeight,
                                            "\(variant): the number needs \(oneLine) pt on one line but got \(frame.width) pt "
                                            + "and one line (\(frame.height) pt tall) — it's truncated")
            }
            // By its name: the row's own identifier, set on the whole row, reaches the button too.
            let remove = app.buttons.matching(NSPredicate(format: "label == %@", "Remove \(shown)")).firstMatch
            assertTarget(remove, "settings.phone remove", variant)
        }
    }

    // MARK: - Onboarding

    /// "How to stash" (Settings › How to stash): panels 1–3, each from the top; at the larger sizes
    /// also scrolled to its buttons. Fix round 1: at the default size the card hugs its content
    /// (I-1, `assertCarouselHugsItsTallestPanel`), and a tap on Next's very bottom edge is Next's,
    /// at every size (M-2: Skip's 44 pt target, which reaches up into Next's fill at the default
    /// size, used to take it and dismiss the panel).
    @MainActor
    func testOnboardingScreensAtEveryTextSize() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        variants: for variant in A11yVariant.matrix {
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
                if panel == 2, variant == .large || variant == .largeBold {
                    assertCarouselHugsItsTallestPanel(app, primary, variant)
                }
                Self.bringIntoView(app, primary)
                if variant != .large, variant != .largeBold {
                    shoot("onboarding-\(panel)-end", variant)
                }
                XCTAssertEqual(primary.label, panel < 3 ? "Next" : "Got it", "\(variant): panel \(panel)'s button")
                if panel == 1 {
                    primary.tap()
                } else if panel == 2 {
                    // 1 pt inside Next's bottom edge: Next's fill, and — at the default size — inside
                    // Skip's overhanging target too. Next must take it and move on to panel 3.
                    let next = primary.frame
                    A11yScreens.tap(app, at: CGPoint(x: next.midX, y: next.maxY - 1))
                    let advanced = A11yScreens.waitForLabel(primary, "Got it", condition: "==", timeout: 4)
                    let skip = app.buttons["onboarding.skip"]
                    print("A11Y onboarding next-edge tap \(variant): next=\(next) "
                          + "skip=\(skip.exists ? "\(skip.frame)" : "gone") advanced=\(advanced)")
                    guard advanced else {
                        XCTFail("\(variant): a tap 1 pt inside Next's bottom edge didn't move to panel 3 (Skip took it?)")
                        continue variants
                    }
                }
                if panel < 3 {
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
            // What VoiceOver does get: the step — its label uppercased like the drawing ("STEP 1":
            // `.textCase` reaches the label too, and VoiceOver reads "step" as a word), so the match
            // ignores case — the title (a heading) and the caption.
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
    ///
    /// `ios/scripts/a11y-share-shots.sh <udid> <derived-data> <results-dir>` runs all four sizes
    /// that way, and an EXIT trap puts the simulator's text size back to `large` however the run
    /// ends: `trap 'xcrun simctl ui "$UDID" content_size large' EXIT` (a killed shell skips even
    /// that — `testSimulatorTextSettingsAreTheDefaults` then reports the leak).
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
    ///
    /// An issue Xcode can't tie to an element (`id=-`) is logged with its detailed description,
    /// and the screen once with what an unattributed contrast issue is usually about (fix round 1,
    /// N-4): the texts and buttons that lie under the tab bar — a translucent bar on iOS 17,
    /// floating glass on iOS 26, which a scrolled list's rows show through — and the disabled
    /// buttons, whose text is drawn faint on purpose.
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String, _ variant: A11yVariant) {
        var unattributed = 0
        do {
            try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast, .textClipped]) { issue in
                let element = issue.element
                let label = String((element?.label ?? "").prefix(60)).replacingOccurrences(of: "\n", with: " ")
                print("A11Y audit \(Self.osPrefix)\(screen) \(variant) | \(issue.compactDescription) | "
                      + "id=\(element?.identifier ?? "-") label=\"\(label)\" frame=\(element.map { "\($0.frame.integral)" } ?? "-")")
                if element == nil {
                    unattributed += 1
                    print("A11Y audit-detail \(Self.osPrefix)\(screen) \(variant) | "
                          + String(issue.detailedDescription.prefix(200)).replacingOccurrences(of: "\n", with: " "))
                }
                return true
            }
        } catch {
            print("A11Y audit \(Self.osPrefix)\(screen) \(variant) | audit error: \(error)")
        }
        guard unattributed > 0 else { return }
        // One snapshot of the tree (one round trip, not one per element).
        func flatten(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] { [node] + node.children.flatMap(flatten) }
        let nodes = (try? app.snapshot()).map(flatten) ?? []
        let barFrame = nodes.first { $0.elementType == .tabBar }?.frame ?? .null
        // Includes the bar's own items (Add, Ask, View, Settings), which read fine on it.
        let underBar = barFrame.isNull ? [] : nodes.filter {
            ($0.elementType == .staticText || $0.elementType == .button) && Self.overlaps($0.frame, barFrame)
        }
        let disabled = nodes.filter { $0.elementType == .button && !$0.isEnabled }
        func describe(_ found: [XCUIElementSnapshot]) -> String {
            found.map { "\"\(String($0.label.prefix(30)))\" \($0.frame.integral)" }.joined(separator: ", ")
        }
        print("A11Y audit-unattributed \(Self.osPrefix)\(screen) \(variant) | \(unattributed) issue(s) | "
              + "tab bar \(barFrame.isNull ? "-" : "\(barFrame.integral)") | under it: [\(describe(underBar))] | "
              + "disabled: [\(describe(disabled))]")
    }

    /// The composer's toast fixture: a 30 MB movie that attaches and a 101 MB one it refuses, each
    /// load held 4 s (see the toast step in `testAddScreensAtEveryTextSize`).
    private static let refusedImportArguments = ["--uitest-slow-attachment-load=4000", "--uitest-import-file=clip.mov:30",
                                                 "--uitest-import-file=lecture.mov:101"]

    /// The bottom bar's controls, by identifier (the camera's is absent on a simulator).
    private static let bottomBarControls = ["capture.photosPicker", "capture.cameraButton", "capture.fileButton",
                                            "capture.voice", "capture.pin", "capture.save"]

    /// Whether two frames share more than a sliver (≥ 1 pt each way) — touching edges don't count.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && shared.width >= 1 && shared.height >= 1
    }

    /// The attachment ×'s target reaches up past its glyph (fix round 1, M-5) — proven by a tap, not
    /// a frame: a horizontal scroll view takes taps only inside its own bounds, so the part of a
    /// 44 pt target that overhangs the row's top is lost to taps while the accessibility frame
    /// (`assertTarget`'s) keeps it. The row's 19 pt top padding keeps the target inside. The tap:
    /// 16 pt above the glyph's centre — 6 pt inside the target's top edge, well off the 18 pt glyph.
    ///
    /// Measured with a probe (2026-10-03, taps every few points above the glyph's centre): with the
    /// 19 pt padding the target takes taps up to 18 pt above the centre on iOS 17.5 (the scroll
    /// view's top ~5 pt take no taps there) and at least 20 on iOS 26.5; with the old 10 pt padding,
    /// up to about 9 (17.5) and 12 (26.5) — so this tap misses on the old layout on both. Not
    /// checked: the trailing edge. A tap 2 pt inside it worked even with the old 8 pt trailing
    /// padding, since a row narrower than its scroll view isn't cut there; that padding matters
    /// only once the row overflows and is scrolled to its end.
    @MainActor
    private func assertAttachmentRemoveTargetTakesATapAtItsTopEdge(_ app: XCUIApplication, _ variant: A11yVariant) {
        let remove = Self.element(app, "capture.attachment.remove")
        guard remove.waitForExistence(timeout: 10) else {
            XCTFail("\(variant): the attached movie's × is missing")
            return
        }
        let frame = remove.frame
        A11yScreens.tap(app, at: CGPoint(x: frame.midX, y: frame.midY - 16))
        let removed = remove.waitForNonExistence(timeout: 5)
        print("A11Y attachment-x top-edge tap \(variant): target=\(frame) removed=\(removed)")
        XCTAssertTrue(removed, "\(variant): a tap 16 pt above the ×'s centre (inside its target, off the glyph) should remove its chip")
    }

    /// A toast that doesn't navigate lets taps through to what it lies over (fix round 1, M-1). At
    /// AX3 the refusal toast covers the lower part of the bottom bar's circles for its 3 s: a tap
    /// on the mic where the toast lies over it must open the voice recorder — it used to land on
    /// the toast, which only closed. A launch of its own, so the tap comes well inside the 3 s;
    /// nothing is saved (the take is never started, and the recorder is closed).
    @MainActor
    private func assertARefusalToastLetsTapsThroughToTheMic(_ screens: A11yScreens, _ variant: A11yVariant) {
        let app = screens.launch(variant, tab: .add, arguments: Self.refusedImportArguments)
        let toast = Self.element(app, "capture.toast")
        guard toast.waitForExistence(timeout: 20) else {
            XCTFail("\(variant): no toast for the tap-through check")
            return
        }
        usleep(500_000)   // past its slide-in
        let mic = Self.element(app, "capture.voice")
        let toastFrame = toast.frame, micFrame = mic.frame
        guard Self.overlaps(toastFrame, micFrame) else {
            XCTFail("\(variant): this time the toast didn't lie over the mic (toast \(toastFrame), mic \(micFrame))")
            return
        }
        let spot = toastFrame.intersection(micFrame)
        let toastStillUp = toast.exists
        A11yScreens.tap(app, at: CGPoint(x: spot.midX, y: spot.midY))
        let record = Self.element(app, "capture.voice.record")
        let opened = record.waitForExistence(timeout: 5)
        print("A11Y toast tap-through \(variant): toast=\(toastFrame) mic=\(micFrame) tap=(\(spot.midX), \(spot.midY)) "
              + "toastUp=\(toastStillUp) recorderOpened=\(opened)")
        XCTAssertTrue(toastStillUp, "\(variant): the toast had gone before the tap — the check didn't run")
        XCTAssertTrue(opened, "\(variant): a tap on the mic where the refusal toast lies over it should reach the mic")
        if opened {
            let close = app.buttons["capture.voice.close"]
            if close.waitForExistence(timeout: 3) { close.tap() }
            XCTAssertTrue(record.waitForNonExistence(timeout: 5), "\(variant): the recorder didn't close")
        }
    }

    /// The onboarding carousel is exactly as tall as its tallest panel (fix round 1, I-1) — at the
    /// default text size panel 2, the one with a hint under its caption, which fills it — so the
    /// card keeps its natural height and sits centred, as with the old fixed 490 pt. Panel 2's hint
    /// then sits one card spacing (14 pt) above the 6 pt dots, and they 14 pt above Next: 34 pt
    /// from the hint to Next. (While the carousel absorbed the screen's spare height, the review
    /// measured 46.7 / 65.7 pt of blank from the hint to the dots on iOS 17.5 / 26.5, against 20.3
    /// before plan 16.)
    @MainActor
    private func assertCarouselHugsItsTallestPanel(_ app: XCUIApplication, _ primary: XCUIElement, _ variant: A11yVariant) {
        let hint = app.staticTexts.matching(NSPredicate(format: "label == %@",
                                                        "Don't see Stash? Tap More, then add Stash to your favorites.")).firstMatch
        guard hint.waitForExistence(timeout: 3) else {
            XCTFail("\(variant): panel 2's hint isn't on screen")
            return
        }
        let hintFrame = hint.frame, nextFrame = primary.frame
        let gap = nextFrame.minY - hintFrame.maxY
        print(String(format: "A11Y onboarding hint-to-next %@: %.1f pt (hint maxY %.1f, next minY %.1f)",
                     variant.token, gap, hintFrame.maxY, nextFrame.minY))
        XCTAssertLessThanOrEqual(gap, 40, "\(variant): \(gap) pt from panel 2's hint to Next (34 expected) — "
                                 + "the carousel is taller than its tallest panel")
        XCTAssertGreaterThanOrEqual(gap, 30, "\(variant): \(gap) pt from panel 2's hint to Next (34 expected) — panel 2 is cut short")
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
