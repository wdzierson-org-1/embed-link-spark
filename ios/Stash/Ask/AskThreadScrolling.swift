import SwiftUI
import UIKit
import Observation
import StashKit

// The Ask thread's scroll machinery (plan 16): what the thread lays out in full and what it holds still
// for the reader. Moved here from AskView.swift in task 1d (review finding M-6); AskView owns the
// thread's view and decides when to follow, shed and jump, and these carry it out:
// - `AskThreadScrollObserver` and its `Coordinator`: KVO on the thread's UIScrollView — the reader's drags
//   and other scrolls decide following; the holds keep what the reader sees still through every change of
//   size; a status-bar tap, and any long scroll UIKit would animate across the lazy history, is the thread's
//   own cut to its top or its end;
// - `AskThreadScrollHandle`: the scroll state AskView and the observer share, unobserved;
// - `AskThreadStatusBarDelegate`: stands in front of SwiftUI's scroll-view delegate to take status-bar taps;
// - `AskThreadScrollLog` (DEBUG): what moved the thread without a drag, for the UI tests;
// - `AskBubbleTextGauge` and `AskThreadTail`: where the lazy history ends and the laid-out tail begins, and
//   the measurements its budget needs (the rule itself is StashKit's `ChatThreadTail`).

/// Plan 15 review fix (M2): tells the Ask thread whether the USER has left or returned to the end
/// of the conversation. Reports only for user-driven motion — a finger drag or the momentum after
/// one (`isDragging || isDecelerating`) — never for programmatic scrolls, keyboard insets or the
/// content growing under a still viewport, so a burst of streamed lines can't switch following
/// off by itself.
///
/// UIScrollView KVO rather than SwiftUI geometry, for the reason `LibraryView` documents (verified
/// there): on the iOS 17 floor, geometry/preference tracking fires at layout but not during an
/// interactive scroll. Invisible and zero-size; must sit inside the `ScrollView`'s own content so
/// walking `superview` reaches the real `UIScrollView`.
///
/// Reports land on a later main-queue turn (`Coordinator.userScrolled`): the KVO callback also fires
/// when SwiftUI's OWN layout moves the content while a drag or glide is in progress — inside a view
/// update — and a report then would read a mid-layout snapshot. (Plan 15 wrote `@State` here, which
/// was the "Modifying state during view update" runtime issue; task 1c keeps following on the
/// unobserved handle, `AskThreadScrollHandle.isFollowing`.)
///
/// Plan 16 (task 1c): it also holds what the reader sees through every change of size, on every OS
/// (`Coordinator.Hold`). Why: the rows above the laid-out tail are the lazy history's estimates, and
/// whenever it builds or re-estimates one — after a landing, when the keyboard comes up, after a
/// jump, at a completion shed — everything below moves by the difference. The lazy stack keeps its
/// own visible rows still through that, but not the tail, which is outside it; and nothing kept the
/// end through the keyboard, a rotation or a text-size change. With the content's top holding still,
/// as a scroll view's does, every re-estimate moved the reader. On iOS 18.5, task 1b's restored long
/// thread came to rest 816 pt short of its end half a second after it landed; and without the tail
/// hold, a reader a little way up its last answer saw the line they were reading drop 816 pt down
/// the screen when they tapped the composer.
///
/// SwiftUI's own size-change anchor (`defaultScrollAnchor(_:for: .sizeChanges)`, iOS 18 and later)
/// can't do this job: it holds a fixed point of the viewport, so it can't keep a reader's place on
/// the tail while an answer streams below them, and switching it on and off with following means
/// reading `isFollowing` in `body` — whose re-render at the flip is itself what made the history
/// re-estimate under a drag (see `AskView.isFollowing`).
struct AskThreadScrollObserver: UIViewRepresentable {
    /// Receives the thread's UIScrollView once found, and the reader's following.
    let handle: AskThreadScrollHandle

    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        // `didMoveToWindow` is when this view's full ancestor chain (up through the UIScrollView)
        // exists — see `LibraryScrollOffsetObserver` for the verification.
        view.onWindowAttach = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        if uiView.window != nil { context.coordinator.attach(from: uiView) }
    }

    final class ProbeView: UIView {
        var onWindowAttach: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindowAttach?() }
        }
    }

    final class Coordinator {
        /// What a change of size holds still for the reader. Decided from the geometry just BEFORE
        /// the change (the KVO "prior" notification), applied just after it, inside the same
        /// setter — so in the layout pass that made the change, and no frame is drawn displaced.
        /// (Deciding afterwards would read a geometry UIKit has already touched: when the content
        /// shrinks, it clamps the offset inside `setContentSize:` before the change is reported —
        /// by 316 pt in one measured pass on iOS 18.5.)
        enum Hold: Equatable {
            /// The reader follows, with no finger on the thread and the viewport at the end (within
            /// `AskThreadScrollHandle.endSlack`): the viewport keeps this distance from the content's
            /// end. A streamed update, a completion shed, the lazy history re-measuring above, the
            /// keyboard, a rotation, a text-size change: the end stays where it was on screen.
            case end(distance: CGFloat)
            /// Every row on screen is a laid-out tail row (the reader reads inside the tail, following
            /// or not, finger on the thread or not): the viewport keeps its place on the tail. It keeps
            /// this distance from the content's end, plus whatever the tail itself grew by below it, so
            /// a change above the tail (the lazy history re-measuring) moves it with the tail, and an
            /// answer streaming below the reader moves nothing.
            ///
            /// Relative to the end, never to the lazy history's own reported height: SwiftUI reports
            /// that from passes it lays out and drops in the same frame, and holding by those moved
            /// the viewport into rows that then re-estimated it back — on iOS 18.5, an oscillation of
            /// 6,000 pt every frame. The end is laid out, so the viewport's place relative to it is
            /// the same in every pass, and so is what the lazy stack builds near it.
            case tail(distance: CGFloat)
        }

        private let handle: AskThreadScrollHandle
        private var observations: [NSKeyValueObservation] = []
        /// Decided at the prior notification of a content-size or viewport-size change.
        private var contentHold: Hold?
        private var viewportHold: Hold?
        /// The tail's height as of the last content-size change (nil until the first). SwiftUI
        /// reports the tail's new height to the handle before it sets the content size that comes
        /// with it, in the same layout pass (measured on iOS 17.5, 18.5 and 26.5).
        private var tailHeight: CGFloat?
        /// Where the last hold put the viewport, and whether the reader followed then (an end hold) or
        /// not (a tail hold) — kept until this run-loop turn is over — and how many times it has been
        /// put back since (see `offsetChanged`).
        private var held: (offset: CGFloat, following: Bool)?
        private var heldRestores = 0
        private var heldExpiryScheduled = false
        /// The offset the coordinator is writing at this moment, nil otherwise (task 1d; task 1c review, M-4).
        /// A change that lands on it while the write runs is that write. Any other change made while it runs
        /// was made inside it — SwiftUI's delegate answering the move with an offset of its own — and is seen
        /// once the write returns (`applyHold`), never let stand unnoticed as the old flag let it.
        private var ownWrite: CGFloat?
        /// A content-size change's prior notification has come and its after notification hasn't yet: the pair
        /// every hold rests on (`AskThreadScrollHandle.holdsSeen`; task 1d, review finding M-2).
        private var contentSizePriorPending = false
        /// True while a report is scheduled on the main queue (see `userScrolled`).
        private var reportScheduled = false
        /// When the viewport last changed size (the keyboard, a rotation) — see `movedWithoutADrag`.
        private var viewportChangedAt: CFTimeInterval = 0
        /// Where the last tail hold aimed, unrounded (plan 16, task 2d) — see `tailDistance`.
        private var tailHoldTarget: CGFloat?
        /// Stands in for the scroll view's own delegate (SwiftUI's), to take taps on the status bar
        /// (`statusBarTapped`).
        private var statusBarDelegate: AskThreadStatusBarDelegate?
        /// Until when a cut's top is put back, and how many times it has been (`keepCutTop`): only when a pin was
        /// pending at the cut (task 2d re-review, N-2), else 0.
        private var cutHeldUntil: CFTimeInterval = 0
        private var cutRestores = 0
        #if DEBUG
        private let scrollLog = AskThreadScrollLog.isEnabled ? AskThreadScrollLog() : nil
        #endif

        init(handle: AskThreadScrollHandle) {
            self.handle = handle
            #if DEBUG
            handle.scrollLog = scrollLog
            #endif
        }

        func attach(from view: UIView) {
            if observations.isEmpty { observe(from: view) }
            if let scrollView = handle.scrollView { takeStatusBarTaps(scrollView) }
        }

        /// Puts `AskThreadStatusBarDelegate` between the scroll view and its own delegate, once, and again if
        /// SwiftUI has since given the scroll view a delegate of its own.
        ///
        /// Task 1d (task 2d re-review, N-1): the stand-in is kept by the scroll view itself (`retain(on:)`). A
        /// scroll view holds its delegate weakly, and SwiftUI's delegate is kept only by the stand-in, so neither
        /// can go while the scroll view lives, whatever becomes of this coordinator. The scroll view's delegate is
        /// checked again on every scroll and every change of size (`offsetChanged`, `contentSizeChanged`), so a
        /// delegate SwiftUI assigns can't quietly bring back UIKit's animated scroll to the top for long — and a
        /// tap that reached UIKit before the check is still cut short (`cutLongForeignScroll`). In DEBUG every
        /// replacement is logged and counted (`AskThreadScrollLog`, which the status-bar test reads).
        private func takeStatusBarTaps(_ scrollView: UIScrollView) {
            guard let current = scrollView.delegate, current !== statusBarDelegate,
                  !(current is AskThreadStatusBarDelegate) else { return }
            #if DEBUG
            if statusBarDelegate != nil {
                NSLog("ASKTHREAD the thread's scroll view was given a new delegate (%@): taking status-bar taps again",
                      String(describing: type(of: current)))
                scrollLog?.noteRewrap()
            }
            scrollLog?.noteDelegate(String(describing: type(of: current)))
            #endif
            let delegate = AskThreadStatusBarDelegate(swiftUIDelegate: current, coordinator: self)
            delegate.retain(on: scrollView)
            statusBarDelegate = delegate
            scrollView.delegate = delegate
        }

        private func observe(from view: UIView) {
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scrollView = candidate as? UIScrollView {
                    handle.scrollView = scrollView
                    #if DEBUG
                    scrollLog?.attach(to: scrollView.window)
                    #endif
                    observations = [
                        scrollView.observe(\.contentOffset, options: [.old]) { [weak self] scrollView, change in
                            self?.offsetChanged(scrollView, from: change.oldValue?.y)
                        },
                    ]
                    #if DEBUG
                    // `--uitest-without-holds` (UI tests only; task 1d, review finding M-2): the size-change
                    // notifications every hold rests on never come, as if UIKit stopped sending them.
                    if AskThreadScrollHandle.holdsDisabledForTesting { return }
                    #endif
                    observations += [
                        scrollView.observe(\.contentSize, options: [.prior]) { [weak self] scrollView, change in
                            guard let self else { return }
                            if change.isPrior {
                                self.contentSizePriorPending = true
                                self.contentHold = self.hold(scrollView)
                            } else {
                                // The first prior/after pair: the holds work (task 1d, review finding M-2).
                                if self.contentSizePriorPending, !self.handle.holdsSeen { self.handle.holdsSeen = true }
                                self.contentSizePriorPending = false
                                self.contentSizeChanged(scrollView)
                            }
                        },
                        // The viewport's size: the keyboard, a rotation. (`bounds` also changes with
                        // every scroll, as its origin; only a change of size is held.)
                        scrollView.layer.observe(\.bounds, options: [.prior, .old, .new]) { [weak self, weak scrollView] _, change in
                            guard let self, let scrollView else { return }
                            if change.isPrior {
                                self.viewportHold = self.hold(scrollView, followingOnly: true)
                            } else if change.oldValue?.size != change.newValue?.size {
                                self.viewportSizeChanged(scrollView)
                            }
                        },
                    ]
                    return
                }
                ancestor = candidate.superview
            }
        }

        /// What to hold through a change about to land, from the geometry as it stands. The end, while
        /// the reader follows at it with no finger on the thread; otherwise — for content changes only —
        /// the tail, while every row on screen is in it. A viewport that shows any lazy history row is
        /// left alone: the lazy stack keeps its own visible rows still, and a hold on top of that would
        /// move them twice. A viewport-size change is only held at the end: a reader who has scrolled
        /// away keeps their place from the top when the keyboard comes or goes, as before.
        ///
        /// Plan 16 (task 2d): nothing is held while UIKit animates a scroll the thread didn't start
        /// (`AskThreadScrollHandle.foreignScrollIsAnimating`) — a write would retarget it.
        ///
        /// Task 1d: nor while a cut's top is held against the pin it followed (`keepCutTop`), the reader no longer
        /// following. The only rows a hold could keep then are the ones that stray pin landed on. On iOS 26.5 the
        /// pin landed 88 pt short of the end, in a content size about to shrink by 88; as it shrank, `keepCutTop`
        /// put the top back, and the tail hold decided before that, from the pin's place, put the reader back by
        /// the end (3 status-bar runs of 12 on the diag build, 3 of 25 without it, once the mid-stream shed had left
        /// freshly estimated rows next to the tail).
        private func hold(_ scrollView: UIScrollView, followingOnly: Bool = false) -> Hold? {
            if handle.foreignScrollIsAnimating { return nil }
            if !handle.isFollowing, CACurrentMediaTime() < cutHeldUntil { return nil }
            let distance = Self.distanceFromEnd(scrollView)
            if handle.isFollowing, !handle.userIsScrolling, distance < AskThreadScrollHandle.endSlack {
                return .end(distance: max(0, distance))
            }
            guard !followingOnly, let tailHeight,
                  distance + Self.visibleHeight(scrollView) <= tailHeight + 0.5 else { return nil }
            return .tail(distance: tailDistance(scrollView, measured: distance))
        }

        /// A tail hold's distance from the end, measured from where the last tail hold aimed rather than
        /// from where the viewport is, while nothing else has moved it (plan 16, task 2d). A hold's
        /// offset isn't always set exactly — UIKit puts it on the pixel grid, and `setOffset` skips a move
        /// of half a point or less — and measuring the next hold from the viewport kept what was lost.
        /// Over the history's animated re-estimate as the composer takes focus (a small growth every
        /// frame for half a second) that added up to a drop of 1–3 pt in the line being read (iOS 17.5:
        /// 4 runs of 4 with plan 16's taller answers, 1 of 5 with task 1c's).
        private func tailDistance(_ scrollView: UIScrollView, measured: CGFloat) -> CGFloat {
            guard let target = tailHoldTarget, !handle.userIsScrolling,
                  abs(scrollView.contentOffset.y - target) <= 0.5 else { return measured }
            return Self.endOffset(scrollView) - target
        }

        private func contentSizeChanged(_ scrollView: UIScrollView) {
            if scrollView.delegate !== statusBarDelegate { takeStatusBarTaps(scrollView) }
            let newTailHeight = handle.tailHeight
            switch contentHold {
            case .end(let distance)?:
                tailHoldTarget = nil
                applyHold(scrollView, to: Self.endOffset(scrollView) - distance, following: true)
            case .tail(let distance)?:
                let tailGrowth = newTailHeight - (tailHeight ?? newTailHeight)
                tailHoldTarget = applyHold(scrollView, to: Self.endOffset(scrollView) - (distance + tailGrowth),
                                           following: false)
            case nil:
                tailHoldTarget = nil
                held = nil
            }
            contentHold = nil
            tailHeight = newTailHeight
            #if DEBUG
            scrollLog?.noteGeometry(scrollView, following: handle.isFollowing)
            #endif
        }

        private func viewportSizeChanged(_ scrollView: UIScrollView) {
            viewportChangedAt = CACurrentMediaTime()
            if case .end(let distance)? = viewportHold {
                applyHold(scrollView, to: Self.endOffset(scrollView) - distance, following: true)
            }
            viewportHold = nil
        }

        /// Every move of the offset: the user's drags and glides decide following (`userScrolled`), a hold made
        /// this run-loop turn is put back if SwiftUI undoes it (`putBackIfUndone`), and a long scroll UIKit
        /// animates across the lazy history becomes a cut (`cutLongForeignScroll`).
        ///
        /// A move made while the coordinator writes the offset is that write, or a write made inside it, which
        /// the write's caller checks once it returns (`applyHold`; task 1d, review finding M-4) — so neither is a
        /// move to put back, cut short or take for a reader's here.
        private func offsetChanged(_ scrollView: UIScrollView, from oldOffset: CGFloat?) {
            #if DEBUG
            if handle.foreignScrollIsAnimating { scrollLog?.noteAnimatedFrame() }
            if let ownWrite, abs(scrollView.contentOffset.y - ownWrite) > 0.5 { scrollLog?.noteNestedWrite() }
            scrollLog?.noteGeometry(scrollView, following: handle.isFollowing)
            #endif
            if scrollView.delegate !== statusBarDelegate { takeStatusBarTaps(scrollView) }
            let writing = ownWrite != nil
            if !writing, cutLongForeignScroll(scrollView, from: oldOffset) { return }
            if keepCutTop(scrollView) { return }
            let putBack = !writing && putBackIfUndone(scrollView)
            // A drag or the glide after one turns following on or off on the next turn
            // (`userScrolled`) — never a touch-down that hasn't moved, content growth or a hold. Two
            // flag reads are safe inside a layout pass.
            if scrollView.isDragging || scrollView.isDecelerating {
                userScrolled(scrollView)
            } else if !writing, !putBack, let oldOffset {
                movedWithoutADrag(scrollView, from: oldOffset)
            }
        }

        /// Plan 16 (task 2d; task 1c review, M-6): a scroll that isn't a drag leaves the thread's end, or
        /// comes back to it, as a drag does. VoiceOver scrolls what it moves its focus to into view, and
        /// scrolls a page at a three-finger swipe; Switch Control, Voice Control and Full Keyboard Access
        /// scroll too — none of them a drag, so none turned following off, and the follow pins and the
        /// settle after each answer pulled the reader straight back to the end. (A tap on the status bar is
        /// the thread's own cut, which decides following itself: `statusBarTapped`.)
        ///
        /// Only two kinds of move count (task 2d fix round 1, M-3): a scroll UIKit animates that the thread
        /// didn't start (`AskThreadScrollHandle.foreignScrollIsAnimating`), and, while an assistive
        /// technology runs (`assistiveTechnologyRuns`), any move — VoiceOver's scroll to the element it
        /// moves to isn't animated. Every other move without a finger is the system's own and is never a
        /// reader's: SwiftUI setting offsets of its own after a change of size (2,681 and 3,149 pt up as the
        /// keyboard comes or goes, iOS 26.5) or landing a scroll request late, UIKit clamping the offset as
        /// the content shrinks. (Before, only a 0.4 s window after a change of the viewport's size kept those
        /// out, and one landing later would have turned following off, or on.) While an assistive technology
        /// runs, that window still guards the moves it makes without animation.
        ///
        /// Leaving is any such move AWAY from the end that starts at it (within `endSlack`) — the first
        /// frame of an animated scroll is enough, and it has to be: VoiceOver's page scroll moves a point
        /// or two in its first frames, and a pin landing before it had gone further cancelled it. Small
        /// moves count too: a VoiceOver reader moving up to the paragraph before the one streaming keeps
        /// it where it is. Of the moves that count, none of the thread's own can be taken for one:
        /// - the thread's own scrolls (`AskView.scrollToEnd`) only ever go to the end, and only while the
        ///   reader follows;
        /// - the holds are this coordinator's own writes (`ownWrite`), and SwiftUI undoing one is put
        ///   back above, first; in a turn that has made a hold (`held`), no move is taken as a reader's —
        ///   SwiftUI's own writes come in those turns (task 1c), and VoiceOver's scroll in one is put back
        ///   anyway;
        /// - a scroll that starts away from the end — the thread's first layout before its landing —
        ///   isn't leaving it.
        /// Coming back is any such move toward the end that ends within its reach. (Not just the move
        /// that crosses into it: an animated scroll's frame that lands in a turn with a tail hold is put
        /// back, and if that was the frame that crossed, the frames after it are already inside.)
        /// It's decided at once, not on the next turn as a drag is: the next streamed update would pin the
        /// reader back first. And any move away from the end while the reader follows — even one put back,
        /// or in a held turn — holds the pins off for a beat (`AskThreadScrollHandle.pinsHeldOff`): the
        /// first frame of an animated scroll can land in a held turn, and a pin before the next frame would
        /// cancel the scroll.
        private func movedWithoutADrag(_ scrollView: UIScrollView, from oldOffset: CGFloat) {
            guard !scrollView.isTracking else { return }   // a finger is down: its drag decides
            let foreign = handle.foreignScrollIsAnimating
            guard foreign || (handle.assistiveTechnologyRuns && CACurrentMediaTime() - viewportChangedAt > 0.4)
            else { return }
            let slack = AskThreadScrollHandle.endSlack
            let before = Self.endOffset(scrollView) - oldOffset
            let after = Self.distanceFromEnd(scrollView)
            // While UIKit animates a scroll the thread didn't start, nothing holds the end, so a streamed
            // update can grow the content past the end's reach before its first frame: a follower is
            // still leaving the end (iOS 17.5: 266 pt below at a status-bar tap's first frame, before the
            // thread took those taps itself).
            let fromTheEnd = before < slack || foreign
            if handle.isFollowing, fromTheEnd, after > max(before, 0) + 0.5 {
                handle.movedAwayWithoutADragAt = CACurrentMediaTime()
                if held == nil { handle.isFollowing = false }
            } else if !handle.isFollowing, after < slack, after < before {
                handle.isFollowing = true
            }
        }

        /// A tap on the status bar (plan 16, task 2d fix round 1, C-1; from `AskThreadStatusBarDelegate`): the
        /// thread cuts to its top — the content's own top, a laid-out target whatever the lazy history holds,
        /// without animation — and UIKit's animated scroll to the top never runs. That animation crosses the
        /// whole lazy history, rows it can only estimate, and on iOS 26.5, while an answer grew below it and
        /// nothing held (a foreign animation), it now and then stopped the app's main thread for minutes at its
        /// first frame, a jump of 1,700 pt into the history.
        ///
        /// The reader leaves the end as with a drag: following is decided first, from where the cut lands —
        /// off, unless the whole thread is within the end's reach — so no pin or settle pulls them back. Then:
        /// - this coordinator's own write to the top, at once (with `setContentOffset`, so a glide stops, as
        ///   UIKit's own scroll to the top stops it). Every hold this turn then decides from the top. Leaving
        ///   the jump to SwiftUI alone, the content-size change of its own layout pass found the viewport still
        ///   at the end, all tail rows, made a tail hold there, and put SwiftUI's jump back — every time, in a
        ///   stress run of 48 (SwiftUI's next pass jumped again);
        /// - SwiftUI's own scroll to the same top (`AskThreadScrollHandle.scrollToTop`), so its idea of where
        ///   the thread is agrees with the scroll view's;
        /// - and, if a follow pin was pending, the top is held against it (`keepCutTop`): a scroll SwiftUI had in
        ///   hand before the tap — a follow pin requested just before it — lands a pass after the cut, at the old
        ///   end (iOS 26.5: 1 ms and 3 ms after it, 10–11 ms after the pin; a held turn had already ended), and is
        ///   put back.
        ///
        /// Never under a finger. Returns whether the thread took the tap — not before `AskView` has handed over
        /// its scroll to the top, when UIKit's own scroll runs.
        func statusBarTapped(_ scrollView: UIScrollView) -> Bool {
            guard handle.scrollToTop != nil else { return false }
            guard !scrollView.isTracking, !scrollView.isDragging else { return true }
            cutToTop(scrollView)
            #if DEBUG
            scrollLog?.noteCut()
            #endif
            return true
        }

        /// The thread's cut to its top, for a status-bar tap (`statusBarTapped`) or a long scroll heading there
        /// (`cutLongForeignScroll`), in the order the status-bar cut has always taken: following decided from where
        /// the cut lands; this turn's hold, its restores and the tail target dropped; the coordinator's own write to
        /// the top (`cutWrite`); SwiftUI told the same top; and the top held against a pin that was pending.
        private func cutToTop(_ scrollView: UIScrollView) {
            let top = -scrollView.adjustedContentInset.top
            handle.isFollowing = scrollView.contentSize.height <= Self.visibleHeight(scrollView)
                || Self.endOffset(scrollView) - top < AskThreadScrollHandle.endSlack
            held = nil
            heldRestores = 0
            tailHoldTarget = nil
            let now = CACurrentMediaTime()
            cutHeldUntil = now - handle.pinRequestedAt < Self.pendingPinWindow ? now + Self.cutHold : 0
            cutRestores = 0
            cutWrite(scrollView, top)
            handle.scrollToTop?()
        }

        /// At most how long after a cut its top is held against the pin it followed.
        private static let cutHold: CFTimeInterval = 0.25
        /// A follow pin requested this recently before a cut may not have landed yet (it lands in the next layout
        /// pass: 10–11 ms after it in the traces, so this leaves room for a busy main thread).
        private static let pendingPinWindow: CFTimeInterval = 0.3

        /// A cut's top, put back against the pin it followed (see `statusBarTapped`): true when this move was undone.
        ///
        /// Task 1d (task 2d re-review, N-2): the hold is the pending pin's, not a clock's. It's set only if a pin was
        /// requested just before the cut (`pendingPinWindow`), and it puts back only the pin's own move — back to
        /// the old end, within `endSlack` of it — at most until `cutHold`. Any other move stands: a reader's scroll,
        /// and an assistive technology's — VoiceOver's scroll to the element it moves to after the tap lands next to
        /// that element, never at the end it left. (Before, any move off the top within 0.25 s was undone, a
        /// VoiceOver scroll-to-visible included.) Not under a finger, not while UIKit animates a scroll the thread
        /// didn't start, and not once the reader follows again.
        private func keepCutTop(_ scrollView: UIScrollView) -> Bool {
            guard ownWrite == nil, cutRestores < 4, CACurrentMediaTime() < cutHeldUntil, !handle.isFollowing,
                  !handle.userIsScrolling, !handle.foreignScrollIsAnimating else { return false }
            let top = -scrollView.adjustedContentInset.top
            guard scrollView.contentOffset.y > top + 0.5,
                  Self.distanceFromEnd(scrollView) < AskThreadScrollHandle.endSlack else { return false }
            cutRestores += 1
            setOffset(scrollView, top)
            return true
        }

        /// A scroll UIKit animates that the thread didn't start, moving more than a screen in one frame
        /// (`longScrollStep`), becomes the thread's own cut (task 1d; task 2d re-review, "the unheld animated
        /// paths"): the status-bar tap's fix, for the scrolls that don't ask the delegate first. A scroll to the top or the end from a hardware keyboard
        /// (Home and End, ⌘↑ and ⌘↓, which UIKit animates: `allowsKeyboardScrolling`), under Full Keyboard Access too;
        /// Voice Control's "scroll to top" and "scroll to bottom"; a scroll-to-visible of something screens away.
        /// Such an animation crosses the lazy history in jumps of up to thousands of points a frame, into rows it
        /// can only estimate, while an answer may grow below and nothing holds — and on iOS 26.5 the status-bar
        /// animation's first such jump, 1,659 pt, sent SwiftUI's own lazy-stack placement into a loop that never
        /// returned to the run loop (task 2d fix round 1, R-1's samples: one `GraphHost.flushTransactions` holding
        /// the main thread, in `LazyLayoutViewCache.updateItemPhases` and `LazyVStackLayout.sizeThatFits`).
        ///
        /// This runs in such a frame's own KVO callback, as UIKit sets the offset, before SwiftUI lays the far rows
        /// out. Upward it's the cut to the top (`cutToTop`, the status-bar tap's); downward, a cut to the end
        /// (`cutToEnd`), where the reader follows again. Scrolls that move less than that a frame run as before: VoiceOver's three-finger page, Page Up
        /// and Page Down, the arrow keys, a scroll-to-visible nearby — and a fling, which UIKit doesn't animate. A
        /// scroll-to-visible of a row screens away lands at the top or the end rather than on the row: UIKit doesn't
        /// say where its animation is headed. Never under a finger.
        ///
        /// It needs iOS 17.4's `isScrollAnimating` (`AskThreadScrollHandle.foreignScrollIsAnimating`). On iOS
        /// 17.0–17.3 nothing tells the thread such a scroll is UIKit's, so while an answer streams the holds take it
        /// back and the reader stays at the end (task 2d's trade-off; measured on 17.0 in task 1d): it never crosses
        /// the history there; once the answer is done it runs uncut, as before plan 16.
        private func cutLongForeignScroll(_ scrollView: UIScrollView, from oldOffset: CGFloat?) -> Bool {
            // While VoiceOver or Switch Control runs every row is laid out (`AskThreadTail.historyCount`), so there
            // are no estimates to cross, and VoiceOver's long scrolls (a rotor jump) go where its focus goes.
            guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return false }
            // Not a clamp inside `setContentSize:` (`contentSizePriorPending`): that moves the offset by the content's
            // change, not by the animation. (Steps between UIKit's frames do come with content-size changes — the lazy
            // stack re-measuring as rows come into view — and they are the animation's own: SwiftUI doesn't write
            // offsets of its own during it, in the traces of task 2d.)
            guard handle.foreignScrollIsAnimating, !contentSizePriorPending, let oldOffset, handle.scrollToTop != nil,
                  handle.scrollToEnd != nil, !scrollView.isTracking, !scrollView.isDragging else { return false }
            let step = scrollView.contentOffset.y - oldOffset
            guard abs(step) > Self.longScrollStep * Self.visibleHeight(scrollView) else { return false }
            if step < 0 { cutToTop(scrollView) } else { cutToEnd(scrollView) }
            #if DEBUG
            scrollLog?.noteLongScrollCut()
            #endif
            return true
        }

        /// A frame of a scroll UIKit animates that moves more than this many screens is a long scroll's
        /// (`cutLongForeignScroll`): one screen, so two frames' viewports don't even overlap and each lands in rows the
        /// lazy stack has to place from estimates — the hazard R-1's samples show (the status-bar animation's first
        /// frame jumped 2.7 screens, 1,659 pt of 616, on iOS 26.5). An animated scroll to the top of the long thread
        /// moves about 900 pt a frame (17,000 pt in 19); a page scroll a screen in all, over all its frames, so even
        /// a busy main thread delivering it in one frame isn't more than a screen; a fling, which UIKit doesn't
        /// animate, and a scroll-to-visible nearby much less a frame. (Speed between KVO callbacks is no measure: two
        /// offset changes can land in one frame, and a VoiceOver page scroll read as 12 screens a second was cut.)
        private static let longScrollStep: CGFloat = 1

        /// The thread's cut to its end, for a long scroll heading there (`cutLongForeignScroll`): the reader follows
        /// again, this turn's holds are dropped, the coordinator writes the content's end at once (`cutWrite`, which
        /// stops UIKit's animation), and SwiftUI lands on the last row (`AskThreadScrollHandle.scrollToEnd`: the
        /// thread's own `scrollToEnd`, a laid-out target).
        private func cutToEnd(_ scrollView: UIScrollView) {
            handle.isFollowing = true
            held = nil
            heldRestores = 0
            tailHoldTarget = nil
            cutHeldUntil = 0
            cutWrite(scrollView, Self.clampedOffset(scrollView, Self.endOffset(scrollView)))
            handle.scrollToEnd?()
        }

        /// A cut's own write: `setContentOffset(_:animated: false)`, which also stops a glide or a scroll UIKit is
        /// animating, as UIKit's own scroll to the top stops them.
        private func cutWrite(_ scrollView: UIScrollView, _ y: CGFloat) {
            let outer = ownWrite
            ownWrite = y
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
            ownWrite = outer
        }

        /// Keeps a hold's offset for the rest of this run-loop turn (the update it was made in, and
        /// the frame it draws), then lets it go.
        private func keepHeld(_ offset: CGFloat, following: Bool) {
            held = (offset, following)
            guard !heldExpiryScheduled else { return }
            heldExpiryScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.held = nil
                self.heldRestores = 0
                self.heldExpiryScheduled = false
            }
        }

        /// Sets the offset — never above the content's top or past its end — and returns where it put
        /// it.
        @discardableResult
        private func setOffset(_ scrollView: UIScrollView, _ y: CGFloat) -> CGFloat {
            let target = Self.clampedOffset(scrollView, y)
            if abs(scrollView.contentOffset.y - target) > 0.5 {
                let outer = ownWrite
                ownWrite = target
                scrollView.contentOffset.y = target
                ownWrite = outer
            }
            return target
        }

        /// A hold (task 1d; task 1c review, M-4). The offset it keeps is recorded for the turn BEFORE it's written,
        /// so that a write SwiftUI makes inside this one — its delegate answering the move — is an undo like any
        /// other in a held turn: once the write returns, an offset left elsewhere is put back (`putBackIfUndone`), at
        /// most 4 times a turn. (Before, a change made during the coordinator's own write was skipped whatever it
        /// was, and the hold recorded only after it, so a write inside one could stand.) Returns where the hold
        /// keeps the viewport.
        @discardableResult
        private func applyHold(_ scrollView: UIScrollView, to y: CGFloat, following: Bool) -> CGFloat {
            let target = Self.clampedOffset(scrollView, y)
            keepHeld(target, following: following)
            setOffset(scrollView, target)
            while putBackIfUndone(scrollView) {}
            return held?.offset ?? target
        }

        /// Puts this turn's hold back if the offset now undoes it, and returns whether it did — after any move that
        /// isn't the coordinator's own (`offsetChanged`), and once a hold's own write returns (`applyHold`).
        ///
        /// Why put back: in an update that lays the thread out more than once (the lazy history
        /// re-estimating as the keyboard comes up, say), SwiftUI can set the offset itself after a
        /// hold, discarding it. On iOS 18.5, after UIKit had clamped the offset inside
        /// `setContentSize:` as the content shrank, SwiftUI wrote back the offset the update began
        /// with: tail holds that had kept a reader's line still through +2,990, −544 and +2,534 pt
        /// were wiped, and the line dropped 1,990 pt (1 run in 3). On iOS 26.5, right after an end hold
        /// it set an offset of its own: a restored long thread at rest at its end was left 2,637 pt
        /// short of it when the keyboard came up, every time.
        ///
        /// Put back only what a hold of the same kind would still keep, and never under a finger. A
        /// tail hold (the reader doesn't follow): any move, since then nothing else moves the offset
        /// programmatically. An end hold (the reader follows): a move up, away from the end, or past
        /// it — a follower's own jumps and pins only ever go to the end, and those stand.
        private func putBackIfUndone(_ scrollView: UIScrollView) -> Bool {
            guard let held, heldRestores < 4, !handle.userIsScrolling, handle.isFollowing == held.following,
                  !handle.foreignScrollIsAnimating else { return false }
            let offset = scrollView.contentOffset.y
            let lastOffset = max(-scrollView.adjustedContentInset.top, Self.endOffset(scrollView))
            let undone = held.following
                ? offset < held.offset - 0.5 || offset > lastOffset + 0.5
                : abs(offset - held.offset) > 0.5
            // Where the put-back would land: UIKit may have put the offset there already — as the content
            // shrinks it clamps the offset to the new end, where an end hold aimed — and then nothing was
            // undone, and nothing moved away (task 2d fix round 1, M-2: in the status-bar test's traces on
            // iOS 26.5, 51 of 52 put-backs were such no-ops, each holding the next pin off for a beat).
            let target = Self.clampedOffset(scrollView, held.offset)
            guard undone, abs(offset - target) > 0.5 else { return false }
            heldRestores += 1
            // A move up undone under an end hold may be the first frame of a scroll that isn't
            // a drag: the next pin waits a beat, so it can go on (see `movedWithoutADrag`).
            if held.following, offset < target { handle.movedAwayWithoutADragAt = CACurrentMediaTime() }
            setOffset(scrollView, held.offset)
            return true
        }

        /// `y`, kept between the content's top and its end, as `setOffset` writes it.
        static func clampedOffset(_ scrollView: UIScrollView, _ y: CGFloat) -> CGFloat {
            let top = -scrollView.adjustedContentInset.top
            return max(top, min(y, max(top, endOffset(scrollView))))
        }

        /// The offset at which the viewport's bottom meets the content's end.
        static func endOffset(_ scrollView: UIScrollView) -> CGFloat {
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        }

        /// How far the content's end is below the viewport's bottom (negative when the content is
        /// shorter than the viewport).
        static func distanceFromEnd(_ scrollView: UIScrollView) -> CGFloat {
            endOffset(scrollView) - scrollView.contentOffset.y
        }

        static func visibleHeight(_ scrollView: UIScrollView) -> CGFloat {
            let insets = scrollView.adjustedContentInset
            return scrollView.bounds.height - insets.top - insets.bottom
        }

        /// Records whether the thread now rests at its end, on the next main-queue turn — outside
        /// whatever layout pass may be running now. A burst of offset changes coalesces into one
        /// report, which reads the layout as it stands then rather than a mid-layout snapshot. The lag
        /// is harmless: a follow-scroll can't pin in between, because it holds off while
        /// `AskThreadScrollHandle.userIsScrolling`.
        private func userScrolled(_ scrollView: UIScrollView) {
            guard !reportScheduled else { return }
            reportScheduled = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self else { return }
                self.reportScheduled = false
                guard let scrollView else { return }
                self.handle.isFollowing = Self.isAtEnd(scrollView)
            }
        }

        /// A thread shorter than the viewport is always "at the end" (so a rubber-band pull on a
        /// short thread doesn't stop following); otherwise within `endSlack` of the last row counts.
        static func isAtEnd(_ scrollView: UIScrollView) -> Bool {
            guard scrollView.contentSize.height > visibleHeight(scrollView) else { return true }
            return distanceFromEnd(scrollView) < AskThreadScrollHandle.endSlack
        }
    }
}

