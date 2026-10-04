import Foundation

/// Plan 16 (tasks 1b, 1c and 1d): how the Ask thread splits into a lazily built history and a fully
/// laid-out tail, when the tail may shed rows it no longer needs, and how a send's jump to the thread's
/// end goes. Pure: the app (`AskThreadTail`) measures the thread and its text and passes them in.
///
/// Why a tail (task 1b): a `LazyVStack` sizes the rows it hasn't built at the average height of the
/// ones it has, so a jump aimed far down the thread with that estimate could land past the last real
/// row, and the thread stayed blank. Rows in the tail are always built, so a jump to the last row lands
/// exactly, and so does everything on screen with it, as long as the tail covers the viewport.
///
/// Why only a tail: each laid-out row is redrawn on every streamed update, and costs memory. So the
/// tail is the last exchange plus earlier rows until it covers `screensCovered` viewports, by an
/// estimate of the rows' rendered height (task 1c). Task 1b counted 2,000 characters instead, a
/// different height at every text size: with prose answers on an iPhone 15 Pro Max, about 1.6
/// screens at xSmall, eight at AX3 and fifteen at AX5, every one of them laid out.
///
/// Why whole exchanges (task 1d): the lazy stack sizes a row it hasn't built at the average of the rows
/// it has. A question left at the history's end without its answer was all it had measured there, so
/// the answer that moved in after it was sized as a question: on iOS 17.5 and 18.5, a 1,739 pt answer at
/// about 110 pt, which grew to its own height above a reader scrolling back up to it and carried its
/// actions away from the drag. The tail never starts between a question and its answer.
public enum ChatThreadTail {
    /// The thread and its text as laid out now, in points.
    public struct Metrics: Equatable, Sendable {
        /// The thread's visible height: the tallest seen, so a keyboard that's up doesn't shrink it.
        public var viewportHeight: Double
        /// The widest a line of bubble text can be.
        public var textWidth: Double
        /// The step from one line of bubble text to the next: the line's own height plus its leading.
        public var lineHeight: Double
        /// The average advance of a character of prose set as bubble text.
        public var characterWidth: Double

        public init(viewportHeight: Double, textWidth: Double, lineHeight: Double, characterWidth: Double) {
            self.viewportHeight = viewportHeight
            self.textWidth = textWidth
            self.lineHeight = lineHeight
            self.characterWidth = characterWidth
        }

        /// Each value held within what a phone can show, so a broken measurement can't size the tail
        /// to nothing or to the whole thread.
        var clamped: Metrics {
            Metrics(viewportHeight: min(max(viewportHeight, 200), 2_000),
                    textWidth: min(max(textWidth, 80), 2_000),
                    lineHeight: min(max(lineHeight, 8), 200),
                    characterWidth: min(max(characterWidth, 2), 100))
        }
    }

    /// The tail covers a screen and a half of the thread (estimated), so a one-shot landing on the
    /// last row has only laid-out rows on screen, with the keyboard up or down.
    public static let screensCovered = 1.5
    /// However the estimate comes out, the tail stops taking rows before the last exchange once they hold
    /// this many characters: a ceiling on what a broken measurement can lay out. The row that reaches it
    /// comes whole, with its question, so one row can take the extension past it (task 1c review, nit N-a).
    public static let maximumExtensionCharacters = 6_000
    /// Before the thread has been measured once: the tail holds this many characters (task 1b's rule).
    public static let fallbackCharacters = 2_000

    /// The index of the tail's first row: the last question, or earlier until the tail covers
    /// `screensCovered` viewports (or, without `metrics`, holds `fallbackCharacters`), and never an answer
    /// whose question is just before it (task 1d). With no question, the tail extends back from the last row.
    public static func tailStart(in messages: [ChatMessage], metrics: Metrics?) -> Int {
        guard !messages.isEmpty else { return 0 }
        var start = messages.lastIndex { $0.role == .user } ?? messages.count - 1
        guard let metrics = metrics?.clamped else {
            var characters = messages[start...].reduce(0) { $0 + $1.content.count }
            while start > 0, characters < fallbackCharacters {
                start -= 1
                characters += messages[start].content.count
            }
            return wholeExchange(from: start, in: messages)
        }
        let target = screensCovered * metrics.viewportHeight
        var height = messages[start...].reduce(0) { $0 + estimatedHeight(of: $1.content, metrics: metrics) }
        var extensionCharacters = 0
        while start > 0, height < target, extensionCharacters < maximumExtensionCharacters {
            start -= 1
            height += estimatedHeight(of: messages[start].content, metrics: metrics)
            extensionCharacters += messages[start].content.count
        }
        return wholeExchange(from: start, in: messages)
    }

