import XCTest
@testable import StashKit

/// Plan 16 (task 1c): the Ask thread's laid-out tail is sized by height — the viewport and the text
/// as `ChatBubble` sets it — not by characters, and a send's jump sheds rows only when the reader is
/// above the whole tail.
final class ChatThreadTailTests: XCTestCase {
    // MARK: - Fixtures

    /// iPhone 15 Pro at the default text size, keyboard down: bubble text 14 pt with 4.9 pt leading
    /// (a 22 pt line step), about 6.3 pt a character, 289 pt of text width, a 600 pt thread.
    private let standard = ChatThreadTail.Metrics(viewportHeight: 600, textWidth: 289, lineHeight: 22, characterWidth: 6.3)
    /// A Pro Max at xSmall: about 11 pt text, an 18 pt line step, 326 pt of text width, a 700 pt thread.
    private let extraSmall = ChatThreadTail.Metrics(viewportHeight: 700, textWidth: 326, lineHeight: 18, characterWidth: 5)
    /// The largest accessibility size: about 46 pt text, a 60 pt line step, 21 pt a character.
    private let accessibility5 = ChatThreadTail.Metrics(viewportHeight: 600, textWidth: 289, lineHeight: 60, characterWidth: 21)

    private func question(_ n: Int, _ text: String? = nil) -> ChatMessage {
        ChatMessage(id: "q\(n)", role: .user, content: text ?? "Question \(n)?")
    }

    private func answer(_ n: Int, _ text: String) -> ChatMessage {
        ChatMessage(id: "a\(n)", role: .assistant, content: text)
    }

    /// About 600 characters of prose in three paragraphs.
    private static let prose = [
        String(repeating: "Your saved notes come back to the same idea again and again. ", count: 3),
        String(repeating: "Most of the links agree on the basics, and one memo adds a caveat. ", count: 3),
        String(repeating: "The article you saved in spring covers the background in more depth. ", count: 3),
    ].joined(separator: "\n\n")

    /// `count` exchanges of a short question and a prose answer.
    private func proseThread(_ count: Int) -> [ChatMessage] {
        (1...count).flatMap { [question($0), answer($0, Self.prose)] }
    }

    /// The tail's estimated height from `start` to the end.
    private func tailHeight(_ messages: [ChatMessage], from start: Int, _ metrics: ChatThreadTail.Metrics) -> Double {
        messages[start...].reduce(0) { $0 + ChatThreadTail.estimatedHeight(of: $1.content, metrics: metrics) }
    }

    // MARK: - Where the tail starts

    func testAnEmptyThreadHasNoHistory() {
        XCTAssertEqual(ChatThreadTail.tailStart(in: [], metrics: standard), 0)
        XCTAssertEqual(ChatThreadTail.tailStart(in: [], metrics: nil), 0)
    }

    func testTheLastQuestionOnwardIsAlwaysInTheTail() {
        // The last answer alone is many screens tall: the tail is just the last exchange.
        let long = String(repeating: "A line of the answer\n", count: 200)
        let messages = [question(1), answer(1, "Short."), question(2), answer(2, long)]
        XCTAssertEqual(ChatThreadTail.tailStart(in: messages, metrics: standard), 2)
    }

    func testALongLastQuestionStillStartsTheTail() {
        let longQuestion = String(repeating: "Tell me everything about this. ", count: 400)
        let messages = [question(1), answer(1, "Short."), question(2, longQuestion), answer(2, "")]
        XCTAssertEqual(ChatThreadTail.tailStart(in: messages, metrics: standard), 2,
                       "The tail never starts after the last question, however tall it is")
    }

    func testShortExchangesAddUpToAScreenAndAHalf() {
        let messages = (1...40).flatMap { [question($0), answer($0, "A one-line answer.")] }
        let start = ChatThreadTail.tailStart(in: messages, metrics: standard)
        let target = ChatThreadTail.screensCovered * standard.viewportHeight
        XCTAssertGreaterThanOrEqual(tailHeight(messages, from: start, standard), target,
                                    "The tail covers a screen and a half")
        XCTAssertLessThan(tailHeight(messages, from: start + 1, standard), target,
                          "…and no more rows than it takes")
        XCTAssertGreaterThan(start, 0, "The rest stays in the lazy history")
    }

    func testWithoutAQuestionTheTailExtendsBackFromTheLastRow() {
        let messages = (1...40).map { answer($0, "A one-line answer.") }
        let start = ChatThreadTail.tailStart(in: messages, metrics: standard)
        XCTAssertGreaterThan(start, 0)
        XCTAssertLessThan(start, messages.count - 1)
        XCTAssertGreaterThanOrEqual(tailHeight(messages, from: start, standard),
                                    ChatThreadTail.screensCovered * standard.viewportHeight)
    }

    /// Review finding I3: a fixed 2,000 characters is a different height at every text size — little at
    /// xSmall, many screens at AX5 (all of it laid out). By height, each holds a screen and a half.
    func testTheTailIsSizedByHeightAtEveryTextSize() {
        let messages = proseThread(8)
        let small = ChatThreadTail.tailStart(in: messages, metrics: extraSmall)
        let regular = ChatThreadTail.tailStart(in: messages, metrics: standard)
        let huge = ChatThreadTail.tailStart(in: messages, metrics: accessibility5)
        XCTAssertLessThan(small, regular, "Smaller text keeps more rows laid out")
        XCTAssertLessThan(regular, huge, "Larger text keeps fewer")
        XCTAssertEqual(huge, messages.count - 2, "At AX5 one prose answer is already more than a screen and a half")
        XCTAssertGreaterThanOrEqual(tailHeight(messages, from: small, extraSmall), 1.5 * extraSmall.viewportHeight)
        let oldCharacterTail = messages[small...].reduce(0) { $0 + $1.content.count }
        XCTAssertGreaterThan(oldCharacterTail, ChatThreadTail.fallbackCharacters,
                             "At xSmall the tail holds more than the old 2,000-character budget")
    }