/// The Ask thread's scroll state, shared by `AskView` and `AskThreadScrollObserver` and held in
/// `@State`: a weak reference to the thread's UIScrollView, so follow-scrolls can check whether the
/// user's finger — or the glide after it — is on the thread right now; whether the reader follows;
/// and the measured heights the observer's holds and a send's classification need. Unobserved:
/// writing to it never re-renders anything.
final class AskThreadScrollHandle {
    /// Within this distance of the content's end the viewport is at the end: a drag that comes to
    /// rest there keeps following, the end hold applies, and so may a shed above the reader (task 1d:
    /// StashKit's `ChatThreadTail.endSlack`, so the hold and the shed's rule can't disagree about the end).
    static let endSlack = CGFloat(ChatThreadTail.endSlack)

    weak var scrollView: UIScrollView?
    /// The reader follows the thread (see `AskView.isFollowing`).
    var isFollowing = true
    /// When a scroll that isn't a drag last moved the viewport away from the end while the reader
    /// followed (plan 16, task 2d) — VoiceOver's, say. See `pinsHeldOff`.
    var movedAwayWithoutADragAt: CFTimeInterval = 0

    /// A streamed update doesn't pin the end for a beat after such a move: the scroll is animated, and a
    /// pin cancels it. Its first frames can land in a turn whose hold puts them back, so it may not have
    /// left the end yet; a frame or two later it has, and following is off. (Sends and retries still
    /// jump.)
    var pinsHeldOff: Bool { CACurrentMediaTime() - movedAwayWithoutADragAt < 0.12 }
    /// When the thread's own eased jump last started (`AskView.scrollToEnd(_:animated: true)`).
    var ownScrollAnimationAt: CFTimeInterval = 0

