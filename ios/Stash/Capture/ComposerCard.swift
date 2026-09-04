import SwiftUI

/// The Add-tab composer's floating-card shell — re-derived (NOT ported from the old visual-harvest
/// branch) from DESIGN.md §Space "Composer card" / the web's `UnifiedInputPanel.tsx:900-930`
/// `motion.div` shell: `white/90` over a blurred material at `StashRadius.composer`, idle vs.
/// composing entirely owned by Task 0's `stashComposerRing(active:)` (stroke, halo, deep shadow,
/// lift, scale, spring — nothing re-implemented here). `active` mirrors the web's `isPanelActive`;
/// the caller computes that boolean (editor focus OR non-empty draft) and passes it straight
/// through — this view only renders the resulting state, it owns nothing about why.
///
/// `.background()` (not `.clipShape`/`.background(_, in:)` on `content` itself) so nothing this
/// wraps is re-clipped to the card's own rounded bounds — in particular
/// `CaptureAttachmentsRow`'s `.scrollClipDisabled()` remove-×, which deliberately draws past its
/// own ScrollView's edge, must still be free to draw past the card's top edge too.
struct ComposerCard<Content: View>: View {
    let active: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: StashRadius.composer, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Web: `bg-white/90 backdrop-blur-sm` — the material above blurs whatever
                        // sits behind the card (GradientBackdrop); this paper tint on top supplies
                        // the "mostly opaque white" read the web's `/90` opacity gives.
                        RoundedRectangle(cornerRadius: StashRadius.composer, style: .continuous)
                            .fill(StashColor.paper.opacity(0.9))
                    )
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
