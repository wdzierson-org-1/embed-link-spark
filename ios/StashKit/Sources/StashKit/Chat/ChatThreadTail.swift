import Foundation

/// Plan 16 (tasks 1b and 1c): how the Ask thread splits into a lazily built history and a fully
/// laid-out tail, and how a send's jump to the thread's end goes. Pure: the app (`AskThreadTail` in
/// `AskView.swift`) measures the thread and its text and passes them in.
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
    /// However the estimate comes out, the rows before the last exchange never hold more than this
    /// many characters: a hard ceiling on what a broken measurement can lay out.
    public static let maximumExtensionCharacters = 6_000
    /// Before the thread has been measured once: the tail holds this many characters (task 1b's rule).
    public static let fallbackCharacters = 2_000

    /// The index of the tail's first row: the last question, or earlier until the tail covers
    /// `screensCovered` viewports (or, without `metrics`, holds `fallbackCharacters`). With no question,
    /// the tail extends back from the last row.
    public static func tailStart(in messages: [ChatMessage], metrics: Metrics?) -> Int {
        guard !messages.isEmpty else { return 0 }
        var start = messages.lastIndex { $0.role == .user } ?? messages.count - 1
        guard let metrics = metrics?.clamped else {
            var characters = messages[start...].reduce(0) { $0 + $1.content.count }
            while start > 0, characters < fallbackCharacters {
                start -= 1
                characters += messages[start].content.count
            }
            return start
        }
        let target = screensCovered * metrics.viewportHeight
        var height = messages[start...].reduce(0) { $0 + estimatedHeight(of: $1.content, metrics: metrics) }
        var extensionCharacters = 0
        while start > 0, height < target, extensionCharacters < maximumExtensionCharacters {
            start -= 1
            height += estimatedHeight(of: messages[start].content, metrics: metrics)
            extensionCharacters += messages[start].content.count
        }
        return start
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

    // MARK: - A send's jump to the end

    /// How the jump to a just-sent question goes (task 1c, review finding I1).
    public struct SendJump: Equatable, Sendable {
        /// The reader is above the whole tail, so every row the tail sheds is off screen below them:
        /// it can move into the lazy history before the jump without moving anything they see.
        public var shedsTail: Bool
        /// A hop of up to one screen from up the thread eases; anything longer cuts (an eased scroll
        /// across screens of history reads as a blur). From the end nothing eases: the app holds the
        /// end while the reader follows, so the new rows are already in view in the layout pass that
        /// adds them, and an ease would have nothing left to move.
        public var animated: Bool

        public init(shedsTail: Bool, animated: Bool) {
            self.shedsTail = shedsTail
            self.animated = animated
        }

        /// A send made at the end of the thread.
        public static let fromTheEnd = SendJump(shedsTail: false, animated: false)
    }

    /// Classifies a send's jump by where the reader is, not by whether they were following: only a
    /// reader whose viewport ends above the tail's first row is far enough up for the tail to shed
    /// (task 1b shed on any send made while not following, which, from a little way up inside the last
    /// answer, moved rows above the reader). `distanceFromEnd` is the content's end minus the viewport's
    /// bottom; inside the tail it's exact (nothing there is estimated), above it it's at least the tail's
    /// height. Without geometry (no scroll view yet) the send goes as from the end.
    public static func sendJump(isFollowing: Bool, distanceFromEnd: Double?, visibleHeight: Double?,
                                tailHeight: Double) -> SendJump {
        guard let distanceFromEnd, let visibleHeight else { return .fromTheEnd }
        let aboveTheTail = !isFollowing && distanceFromEnd > tailHeight
        let cut = aboveTheTail || distanceFromEnd > visibleHeight
        return SendJump(shedsTail: aboveTheTail, animated: !isFollowing && !cut)
    }
}