    /// UIKit is animating a scroll the thread didn't start: VoiceOver's page or scroll-to-visible, Voice
    /// Control's or Full Keyboard Access's (plan 16, task 2d) — not a status-bar tap's, which the thread
    /// takes itself as a cut (`AskThreadScrollObserver.Coordinator.statusBarTapped`); and one that moves more
    /// than a screen in a frame is cut short at once (task 1d, `cutLongForeignScroll`). While it runs, nothing
    /// holds, puts back or pins — it's let run, and where it goes decides following (`movedWithoutADrag`).
    /// A write to the offset before its first frame retargets it to that offset, and the scroll is lost: on
    /// iOS 17.5 a streamed update's end hold landed between a status-bar tap and its first frame in 4 runs
    /// of 8, and UIKit then animated to the held end for 200 ms. iOS 17.4 and later (`isScrollAnimating`);
    /// before that nothing tells, and a scroll can still be lost that way.
    var foreignScrollIsAnimating: Bool {
        guard #available(iOS 17.4, *) else { return false }
        guard let scrollView, scrollView.isScrollAnimating else { return false }
        return CACurrentMediaTime() - ownScrollAnimationAt > 0.4
    }

    /// An assistive technology that scrolls the thread without a drag runs: VoiceOver or Switch Control
    /// (plan 16, task 2d fix round 1, M-3; see `AskThreadScrollObserver.Coordinator.movedWithoutADrag`). In
    /// DEBUG, `--uitest-a11y-hooks` stands in for one, as its controls stand in for VoiceOver's scrolls.
    var assistiveTechnologyRuns: Bool {
        if UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning { return true }
        #if DEBUG
        return Self.standsInForAssistiveTechnology
        #else
        return false
        #endif
    }
    #if DEBUG
    private static let standsInForAssistiveTechnology = ProcessInfo.processInfo.arguments.contains("--uitest-a11y-hooks")
    /// `--uitest-without-holds` (UI tests only; task 1d, review finding M-2): the observer never subscribes to the
    /// size-change notifications its holds rest on — a stand-in for UIKit no longer sending them.
    static let holdsDisabledForTesting = ProcessInfo.processInfo.arguments.contains("--uitest-without-holds")
    /// The coordinator's `--uitest-scroll-log`, for `AskView` to report the thread's split to (nit N-d).
    var scrollLog: AskThreadScrollLog?
    #endif

