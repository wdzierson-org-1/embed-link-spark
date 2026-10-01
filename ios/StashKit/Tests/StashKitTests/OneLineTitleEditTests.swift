import XCTest
@testable import StashKit

/// Plan 16, 2b review I-1: the detail sheet's title wraps (a vertical-axis field), so the keyboard's
/// "done" reaches it as a line break. What the field should hold next is decided by what the change
/// INSERTED — never by comparing whole strings, which read a Return over a selected word, or a Return
/// that also accepted an autocorrection, as a paste (the word became a space; the keyboard stayed).
final class OneLineTitleEditTests: XCTestCase {
    private func resolve(_ old: String?, _ new: String?) -> OneLineTitleEdit? {
        OneLineTitleEdit.resolve(old: old, new: new)
    }

    func testAChangeWithoutALineBreakNeedsNothing() {
        XCTAssertNil(resolve("Gro", "Groc"))
        XCTAssertNil(resolve("Groceries", "Gro"))
        XCTAssertNil(resolve(nil, nil))
    }

    func testDoneLeavesTheTitleAsItWasAndEndsEditing() {
        XCTAssertEqual(resolve("Gro", "Gro\n"), OneLineTitleEdit(title: "Gro", endsEditing: true), "at the end")
        XCTAssertEqual(resolve("Grocery list", "Grocery\n list"), OneLineTitleEdit(title: "Grocery list", endsEditing: true),
                       "in the middle")
    }

    /// The text view replaces a selection with the line break: the selected word must come back.
    func testDoneOverASelectionLeavesTheTitleAsItWas() {
        XCTAssertEqual(resolve("Grocery list", "Grocery \n"), OneLineTitleEdit(title: "Grocery list", endsEditing: true))
        XCTAssertEqual(resolve("Weekly grocery list", "Weekly \n list"),
                       OneLineTitleEdit(title: "Weekly grocery list", endsEditing: true))
        XCTAssertEqual(resolve("list list", "\n list"), OneLineTitleEdit(title: "list list", endsEditing: true),
                       "a selection whose text repeats after it")
        XCTAssertEqual(resolve("Groceries", "\n"), OneLineTitleEdit(title: "Groceries", endsEditing: true), "select-all")
        XCTAssertEqual(resolve(nil, "\n"), OneLineTitleEdit(title: nil, endsEditing: true), "an empty title stays nil")
        XCTAssertEqual(resolve("", "\n"), OneLineTitleEdit(title: "", endsEditing: true))
    }

    /// "Grocries", autocorrect offering "Groceries", then done: one change carries both the
    /// correction and the line break. The correction stays; editing ends.
    func testDoneThatAcceptsAnAutocorrectionKeepsItAndEndsEditing() {
        XCTAssertEqual(resolve("Grocries", "Groceries\n"), OneLineTitleEdit(title: "Groceries", endsEditing: true))
        XCTAssertEqual(resolve("teh", "the\n"), OneLineTitleEdit(title: "the", endsEditing: true))
    }

    func testAPasteEndingInALineBreakKeepsTheTextAndEndsEditing() {
        XCTAssertEqual(resolve("My ", "My list\n"), OneLineTitleEdit(title: "My list", endsEditing: true))
    }

    /// A paste with line breaks inside stays one line — each break a space — and editing goes on.
    func testAPasteWithALineBreakInsideBecomesOneLine() {
        XCTAssertEqual(resolve("Gro", "Groceries\nlist"), OneLineTitleEdit(title: "Groceries list", endsEditing: false))
        XCTAssertEqual(resolve("", "a\r\nb"), OneLineTitleEdit(title: "a b", endsEditing: false), "CRLF is one break")
        XCTAssertEqual(resolve("Gro", "Gro\n\n"), OneLineTitleEdit(title: "Gro  ", endsEditing: false), "two at once: a paste")
    }

    func testACRLFDoneIsOneLineBreak() {
        XCTAssertEqual(resolve("Gro", "Gro\r\n"), OneLineTitleEdit(title: "Gro", endsEditing: true))
    }

    /// A title that came from the server with a line break in it is made one line by the first
    /// edit, as before.
    func testATypedCharacterInATitleThatAlreadyHadALineBreakMakesItOneLine() {
        XCTAssertEqual(resolve("Line one\nLine two", "Line one\nLine two!"),
                       OneLineTitleEdit(title: "Line one Line two!", endsEditing: false))
        XCTAssertEqual(resolve("Line one\nLine two", "Line one\nLine two!\n"),
                       OneLineTitleEdit(title: "Line one Line two!", endsEditing: true),
                       "done after a correction never leaves the old break behind")
    }
}