    func testATallerViewportKeepsMoreRows() {
        let messages = (1...40).flatMap { [question($0), answer($0, "A one-line answer.")] }
        var tall = standard
        tall.viewportHeight = 900
        XCTAssertLessThan(ChatThreadTail.tailStart(in: messages, metrics: tall),
                          ChatThreadTail.tailStart(in: messages, metrics: standard))
    }

    // MARK: - The height estimate

    func testEachSourceLineWrapsOnItsOwn() {
        // 289 / 6.3 → 45 characters a line.
        let list = (1...60).map { "- Point \($0): a short scripted line" }.joined(separator: "\n")
        let paragraph = String(repeating: "x", count: 450)
        let listLines = ChatThreadTail.estimatedHeight(of: list, metrics: standard) / standard.lineHeight
        let paragraphLines = ChatThreadTail.estimatedHeight(of: paragraph, metrics: standard) / standard.lineHeight
        XCTAssertEqual(listLines, 61, accuracy: 0.001, "60 list lines, plus one line for the bubble's own chrome")
        XCTAssertEqual(paragraphLines, 11, accuracy: 0.001, "450 characters wrap to 10 lines, plus the chrome line")
    }

    func testBlankLinesAddNoHeight() {
        let one = ChatThreadTail.estimatedHeight(of: "First paragraph.\n\n\n\nSecond paragraph.", metrics: standard)
        let two = ChatThreadTail.estimatedHeight(of: "First paragraph.\nSecond paragraph.", metrics: standard)
        XCTAssertEqual(one, two)
    }

    func testCitationLinkTargetsTakeNoWidth() {
        let linked = "Per [Feeding Log](#item=11111111-1111-1111-1111-111111111111), go slow."
        XCTAssertEqual(ChatThreadTail.visibleCharacterCount(linked), "Per [Feeding Log], go slow.".count)
        XCTAssertEqual(ChatThreadTail.visibleCharacterCount("A plain [bracket] and (parens)."),
                       "A plain [bracket] and (parens).".count)
    }

    // MARK: - Fallback and clamps

    /// Before the thread has been measured once: the old 2,000-character tail.
    func testWithoutMetricsTheTailHoldsTheFallbackCharacters() {
        let messages = (1...10).flatMap { [question($0), answer($0, String(repeating: "y", count: 499))] }
        let start = ChatThreadTail.tailStart(in: messages, metrics: nil)
        let characters = messages[start...].reduce(0) { $0 + $1.content.count }
        XCTAssertGreaterThanOrEqual(characters, ChatThreadTail.fallbackCharacters)
        XCTAssertLessThan(messages[(start + 1)...].reduce(0) { $0 + $1.content.count }, ChatThreadTail.fallbackCharacters)
    }

    func testBrokenMetricsCantLayOutTheWholeThread() {
        let messages = (1...200).flatMap { [question($0), answer($0, String(repeating: "z", count: 200))] }
        let broken = ChatThreadTail.Metrics(viewportHeight: 100_000, textWidth: 0, lineHeight: 0, characterWidth: 0)
        let start = ChatThreadTail.tailStart(in: messages, metrics: broken)
        let lastQuestion = messages.count - 2
        let extension_ = messages[start..<lastQuestion].reduce(0) { $0 + $1.content.count }
        XCTAssertLessThanOrEqual(extension_, ChatThreadTail.maximumExtensionCharacters + 200,
                                 "Past the last exchange the tail never takes more than the character cap")
        XCTAssertGreaterThan(start, 0)
    }

    // MARK: - A send's jump to the end (review finding I1)

    /// Following, the app holds the end (`AskThreadScrollObserver`), so the new rows are in view in
    /// the layout pass that adds them: nothing is left to ease.
    func testASendAtTheEndCutsAndKeepsTheTail() {
        let jump = ChatThreadTail.sendJump(isFollowing: true, distanceFromEnd: 0, visibleHeight: 598, tailHeight: 1_600)
        XCTAssertEqual(jump, ChatThreadTail.SendJump(shedsTail: false, animated: false))
    }

    func testASendFromInsideTheTailKeepsItsRows() {
        // Up a little inside the last answer: the rows above the reader stay laid out, and a hop
        // within a screen eases.
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, distanceFromEnd: 300, visibleHeight: 345, tailHeight: 1_600),
                       ChatThreadTail.SendJump(shedsTail: false, animated: true))
        // More than a screen up, still inside the tail: no shed, but a cut.
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, distanceFromEnd: 1_200, visibleHeight: 345, tailHeight: 1_600),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false))
    }

    func testASendFromAboveTheWholeTailShedsItAndCuts() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, distanceFromEnd: 1_601, visibleHeight: 345, tailHeight: 1_600),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false))
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, distanceFromEnd: 9_000, visibleHeight: 598, tailHeight: 1_600),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false))
    }

    func testAFollowingReaderNeverSheds() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, distanceFromEnd: 60, visibleHeight: 598, tailHeight: 40),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false))
    }

    func testWithoutGeometryASendGoesAsFromTheEnd() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, distanceFromEnd: nil, visibleHeight: nil, tailHeight: 0),
                       ChatThreadTail.SendJump.fromTheEnd)
        XCTAssertEqual(ChatThreadTail.SendJump.fromTheEnd, ChatThreadTail.SendJump(shedsTail: false, animated: false))
    }
}
