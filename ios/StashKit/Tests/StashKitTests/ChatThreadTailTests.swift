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
        XCTAssertEqual(messages[start].role, .user, "The tail starts at a question (task 1d)")
        XCTAssertLessThan(tailHeight(messages, from: start + 2, standard), target,
                          "…and no more exchanges than it takes")
        XCTAssertGreaterThan(start, 0, "The rest stays in the lazy history")
    }

    /// Task 1d: rows move into the lazy history a whole exchange at a time, so the tail never starts at an
    /// answer whose question is just before it. A lazy stack sizes a row it hasn't built at the average of the
    /// ones it has, and a question left alone at the history's end was all it had measured there: on iOS 17.5
    /// and 18.5 the 1,739 pt answer that moved in after it was sized at about 110 pt, and built at its full
    /// height above a reader scrolling back up to it, carrying its actions away from the drag (task 1d, the
    /// thumb test). Here a send at the end of a thread whose last answer alone covers the budget: the tail
    /// keeps that answer, and its question.
    func testTheTailNeverStartsBetweenAQuestionAndItsAnswer() {
        let long = String(repeating: "A line of the answer\n", count: 120)
        let sent = [question(1), answer(1, long), question(2), answer(2, "")]
        XCTAssertEqual(ChatThreadTail.tailStart(in: sent, metrics: standard), 0,
                       "Answer 1 covers the budget, so the tail reaches it, and its question with it")
        XCTAssertEqual(ChatThreadTail.tailStart(in: sent, metrics: nil), 0,
                       "The same by characters, before the thread is measured")
    }

    func testWithoutAQuestionTheTailExtendsBackFromTheLastRow() {
        let messages = (1...40).map { answer($0, "A one-line answer.") }
        let start = ChatThreadTail.tailStart(in: messages, metrics: standard)
        XCTAssertGreaterThan(start, 0)
        XCTAssertLessThan(start, messages.count - 1)
        XCTAssertGreaterThanOrEqual(tailHeight(messages, from: start, standard),
                                    ChatThreadTail.screensCovered * standard.viewportHeight)
        XCTAssertLessThan(tailHeight(messages, from: start + 1, standard),
                          ChatThreadTail.screensCovered * standard.viewportHeight,
                          "…and no more rows than it takes: an answer after an answer has no question to come with")
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
        XCTAssertEqual(messages[start].role, .user, "The tail starts at a question (task 1d)")
        XCTAssertLessThan(messages[(start + 2)...].reduce(0) { $0 + $1.content.count }, ChatThreadTail.fallbackCharacters,
                          "…and holds no more exchanges than it takes")
    }

    func testBrokenMetricsCantLayOutTheWholeThread() {
        let messages = (1...200).flatMap { [question($0), answer($0, String(repeating: "z", count: 200))] }
        let broken = ChatThreadTail.Metrics(viewportHeight: 100_000, textWidth: 0, lineHeight: 0, characterWidth: 0)
        let start = ChatThreadTail.tailStart(in: messages, metrics: broken)
        let lastQuestion = messages.count - 2
        let extension_ = messages[start..<lastQuestion].reduce(0) { $0 + $1.content.count }
        XCTAssertLessThanOrEqual(extension_, ChatThreadTail.maximumExtensionCharacters + 200 + "Question 200?".count,
                                 "Past the last exchange the tail takes no more than the cap, one answer and its question")
        XCTAssertGreaterThan(start, 0)
    }

    /// Task 1c review, nit N-a: the cap stops the tail taking rows before the last exchange once they hold
    /// `maximumExtensionCharacters`, but the row that crosses it comes whole, with its question (task 1d) —
    /// one row can take the extension past the cap — and no other row comes after it. Metrics at the clamps' far ends (1,000
    /// characters an 8 pt line, a 2,000 pt viewport: a 3,000 pt budget) keep the budget out of reach.
    func testOneRowCanTakeTheExtensionPastTheCapButNoRowFollowsIt() {
        let huge = String(repeating: "w", count: 9_000)
        let messages = [question(1), answer(1, "Short."), question(2), answer(2, huge), question(3), answer(3, "Short.")]
        let tiny = ChatThreadTail.Metrics(viewportHeight: 2_000, textWidth: 2_000, lineHeight: 8, characterWidth: 2)
        // q3 + a3 are 32 pt, a2 is 80 pt (9 lines + chrome): 112 pt of a 3,000 pt budget, but 9,000
        // characters, past the 6,000 cap — so a1 and q1 stay in the history, and a2 comes with its question.
        XCTAssertEqual(ChatThreadTail.tailStart(in: messages, metrics: tiny), 2)
    }

    /// The last row can be a question (a thread whose last exchange has no answer row yet): the tail
    /// starts there at the latest, and still covers a screen and a half.
    func testAQuestionAsTheLastRowStartsTheTail() {
        let exchanges = (1...40).flatMap { [question($0), answer($0, "A one-line answer.")] }
        // A tall question (12,400 characters, 277 lines) is the whole tail: row 80, with nothing after it.
        let longQuestion = String(repeating: "Tell me everything about this. ", count: 400)
        XCTAssertEqual(ChatThreadTail.tailStart(in: exchanges + [question(41, longQuestion)], metrics: standard), 80)
        // A short one: every row is 44 pt (one line and the chrome line at 22 pt), so 21 rows reach the
        // 900 pt budget and 20 don't — rows 60 to 80.
        XCTAssertEqual(ChatThreadTail.tailStart(in: exchanges + [question(41)], metrics: standard), 60)
    }

    // MARK: - A send's jump to the end (review findings I1, M-1, M-2)

    /// Task 1d (review finding M-1): a send made at the end sheds the tail back to its budget, as an
    /// answer completing there does. A reader who drags away while each answer streams never has one
    /// complete with them at the end, so no completion shed came, and the tail kept every exchange since
    /// the last one. From the end every row the tail sheds is above the viewport, and the app holds the
    /// end through the layout pass; the new rows are in view in that same pass, so nothing is left to ease.
    func testASendAtTheEndShedsTheTailAndCuts() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false, distanceFromEnd: 0,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false, shedsOnLanding: false))
    }

    /// The end's reach is the end hold's (`endSlack`), and strict: a send just inside it sheds; one at it
    /// doesn't, and (the reader following) cuts.
    func testTheEndsReachIsStrict() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false,
                                               distanceFromEnd: ChatThreadTail.endSlack - 0.5, visibleHeight: 598,
                                               tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false, shedsOnLanding: false))
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false,
                                               distanceFromEnd: ChatThreadTail.endSlack, visibleHeight: 598,
                                               tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: true))
    }

    /// Not while something else scrolls the thread — a finger, the glide after one, a scroll UIKit
    /// animates that the thread didn't start: the end hold doesn't apply then, so a shed above the reader
    /// would move what they see.
    func testASendAtTheEndWhileTheThreadIsBeingScrolledKeepsTheTail() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: true, distanceFromEnd: 0,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: true))
    }

    /// Review finding M-2: until the app has seen its end hold work, nothing sheds at the end, and the
    /// tail grows as task 1b's did — which never moves what the reader sees.
    func testUntilTheHoldsAreSeenASendAtTheEndKeepsTheTail() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false, distanceFromEnd: 0,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: false),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: true))
    }

    func testASendFromInsideTheTailKeepsItsRows() {
        // Up a little inside the last answer: the rows above the reader stay laid out, and a hop
        // within a screen eases.
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 300,
                                               visibleHeight: 345, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: true, shedsOnLanding: true))
        // More than a screen up, still inside the tail: no shed, but a cut.
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 1_200,
                                               visibleHeight: 345, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: true))
    }

    /// The inside of each boundary (task 1c review, unit-test gaps): a viewport that ends exactly at the
    /// tail's first row isn't above the tail, so nothing sheds; a hop of exactly one screen still eases.
    func testTheTailsTopAndOneScreenAreInsideTheirBoundaries() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 1_600,
                                               visibleHeight: 345, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: true))
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 345,
                                               visibleHeight: 345, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: true, shedsOnLanding: true))
    }

    func testASendFromAboveTheWholeTailShedsItAndCuts() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 1_601,
                                               visibleHeight: 345, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false, shedsOnLanding: false))
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 9_000,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false, shedsOnLanding: false))
    }

    /// A send from above the whole tail sheds whether or not the holds work: the rows it sheds are below
    /// the reader, off screen, and the jump lands on the new rows (task 1b's shed, which needs no hold).
    func testASendFromAboveTheTailShedsWithoutTheHolds() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 9_000,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: false),
                       ChatThreadTail.SendJump(shedsTail: true, animated: false, shedsOnLanding: false))
    }

    /// A follower away from the end — for a beat after a scroll that isn't a drag, while the pins are
    /// held off — is never taken for a reader above the tail, however short the tail: no shed, a cut.
    func testAFollowerAwayFromTheEndNeverSheds() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false, distanceFromEnd: 200,
                                               visibleHeight: 598, tailHeight: 40, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: true))
    }

    func testWithoutGeometryASendCutsAndShedsNothing() {
        XCTAssertEqual(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false, distanceFromEnd: nil,
                                               visibleHeight: nil, tailHeight: 0, holdsSeen: true),
                       ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: false))
        // The app's value before any send is classified, and after one is used: it never sheds.
        XCTAssertEqual(ChatThreadTail.SendJump.cut, ChatThreadTail.SendJump(shedsTail: false, animated: false, shedsOnLanding: false))
    }

    // MARK: - A send from inside the tail sheds once its jump has landed (task 1d, coordinator ruling on Q1)

    /// From inside the tail nothing sheds before the jump, following or not; once the jump has landed at the
    /// end, where the app holds the end (`canShedAtTheEnd`), the tail sheds to its budget. A reader who drags
    /// away while each answer streams and sends from where they read kept every exchange laid out until then.
    func testASendFromInsideTheTailShedsOnceItsJumpHasLanded() {
        for following in [false, true] {
            let jump = ChatThreadTail.sendJump(isFollowing: following, isBeingScrolled: false, distanceFromEnd: 300,
                                               visibleHeight: 345, tailHeight: 1_600, holdsSeen: true)
            XCTAssertFalse(jump.shedsTail, "Following \(following): nothing sheds before the jump")
            XCTAssertTrue(jump.shedsOnLanding, "Following \(following): the tail sheds once the jump has landed")
        }
    }

    /// A send that shed before its jump — from above the whole tail, or at the end — has nothing left to shed
    /// when it lands.
    func testASendThatShedsBeforeItsJumpDoesntShedAgainOnLanding() {
        XCTAssertFalse(ChatThreadTail.sendJump(isFollowing: false, isBeingScrolled: false, distanceFromEnd: 9_000,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: true).shedsOnLanding)
        XCTAssertFalse(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false, distanceFromEnd: 0,
                                               visibleHeight: 598, tailHeight: 1_600, holdsSeen: true).shedsOnLanding)
    }

    /// A send at the end that the hold didn't cover then — something else scrolling the thread, the holds not
    /// seen yet — sheds on landing instead, should `canShedAtTheEnd` hold by then.
    func testASendAtTheEndTheHoldDidntCoverShedsOnLanding() {
        XCTAssertTrue(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: true, distanceFromEnd: 0,
                                              visibleHeight: 598, tailHeight: 1_600, holdsSeen: true).shedsOnLanding)
        XCTAssertTrue(ChatThreadTail.sendJump(isFollowing: true, isBeingScrolled: false, distanceFromEnd: 0,
                                              visibleHeight: 598, tailHeight: 1_600, holdsSeen: false).shedsOnLanding)
    }

    // MARK: - The last exchange alone covers the budget (task 1d, the I-1 ruling)

    /// While an answer streams, every row before its question can shed once that exchange alone covers the
    /// tail's budget — the completion shed's geometry, early. Standard metrics: 22 pt lines, 45 characters a line,
    /// a 900 pt budget. A question (2 lines) and an answer of n one-line source lines (n + 1 lines): the exchange is
    /// 22 × (n + 3) pt, so 38 lines (902 pt) cover it and 37 (880 pt) don't.
    func testTheLastExchangeCoversTheBudgetOnceItIsAScreenAndAHalfTall() {
        func exchange(_ lines: Int) -> [ChatMessage] {
            let earlier = [question(1), answer(1, "An earlier answer.")]
            return earlier + [question(2), answer(2, (1...lines).map { "Line \($0)" }.joined(separator: "\n"))]
        }
        XCTAssertFalse(ChatThreadTail.lastExchangeCoversTheBudget(in: exchange(37), metrics: standard), "880 pt: not yet")
        XCTAssertTrue(ChatThreadTail.lastExchangeCoversTheBudget(in: exchange(38), metrics: standard), "902 pt: it covers")
    }

    /// The budget is reached at exactly a screen and a half (the tail's own rule stops there too). 20 pt lines and a
    /// 600 pt viewport: a 900 pt budget; a question (2 lines) and 42 one-line source lines (43 lines) is 900 pt.
    func testTheLastExchangeCoversTheBudgetAtExactlyAScreenAndAHalf() {
        var metrics = standard
        metrics.lineHeight = 20
        let messages = [question(1), answer(1, (1...42).map { "Line \($0)" }.joined(separator: "\n"))]
        XCTAssertTrue(ChatThreadTail.lastExchangeCoversTheBudget(in: messages, metrics: metrics))
    }

    /// No question, nothing to measure from.
    func testWithoutAQuestionNoExchangeCoversTheBudget() {
        let long = String(repeating: "A line of the answer\n", count: 200)
        XCTAssertFalse(ChatThreadTail.lastExchangeCoversTheBudget(in: [answer(1, long)], metrics: standard))
    }

    /// A shed made on this rule lands where the tail's own rule starts (`tailStart`): the last exchange covers the
    /// budget exactly when the tail is that exchange alone, so the shed moves every row before the last question, a
    /// whole exchange at a time, and no other. Three earlier prose exchanges, then a streaming answer of 0 to 60 lines.
    func testTheLastExchangeCoversTheBudgetExactlyWhenTheTailIsThatExchangeAlone() {
        for lines in 0...60 {
            let streaming = (0..<lines).map { "Line \($0)" }.joined(separator: "\n")
            let messages = proseThread(3) + [question(4), answer(4, streaming)]
            XCTAssertEqual(ChatThreadTail.lastExchangeCoversTheBudget(in: messages, metrics: standard),
                           ChatThreadTail.tailStart(in: messages, metrics: standard) == messages.count - 2,
                           "A streaming answer of \(lines) lines")
        }
    }

    // MARK: - Sheds at the end (review findings M-1, M-2)

    /// Both of the tail's sheds above the reader — an answer completing at the end, a send made there —
    /// go only while the app's end hold covers the layout pass they land in: a follower within the end's
    /// reach, nothing else scrolling the thread, and the hold seen working (M-2: if the size-change
    /// notifications it relies on stop coming, nothing sheds, and the tail grows instead of flashing).
    func testAShedAtTheEndNeedsAFollowerThereNothingElseScrollingAndSeenHolds() {
        func canShed(following: Bool = true, scrolled: Bool = false, distance: Double? = 0, seen: Bool = true) -> Bool {
            ChatThreadTail.canShedAtTheEnd(isFollowing: following, isBeingScrolled: scrolled,
                                           distanceFromEnd: distance, holdsSeen: seen)
        }
        XCTAssertTrue(canShed(), "A follower at rest at the end, with the holds seen working")
        XCTAssertFalse(canShed(seen: false), "Not before the end hold has been seen working (M-2)")
        XCTAssertFalse(canShed(following: false), "Not for a reader who doesn't follow")
        XCTAssertFalse(canShed(scrolled: true), "Not while something else scrolls the thread")
        XCTAssertFalse(canShed(distance: ChatThreadTail.endSlack), "Not beyond the end's reach")
        XCTAssertFalse(canShed(distance: nil), "Not without the thread's geometry")
    }
}
