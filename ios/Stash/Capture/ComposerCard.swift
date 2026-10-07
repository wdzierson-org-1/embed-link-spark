import SwiftUI

/// The v2 capture object: a solid white, near-square surface. The shared ring owns
/// focus and draft feedback. Keep the surface behind the content so attachment targets
/// that overhang the shell remain reachable.
struct ComposerCard<Content: View>: View {
    let active: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: StashRadius.composer)
                    .fill(StashColor.surface)
            )
            .stashComposerRing(active: active)
            // `.contain` (not the default/`.ignore`): the card itself must be individually
            // discoverable by identifier + value, WITHOUT hiding the editor/attachments/bottom-bar
            // controls nested inside it from their own `capture.*` identifiers — same pattern
            // `DetailURLBar`/`CardHero` already use for an inspectable container with interactive
            // children.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture.card")
            .accessibilityValue(active ? "active" : "idle")
    }
}
