import os
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
///
/// Plan 15 review (memory): the system can reuse one extension process for share after share, so
/// nothing of a finished share may outlive it. The SwiftUI card gets the shared items and a
/// `[weak self]` completion — never the `NSExtensionContext` itself, which would tie this
/// controller's lifetime to the card's — and the card's whole tree (its state, the location
/// manager, preview bitmaps) is torn down as soon as the sheet goes away.
final class ShareViewController: UIViewController {
    /// Fix round 1 (Important review finding): owned here (not by `ShareComposeView`, a plain
    /// `struct` SwiftUI recreates freely) so it survives independent of the SwiftUI view's own
    /// lifecycle and is reachable from `viewDidDisappear` below. See `ShareAbandonTracker`'s own
    /// doc comment for the full discard-on-abandon contract.
    private let abandonTracker = ShareAbandonTracker()
    private var hosting: UIHostingController<ShareComposeView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        // DESIGN.md "Color scheme: light-only" (plan 9): Stash renders in the light palette
        // only, regardless of the host app's (here, the sharing app's) system appearance. The
        // main app pins this via `.preferredColorScheme(.light)` on its root SwiftUI scene, but
        // this extension's SwiftUI content is hosted inside a `UIHostingController` embedded in
        // another process's window hierarchy — trait propagation there isn't guaranteed the same
        // way, so both the container view and the hosting controller's own view are locked at
        // the UIKit trait level as a belt-and-suspenders match to the app's rule.
        view.overrideUserInterfaceStyle = .light

        let compose = ShareComposeView(
            inputItems: extensionContext?.inputItems as? [NSExtensionItem] ?? [],
            abandonTracker: abandonTracker,
            finish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            })
        let hosting = UIHostingController(rootView: compose)
        hosting.view.overrideUserInterfaceStyle = .light
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    /// Fires on EVERY teardown of this extension's UI — an explicit Cancel tap, a completed Save's
    /// own `completeRequest`, or a swipe-to-dismiss the system drives with no app code in the loop
    /// at all (the actual case this fix round closes). Unconditional by design: `abandonTracker`'s
    /// own `consumed` guard is what makes calling this on every path — including the two that
    /// already handled their own file lifecycle — safe rather than a double-discard hazard.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        abandonTracker.discardIfAbandoned()
        // Plan 15 review: the share is over — release the card now rather than whenever the host
        // lets this controller go (the process may serve the next share).
        if let hosting {
            hosting.willMove(toParent: nil)
            hosting.view.removeFromSuperview()
            hosting.removeFromParent()
            self.hosting = nil
            #if DEBUG
            Logger(subsystem: "it.gostash.stash", category: "share").notice("ShareViewController released its card")
            #endif
        }
    }

    #if DEBUG
    deinit {
        Logger(subsystem: "it.gostash.stash", category: "share").notice("ShareViewController deinit")
    }
    #endif
}
