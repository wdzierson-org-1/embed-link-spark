import XCTest
@testable import StashKit

/// `ChatSpeech.speakableText` vs the web's `stripForSpeech` (src/components/ChatMole.tsx:56-62).
/// Every expected value in `testMatchesTheWebFunction` was produced by running the web function
/// itself under node — the port must stay byte-identical wherever the iOS pre-pass doesn't apply.
final class ChatSpeechTests: XCTestCase {
    func testMatchesTheWebFunction() {
        let cases: [(String, String)] = [
            ("**Bold** and _it_ `code` > quote # head", "Bold and it code quote head"),
            ("raw [3] marker and [Title](#3) link", "raw marker and Title link"),
            ("a\n\n- b\n- c", "a - b - c"),
            ("[x](https://a.com/(b))", "x)"),
            ("see [a] and [b](u) [12] end", "see [a] and b end"),
            ("nested [a [b] c](u) x", "nested [a [b] c](u) x"),
            ("[](empty) y", "y"),
            ("unclosed [link](abc", "unclosed [link](abc"),
            ("tab\tand\u{00A0}nbsp  and\r\nCRLF", "tab and nbsp and CRLF"),
            ("emoji 😀 [t](u) ok", "emoji 😀 t ok"),
            ("a\u{000B}b\u{FEFF}c\u{2028}d\u{3000}e", "a b c d e"),   // JS \s, not ICU \s
            ("  lead and trail \n", "lead and trail"),
            ("## Heading\n\n> quoted *em* text", "Heading quoted em text"),
            ("1. one\n2. two", "1. one 2. two"),
            ("cost is $5 [link $1](u)", "cost is $5 link $1"),     // `$` in text isn't a template
            ("٣ digits [٣] kept", "٣ digits [٣] kept"),           // JS \d is ASCII-only
        ]
        for (input, expected) in cases {
            XCTAssertEqual(ChatSpeech.speakableText(from: input), expected, "input: \(input.debugDescription)")
        }
    }

    /// The one deliberate divergence: a baked bare citation (`[[1]](#item=<uuid>)`) is dropped
    /// whole. The web leaves `[](item=<uuid>)` here, i.e. it reads the UUID aloud.
    func testBakedCitationsAreNeverSpokenAsUUIDs() {
        let answer = "Per [Feeding Log](#item=3f2a0000-0000-0000-0000-000000000001), persimmons should be "
            + "introduced gradually [[1]](#item=3f2a0000-0000-0000-0000-000000000001) to avoid stomach upset."
        XCTAssertEqual(ChatSpeech.speakableText(from: answer),
                       "Per Feeding Log, persimmons should be introduced gradually to avoid stomach upset.")
        XCTAssertEqual(ChatSpeech.speakableText(from: "[[1]](#item=x)"), "")
        // The legacy `stash://item/` bake reads the same way.
        XCTAssertEqual(ChatSpeech.speakableText(from: "[T](stash://item/abc) and [[2]](stash://item/abc)"), "T and")
    }

    func testRealAnswerShape() {
        let baked = ChatCitations.link(
            answer: "**Kyoto** tips: see [Temple Guide](#2) and book early [2].\n\n- Go at dawn\n- Skip weekends",
            sources: [ChatSource(id: UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!,
                                 title: "Temple Guide", type: "link", url: nil, n: 2)]).text
        let spoken = ChatSpeech.speakableText(from: baked)
        XCTAssertEqual(spoken, "Kyoto tips: see Temple Guide and book early . - Go at dawn - Skip weekends")
        XCTAssertFalse(spoken.contains("item"))
        XCTAssertFalse(spoken.lowercased().contains("6b1e0a4e"))
    }
}
