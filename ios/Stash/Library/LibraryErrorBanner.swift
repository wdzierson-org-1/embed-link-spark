import SwiftUI

/// Compact, non-blocking banner shown above the grid when a refresh fails while items from
/// a previous load/filter are still on screen. `LibraryStatePane`'s full-bleed error view
/// only covers the *empty* case, so without this a failed refresh with stale items on
/// screen would be silently invisible — the grid just keeps showing the last-known
/// (possibly wrong-filter) data. Auto-dismisses on its own: `ItemStore.loadError` is reset
/// to nil at the top of every `load(reset:)`, so the next successful refresh clears it.
struct LibraryErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)
            Text(message)
                .font(StashType.meta())
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Retry", action: retry)
                .buttonStyle(.plain)
                .font(StashType.bodySemibold(12))
                .accessibilityIdentifier("library.errorBanner.retry")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        // .orange has no DESIGN.md token yet.
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityIdentifier("library.errorBanner")
    }
}
