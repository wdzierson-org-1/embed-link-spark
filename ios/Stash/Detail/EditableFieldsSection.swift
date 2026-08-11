import SwiftUI

/// Mirrors the web's `saveStatus` (`idle | saving | saved`, `useEditItemSave.ts`), driving the
/// caption under the title field. `.idle` renders nothing — same as the web leaving the
/// indicator blank before the first edit of a session.
enum SaveStatus {
    case idle, saving, saved
}

/// The detail sheet's editable title + description, with a save-status caption under the title.
/// This view owns no save logic itself — `ItemDetailView` supplies bindings whose setters
/// schedule the debounced autosave (see `ItemDetailView.titleBinding`/`descriptionBinding`), so
/// this stays pure text-entry chrome.
struct EditableFieldsSection: View {
    @Binding var title: String
    @Binding var description: String
    let saveStatus: SaveStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Untitled", text: $title)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("detail.title")
            statusCaption
            TextField("Add a description…", text: $description, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("detail.description")
        }
    }

    @ViewBuilder private var statusCaption: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving…")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("detail.saveStatus")
        case .saved:
            Text("Saved")
                .font(.caption2)
                .foregroundStyle(.green)
                .accessibilityIdentifier("detail.saveStatus")
        }
    }
}
