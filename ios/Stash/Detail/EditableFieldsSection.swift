import SwiftUI
import StashKit

/// Mirrors the web's `saveStatus` (`idle | saving | saved`, `useEditItemSave.ts`), driving the
/// caption under the title field. `.idle` renders nothing — same as the web leaving the
/// indicator blank before the first edit of a session.
enum SaveStatus {
    case idle, saving, saved
}

/// The detail sheet's editable title + description + location row, with a save-status caption
/// under the title. This view owns no save logic itself — `ItemDetailView` supplies bindings
/// whose setters schedule the actual save (see `ItemDetailView.titleBinding`/`descriptionBinding`
/// for the debounced text-field path, `attributesBinding` for the location row's immediate one),
/// so this stays pure text-entry-adjacent chrome; `LocationRow` (Task 8) itself follows the same
/// rule (see its own doc comment).
struct EditableFieldsSection: View {
    @Binding var title: String
    @Binding var description: String
    @Binding var attributes: ItemAttributes
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
                .foregroundStyle(StashColor.muted)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("detail.description")
            LocationRow(attributes: $attributes)
        }
    }

    @ViewBuilder private var statusCaption: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            Text("Saving…")
                .font(.caption2)
                .foregroundStyle(StashColor.muted)
                .accessibilityIdentifier("detail.saveStatus")
        case .saved:
            Text("Saved")
                .font(.caption2)
                .foregroundStyle(.green)
                .accessibilityIdentifier("detail.saveStatus")
        }
    }
}