    /// SwiftUI's scroll to the thread's top, set by `AskView` from inside its `ScrollViewReader`: the
    /// thread's cut when the status bar is tapped (`AskThreadScrollObserver.Coordinator.statusBarTapped`).
    var scrollToTop: (() -> Void)?
    /// SwiftUI's scroll to the thread's end — the last row, as `AskView.scrollToEnd` lands it — set beside
    /// `scrollToTop`: the thread's cut to its end for a long scroll heading there (task 1d,
    /// `AskThreadScrollObserver.Coordinator.cutLongForeignScroll`).
    var scrollToEnd: (() -> Void)?
    /// When `AskView` last asked SwiftUI to scroll to the end (a pin, a send's jump, a landing). SwiftUI lands it a
    /// layout pass later, so a cut made just after one holds its top against it (task 2d re-review, N-2).
    var pinRequestedAt: CFTimeInterval = 0
    /// The scroll observer has seen the notifications its holds rest on: a content-size change's prior and after
    /// notifications, in that order (task 1d, review finding M-2). Every shed above the reader waits for it
    /// (`ChatThreadTail.canShedAtTheEnd`): if UIKit stopped sending them, the holds would vanish without a sound
    /// and each such shed would show displaced for a frame, where no shed only lets the tail grow — as task 1b's
    /// did — which moves nothing.
    var holdsSeen = false
    /// The laid-out tail's height (task 1c), measured as it changes — how far above the end the
    /// tail's first row is, for the observer's tail hold and a send's classification
    /// (`ChatThreadTail.sendJump`).
    var tailHeight: CGFloat = 0