    /// `start`, or its question when `start` is an answer to the row before it.
    private static func wholeExchange(from start: Int, in messages: [ChatMessage]) -> Int {
        guard start > 0, messages[start].role == .assistant, messages[start - 1].role == .user else { return start }
        return start - 1
    }

    /// Whether the last exchange alone — the last question and everything after it, an answer streaming in, say —
    /// covers the tail's budget, a screen and a half by estimate (task 1d, the I-1 ruling): exactly when the tail is
    /// that exchange alone (`tailStart`). Then the exchanges before it can shed while the answer streams, at the end,
    /// as they would when it completes: the rest of the answer streams with only its own exchange laid out, where
    /// the one before stayed laid out, and redrawn, to its end. No question: nothing to measure from.
    public static func lastExchangeCoversTheBudget(in messages: [ChatMessage], metrics: Metrics) -> Bool {
        guard let last = messages.lastIndex(where: { $0.role == .user }) else { return false }
        let metrics = metrics.clamped
        let height = messages[last...].reduce(0) { $0 + estimatedHeight(of: $1.content, metrics: metrics) }
        return height >= screensCovered * metrics.viewportHeight
    }

    /// A row's rendered height, estimated from its text: each line of the source wraps on its own at
    /// the text width, blank lines (paragraph breaks) add nothing, and the bubble's own padding and
    /// actions row count as one more line. It errs low — list items' spacing isn't counted — so the tail
    /// errs on the side of covering more.
    public static func estimatedHeight(of content: String, metrics: Metrics) -> Double {
        let metrics = metrics.clamped
        let charactersPerLine = max(1, (metrics.textWidth / metrics.characterWidth).rounded(.down))
        var lines = 1.0
        for line in content.split(separator: "\n") where !line.allSatisfy(\.isWhitespace) {
            lines += (Double(visibleCharacterCount(line)) / charactersPerLine).rounded(.up)
        }
        return lines * metrics.lineHeight
    }

    /// Characters that take width: a markdown link's target — `(#item=<uuid>)` after `]`, about 46
    /// characters per citation — draws nothing.
    public static func visibleCharacterCount<S: StringProtocol>(_ text: S) -> Int {
        var count = 0
        var inLinkTarget = false
        var previous: Character?
        for character in text {
            defer { previous = character }
            if inLinkTarget {
                if character == ")" { inLinkTarget = false }
            } else if character == "(", previous == "]" {
                inLinkTarget = true
            } else {
                count += 1
            }
        }
        return count
    }

    // MARK: - Sheds at the end

    /// Within this distance of the content's end the thread's viewport is at its end, for the app's
    /// scroll handling (`AskThreadScrollHandle.endSlack`) and for the tail alike: a drag that comes to rest
    /// there keeps the reader following, the app's end hold applies there, and so may a shed.
    public static let endSlack = 80.0

    /// Whether the tail may shed, now, rows above the reader that it no longer needs: only while the
    /// app's end hold covers the layout pass the shed lands in (task 1c; task 1d, review findings M-1 and
    /// M-2). The shed rows move into the lazy history and are re-estimated there, and everything below
    /// them moves by the difference — unless the end holds still, which it does while the reader follows
    /// within `endSlack` of it and nothing else scrolls the thread (`isBeingScrolled`: a finger, the glide
    /// after one, a scroll UIKit animates that the thread didn't start). And only once the app has seen
    /// the hold work (`holdsSeen`): it rests on UIKit's size-change notifications arriving, in order, and
    /// if they ever stopped, a shed here would show displaced for a frame (task 1b measured 1,070–1,517 pt
    /// without a hold), where no shed only lets the tail grow — which never moves what the reader sees.
    public static func canShedAtTheEnd(isFollowing: Bool, isBeingScrolled: Bool, distanceFromEnd: Double?,
                                       holdsSeen: Bool) -> Bool {
        guard let distanceFromEnd else { return false }
        return isFollowing && !isBeingScrolled && holdsSeen && distanceFromEnd < endSlack
    }

