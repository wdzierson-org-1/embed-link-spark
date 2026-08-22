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
    override func viewDidLoad() {
        super.viewDidLoad()

        let compose = ShareComposeView(extensionContext: extensionContext)
        let hosting = UIHostingController(rootView: compose)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}