    /// A finger is on the thread or its momentum is still moving it: touch-down (`isTracking` —
    /// true a beat before `isDragging`, so a pin can't land under a finger that has only just
    /// touched), a drag, or the glide after a lift. Follow-scrolls hold off while this is true.
    /// Broader than what may turn following OFF — that is a drag or glide only
    /// (`AskThreadScrollObserver`), since a bare touch-down moves nothing.
    var userIsScrolling: Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }

    /// Something other than the thread's own jumps moves it now — a finger, the glide after one, or a scroll
    /// UIKit animates that the thread didn't start — so the end hold doesn't apply (task 1d; StashKit's
    /// `ChatThreadTail.canShedAtTheEnd`).
    var isBeingScrolled: Bool { userIsScrolling || foreignScrollIsAnimating }

    /// Any scroll of the thread is animating, the thread's own eased jump included (iOS 17.4 and later; before
    /// that nothing tells): a jump that hasn't landed yet (task 1d).
    var scrollIsAnimating: Bool {
        guard #available(iOS 17.4, *), let scrollView else { return false }
        return scrollView.isScrollAnimating
    }

    /// Where the viewport is: its bottom's distance from the content's end (never negative), and its
    /// visible height. Inside the laid-out tail the distance is exact; above it, it includes the lazy
    /// history's estimate of the rows in between, which only ever adds to it.
    var endGeometry: (distanceFromEnd: CGFloat, visibleHeight: CGFloat)? {
        guard let scrollView else { return nil }
        return (max(0, AskThreadScrollObserver.Coordinator.distanceFromEnd(scrollView)),
                AskThreadScrollObserver.Coordinator.visibleHeight(scrollView))
    }
}