    // MARK: - A send's jump to the end

    /// How the jump to a just-sent question goes (task 1c, review finding I1; task 1d, M-1).
    public struct SendJump: Equatable, Sendable {
        /// The tail sheds to its budget before the jump, from one of the two places where that moves
        /// nothing the reader sees: above the whole tail, every row it sheds is off screen below them;
        /// at the end, every row it sheds is above them, and the app holds the end (`canShedAtTheEnd`).
        public var shedsTail: Bool
        /// A hop of up to one screen from up the thread eases; anything longer cuts (an eased scroll
        /// across screens of history reads as a blur). From the end nothing eases: the app holds the
        /// end while the reader follows, so the new rows are already in view in the layout pass that
        /// adds them, and an ease would have nothing left to move.
        public var animated: Bool
        /// Nothing was shed before the jump — from inside the tail, or from the end while the hold didn't
        /// cover it — so the tail sheds once the jump has landed at the end, the first moment
        /// `canShedAtTheEnd` holds (task 1d, coordinator ruling): the completion shed's geometry, early in the
        /// answer. Never before the jump, so the rows above a reader still up the thread never move.
        public var shedsOnLanding: Bool

        public init(shedsTail: Bool, animated: Bool, shedsOnLanding: Bool) {
            self.shedsTail = shedsTail
            self.animated = animated
            self.shedsOnLanding = shedsOnLanding
        }

        /// Cuts to the end and sheds nothing: a send classified without the thread's geometry, and the
        /// app's value before a send is classified.
        public static let cut = SendJump(shedsTail: false, animated: false, shedsOnLanding: false)
    }

    /// Classifies a send's jump by where the reader is, not by whether they were following:
    /// - from above the whole tail (the viewport ends above the tail's first row) the tail sheds, and the
    ///   jump cuts. Task 1b shed on any send made while not following, which, from a little way up inside
    ///   the last answer, moved rows above the reader;
    /// - from the end, while the app's end hold covers it (`canShedAtTheEnd`), the tail sheds too (task 1d,
    ///   review finding M-1): a reader who drags away while each answer streams never has one complete
    ///   with them at the end, so no completion shed came, and the tail kept every exchange since;
    /// - from anywhere else inside the tail nothing sheds before the jump — the rows above the reader stay as
    ///   they are — and the tail sheds once the jump has landed at the end (`SendJump.shedsOnLanding`), so a
    ///   reader who sends from where they were reading doesn't keep every exchange laid out either.
    ///
    /// A hop of up to one screen from up the thread eases; a longer jump, and any follower's send, cuts.
    /// `distanceFromEnd` is the content's end minus the viewport's bottom; inside the tail it's exact
    /// (nothing there is estimated), above it it's at least the tail's height. Without geometry (no scroll
    /// view yet) the send cuts and sheds nothing, then or on landing.
    public static func sendJump(isFollowing: Bool, isBeingScrolled: Bool, distanceFromEnd: Double?,
                                visibleHeight: Double?, tailHeight: Double, holdsSeen: Bool) -> SendJump {
        guard let distanceFromEnd, let visibleHeight else { return .cut }
        let aboveTheTail = !isFollowing && distanceFromEnd > tailHeight
        let atTheEnd = canShedAtTheEnd(isFollowing: isFollowing, isBeingScrolled: isBeingScrolled,
                                       distanceFromEnd: distanceFromEnd, holdsSeen: holdsSeen)
        let cut = aboveTheTail || distanceFromEnd > visibleHeight
        let shedsNow = aboveTheTail || atTheEnd
        return SendJump(shedsTail: shedsNow, animated: !isFollowing && !cut, shedsOnLanding: !shedsNow)
    }
}
