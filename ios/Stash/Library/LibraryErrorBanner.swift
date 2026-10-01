import SwiftUI

/// Compact, non-blocking banner shown above the grid when a refresh fails while items from
/// a previous load/filter are still on screen. `LibraryStatePane`'s full-bleed error view
/// only covers the *empty* case, so without this a failed refresh with stale items on
/// screen would be silently invisible — the grid just keeps showing the last-known
/// (possibly wrong-filter) data. Auto-dismisses on its own: `ItemStore.loadError` is reset
/// to nil at the top of every `load(reset:)`, so the next successful refresh clears it.
///
/// Plan 16 (HIG + accessibility):
/// - Text is `ink` on the orange: white on system orange is 2.2:1 (below AA for every size);
///   ink is 6.9:1. The glyph follows it.
/// - The message is `meta` and wraps in full (an error is critical text); "Retry" is an inline
///   action — `inlineButton`, Medium 15 — with a 44 pt target (`.stashPlain`) that keeps its one
///   line and its width.
/// - At the accessibility sizes the message takes the banner's width and "Retry" goes on its own
///   line below it, instead of squeezing the message into a narrow column.
struct LibraryErrorBanner: View {
    let message: String
    let retry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    messageRow
                    retryButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    messageRow
                    Spacer(minLength: 8)
                    retryButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(StashColor.ink)
        // .orange has no DESIGN.md token yet.
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityIdentifier("library.errorBanner")
    }

    private var messageRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(message)
                .stashFont(.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .stashFont(.meta)
    }

    private var retryButton: some View {
        Button(action: retry) {
            Text("Retry")
                .stashFont(.inlineButton)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.stashPlain)
        .layoutPriority(1)
        .accessibilityIdentifier("library.errorBanner.retry")
    }
}