/// Stands between the Ask thread's scroll view and its own delegate — SwiftUI's — and passes every message
/// on to it, except a tap on the status bar (plan 16, task 2d fix round 1, C-1): the thread takes that itself
/// (`AskThreadScrollObserver.Coordinator.statusBarTapped`), so UIKit's animated scroll to the top never runs
/// across the lazy history. SwiftUI's delegate is kept here, strongly: the scroll view only holds this one
/// weakly, and a message forwarded to a delegate that had gone would crash. And this one is kept by the scroll
/// view itself (`retain(on:)`, task 1d; task 2d re-review, N-1), so it — and SwiftUI's delegate with it — lives
/// exactly as long as the scroll view, whatever becomes of the coordinator that made it.
private final class AskThreadStatusBarDelegate: NSObject, UIScrollViewDelegate {
    let swiftUIDelegate: any UIScrollViewDelegate
    private weak var coordinator: AskThreadScrollObserver.Coordinator?
    private static var retainKey: UInt8 = 0

    init(swiftUIDelegate: any UIScrollViewDelegate, coordinator: AskThreadScrollObserver.Coordinator) {
        self.swiftUIDelegate = swiftUIDelegate
        self.coordinator = coordinator
    }

    /// Kept by `scrollView` from now on (an associated object): a later stand-in replaces this one there.
    func retain(on scrollView: UIScrollView) {
        objc_setAssociatedObject(scrollView, &Self.retainKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || swiftUIDelegate.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        swiftUIDelegate.responds(to: aSelector) ? swiftUIDelegate : super.forwardingTarget(for: aSelector)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        // SwiftUI's own answer first: what it won't scroll to the top isn't scrolled at all.
        if swiftUIDelegate.scrollViewShouldScrollToTop?(scrollView) == false { return false }
        guard let coordinator, coordinator.statusBarTapped(scrollView) else { return true }
        return false
    }
}

#if DEBUG
/// `--uitest-scroll-log` (UI tests only; plan 16, task 2d fix round 1; task 1d): what moved the thread without a
/// drag, and how its delegate stand-in fares, as the label of an invisible element on the thread's window,
/// `ask.debug.scrollLog`: "animated N · cut M · long L · rewrap R · nested W" — the frames of scrolls UIKit
/// animated that the thread didn't start, the status-bar taps it cut to the top, the long animated scrolls it cut
/// short (`cutLongForeignScroll`), the times the scroll view was given a new delegate (`takeStatusBarTaps`), and
/// the writes made inside the coordinator's own (review finding M-4). Its value is the class of the delegate the
/// stand-in wraps — SwiftUI's — probed on each OS. A second element, `ask.debug.tail`, is the thread's split
/// (task 1c review, nit N-d): "history H · rows R", the lazy history's rows and the laid-out tail's. UIKit views,
/// so updating them re-renders nothing. Compiled out of Release.
final class AskThreadScrollLog {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--uitest-scroll-log")

