import StashKit
import SwiftUI
import UIKit

/// Plan 5 Task 5 scaffold: proves the `StashShareExtension` target exists, builds, embeds in the
/// host app, and appears in the system share sheet with a placeholder card. Real intake
/// (`NSItemProvider` → `SharedObject` mapping, `ShareIntake` orchestration, the actual compose
/// UI) is Task 6/7 — this class deliberately never touches `extensionContext?.inputItems`.
///
/// Extension-safe by construction: no `UIApplication.shared` (unavailable to extensions)
/// anywhere in this file or the view it hosts. No storyboard is used — `Info.plist` names this
/// class directly via `NSExtensionPrincipalClass`, so the system instantiates it with the plain
/// `UIViewController` initializer and sets `extensionContext` before `viewDidLoad`.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let placeholder = PlaceholderShareView { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let hosting = UIHostingController(rootView: placeholder)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}

/// Placeholder-only compose card — no real save/queue logic yet (Task 6/7). References
/// `AppGroup.identifier` (StashKit) purely to prove StashKit actually links into the
/// EXTENSION's own binary, not just the host app's.
private struct PlaceholderShareView: View {
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("Stash")
                    .font(.title2.bold())
                Text("Share extension scaffold (App Group \(AppGroup.identifier))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
