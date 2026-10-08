import SwiftUI

/// Shared full-bleed pane for the grid's empty and load-error states.
///
/// Plan 16: the title is `readingSemibold` and the message `reading` (17, were 14) in `muted`;
/// both are centred and wrap, so at the accessibility sizes the pane grows downward (the tab
/// scrolls) instead of cutting either off, and its side margins narrow from 40 to 20 pt there to
/// leave the words room. The glyph is art — it scales with the text but VoiceOver skips it — and
/// the pane is one VoiceOver stop that reads the title, then the message.
struct LibraryStatePane: View {
    let systemImage: String
    let title: String
    let message: String
    let identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(StashColor.ink)
                .accessibilityHidden(true)
            Text(title)
                .stashFont(.screenTitle)
                .stashTracking(-0.03, role: .screenTitle)
                .foregroundStyle(StashColor.ink)
            Text(message)
                .stashFont(.reading)
                .foregroundStyle(StashColor.muted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { StashDotGrid() }
        .overlay(Rectangle().strokeBorder(StashColor.line, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