    private let element = AskThreadScrollLog.marker("ask.debug.scrollLog")
    private let tailElement = AskThreadScrollLog.marker("ask.debug.tail")
    private var animatedFrames = 0
    private var cuts = 0
    private var longScrollCuts = 0
    private var rewraps = 0
    private var nestedWrites = 0

    private static func marker(_ identifier: String) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = identifier
        return view
    }

    func attach(to window: UIWindow?) {
        guard let window, element.window !== window else { return }
        window.addSubview(element)
        window.addSubview(tailElement)
        update()
    }

    func noteAnimatedFrame() {
        animatedFrames += 1
        update()
    }

    func noteCut() {
        cuts += 1
        update()
    }

    func noteLongScrollCut() {
        longScrollCuts += 1
        update()
    }

    func noteRewrap() {
        rewraps += 1
        update()
    }

    func noteNestedWrite() {
        nestedWrites += 1
        update()
    }

    func noteDelegate(_ name: String) {
        element.accessibilityValue = name
    }

    func noteSplit(history: Int, total: Int) {
        tailElement.accessibilityLabel = "history \(history) · rows \(total - history)"
    }

    /// The thread's geometry as the app has it, as the tail element's value: for a UI test's failure diagnostics
    /// (task 1d; task 2d review, I-2) to set against the frames XCUITest reports.
    func noteGeometry(_ scrollView: UIScrollView, following: Bool) {
        let insets = scrollView.adjustedContentInset
        let endGap = scrollView.contentSize.height + insets.bottom - scrollView.bounds.height - scrollView.contentOffset.y
        tailElement.accessibilityValue = String(format: "offset %.1f · content %.1f · viewport %.1f · end gap %.1f · %@",
                                                scrollView.contentOffset.y, scrollView.contentSize.height,
                                                scrollView.bounds.height, endGap, following ? "following" : "not following")
    }

