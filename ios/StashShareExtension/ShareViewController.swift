import StashKit
import SwiftUI
import UIKit

/// Task 5 built this class as a placeholder scaffold; Task 7 wires in the real compose card
/// (`ShareComposeView`) — provider loading, note, location pin, save/queue, and dismissal all live
/// there now. This class's own job stays exactly what Task 5 established: host that SwiftUI view
/// via `UIHostingController` and nothing else.
///
/// Extension-safe by construction: no `UIApplication.shared` (unavailable to extensions) anywhere
/// in this file. No storyboard is used — `Info.plist` names this class directly via
/// `NSExtensionPrincipalClass`, so the system instantiates it with the plain `UIViewController`
/// initializer and sets `extensionContext` before `viewDidLoad`.
final class ShareViewController: UIViewController {
    /// Fix round 1 (Important review finding): owned here (not by `ShareComposeView`, a plain
    /// `struct` SwiftUI recreates freely) so it survives independent of the SwiftUI view's own
    /// lifecycle and is reachable from `viewDidDisappear` below. See `ShareAbandonTracker`'s own
    /// doc comment for the full discard-on-abandon contract.
    private let abandonTracker = ShareAbandonTracker()

    override func viewDidLoad() {
        super.viewDidLoad()

        let compose = ShareComposeView(extensionContext: extensionContext, abandonTracker: abandonTracker)
        let hosting = UIHostingController(rootView: compose)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    /// Fires on EVERY teardown of this extension's UI — an explicit Cancel tap, a completed Save's
    /// own `completeRequest`, or a swipe-to-dismiss the system drives with no app code in the loop
    /// at all (the actual case this fix round closes). Unconditional by design: `abandonTracker`'s
    /// own `consumed` guard is what makes calling this on every path — including the two that
    /// already handled their own file lifecycle — safe rather than a double-discard hazard.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        abandonTracker.discardIfAbandoned()
    }
}
