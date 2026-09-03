import SwiftUI

/// Shared full-bleed pane for the grid's empty and load-error states.
struct LibraryStatePane: View {
    let systemImage: String
    let title: String
    let message: String
    let identifier: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(StashType.bodySemibold())
            Text(message)
                .font(StashType.body())
                .foregroundStyle(StashColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }
}