    private func update() {
        element.accessibilityLabel = "animated \(animatedFrames) · cut \(cuts) · long \(longScrollCuts) · rewrap \(rewraps)"
            + " · nested \(nestedWrites)"
    }
}
#endif

/// Task 1c: measures bubble text as `ChatBubble` sets it (`chatBubbleText()`), for the tail's height
/// budget (`ChatThreadTail.Metrics`): the step from one line to the next, leading included, and the
/// average width of a character of prose. Hidden behind the thread; it re-measures whenever the
/// bubbles would re-lay out (text size, Bold Text). Writes to `AskThreadTail`'s unobserved fields, so
/// measuring never re-renders anything.
struct AskBubbleTextGauge: View {
    let tail: AskThreadTail

    /// A line of plain prose, for the average character width.
    static let sample = "Here is what your saved notes and links say about it, and where they differ."

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(Self.sample)
                .chatBubbleText()
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { tail.gaugeSample = $0 }
            Text("Ag\nAg\nAg")
                .chatBubbleText()
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tail.gaugeThreeLines = $0 }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where the Ask thread's lazily built history ends and its fully laid-out tail begins (plan 16,
/// tasks 1b and 1c). The rule itself — why a tail, how big — is `ChatThreadTail` in StashKit; this
/// holds the split for the thread on screen and the measurements the rule needs.
///
/// The split is read during `body`, and set there for a new thread (keyed by its first row), so a
/// thread's first render already has it. Rows only ever move from the tail into the history, a whole
/// exchange at a time (task 1d: `ChatThreadTail.tailStart` never starts the tail at an answer whose
/// question is just before it), and only when the rows that move are off screen:
/// - a send from above the whole tail (`ChatThreadTail.sendJump`): they're below the reader, and the
///   jump lands on the new rows;
/// - with the reader following at the end, the scroll observer holding the end through that layout pass
///   (`AskThreadScrollObserver`; `ChatThreadTail.canShedAtTheEnd`), the rows being above the reader: when an
///   answer completes there (task 1c); (task 1d, review finding M-1) when a question is sent from there,
///   or, sent from inside the tail, once its jump has landed there (`shedOnLandingPending`) — so a reader who
///   drags away while answers stream no longer keeps every exchange laid out; and (task 1d, the I-1 ruling)
///   while an answer streams there, once its exchange alone covers the budget
///   (`ChatThreadTail.lastExchangeCoversTheBudget`). Task 1b measured a one-frame
///   flash of 1,070–1,517 pt when it shed at the end without the hold, so it didn't: new exchanges piled up in
///   the tail while the reader followed, and each one kept laid out added about ten dropped frames to every
///   later streamed answer. None of these sheds happens until the observer has seen its holds work (M-2).
///
/// A moved row is rebuilt and loses its own state, as a lazy row scrolled far away sometimes does
/// anyway; a given rating lives in `ChatRatings`, so it stays.
///
/// Plan 16 (task 2d): while VoiceOver or Switch Control runs, there is no lazy history — every row is
/// in the laid-out tail (`laysOutEverything`). Both move through the thread one element at a time, in
/// the order of the accessibility tree, and a lazy stack's tree holds only the rows it has built near
/// the screen, while the tail is always in it, after them. So from the last element of the last row the
/// history had built, the next was the tail's first — every row in between skipped. Measured on iOS
/// 26.5 (`A11yAskUITests`, long prose thread): with an answer's last element at the thread's bottom
/// edge, the least VoiceOver scrolls to show it, the next question wasn't built in 1 of 4 places. The
/// cost is the one the tail was bounded to avoid — every row redrawn as an answer streams — paid only
/// while one of them runs.
@Observable
final class AskThreadTail {
    /// What a line of bubble text is left with of the thread's width (`ChatBubbleLayout`): the
    /// thread's padding, an answer bubble's far-side gap and spacing, and its own padding.
    static let bubbleTextInset: CGFloat = ChatBubbleLayout.answerTextInset

    @ObservationIgnored private var threadKey: String?
    @ObservationIgnored private var historyEnd = 0
    @ObservationIgnored private var laysOutEverything = false
    /// `AskBubbleTextGauge`'s measurements: one line of sample prose, and three short lines.
    @ObservationIgnored var gaugeSample: CGSize = .zero
    @ObservationIgnored var gaugeThreeLines: CGFloat = 0
    /// The thread's size now, and the tallest it has been (so the budget isn't cut while the
    /// keyboard is up).
    @ObservationIgnored private var viewport: CGSize = .zero
    @ObservationIgnored private var tallestViewport: CGFloat = 0
    /// Bumped by `shed`, so the thread re-renders with the new split.
    private var sheds = 0
    /// The last send shed nothing before its jump (`ChatThreadTail.SendJump.shedsOnLanding`), so the tail sheds
    /// once the jump has landed at the end (task 1d; `AskView.followThread`). Unobserved: setting it re-renders
    /// nothing.
    @ObservationIgnored var shedOnLandingPending = false

    func noteViewport(_ size: CGSize) {
        viewport = size
        tallestViewport = max(tallestViewport, size.height)
    }

    /// The budget's inputs, once the thread and the gauge have both been measured.
    var metrics: ChatThreadTail.Metrics? {
        let characters = CGFloat(AskBubbleTextGauge.sample.count)
        guard gaugeSample.width > 0, gaugeThreeLines > gaugeSample.height,
              viewport.width > Self.bubbleTextInset, tallestViewport > 0 else { return nil }
        return ChatThreadTail.Metrics(viewportHeight: Double(tallestViewport),
                                      textWidth: Double(viewport.width - Self.bubbleTextInset),
                                      lineHeight: Double((gaugeThreeLines - gaugeSample.height) / 2),
                                      characterWidth: Double(gaugeSample.width / characters))
    }

    /// How many leading rows of `messages` are lazy history. The rest are the tail, which always
    /// holds at least the last row — and every row, while `laysOutEverything` (VoiceOver or Switch
    /// Control runs; see the type doc).
    func historyCount(for messages: [ChatMessage], laysOutEverything: Bool) -> Int {
        _ = sheds
        let key = messages.first?.id
        if key != threadKey || laysOutEverything != self.laysOutEverything {
            threadKey = key
            self.laysOutEverything = laysOutEverything
            historyEnd = laysOutEverything ? 0 : ChatThreadTail.tailStart(in: messages, metrics: metrics)
        }
        // A rollback (a question that failed before its first token) can leave the split past the
        // last row. Stored back, so the next rows appended stay in the tail rather than moving
        // finished rows out of it while the reader follows (review nit N1).
        historyEnd = min(historyEnd, max(0, messages.count - 1))
        return historyEnd
    }

    /// Moves the rows the tail no longer needs into the history — only at the moments above, and
    /// never while every row is laid out.
    func shed(_ messages: [ChatMessage]) {
        guard !laysOutEverything else { return }
        let start = ChatThreadTail.tailStart(in: messages, metrics: metrics)
        guard messages.first?.id == threadKey, start > historyEnd else { return }
        historyEnd = start
        sheds += 1
    }
}
