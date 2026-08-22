import SwiftUI
import StashKit

/// Detail-sheet location row (Task 8), port of the web's `EditItemLocationSection.tsx`: shows
/// `attributes.location` when present (`posted from {label}` + a remove X), a ghost "Add a
/// location" button when absent, and edits it inline (autofocused field, Enter/blur commits,
/// Escape cancels — hardware-keyboard only, see `editingField`; XCUITest's `typeText` does
/// synthesize hardware key events against the simulator, so this IS exercisable by a UI test even
/// though nothing in this plan currently asserts on it). All actual read-modify-write logic is
/// StashKit's pure `locationEditCommit`/`buildManualLocation` (`LocationBuild.swift`) — this view
/// only owns the transient `isEditing`/`draft` UI state and writes the result through
/// `attributes`, exactly the same "the binding's setter — owned by `ItemDetailView` — schedules
/// the actual save; the field itself stays pure chrome" shape `title`/`description` already use
/// (see `EditableFieldsSection`'s own doc comment). No `ItemEditor`/network awareness lives here.
///
/// Read-modify-write concurrency caveat (matches the web's own "sheet's item prop freezes while
/// open" comment on `EditItemLocationSection.tsx`): `attributes` is a live `Binding` onto
/// `ItemDetailView`'s `item.attributes`, so a commit here always reads-modifies-writes whatever
/// this sheet's CURRENT (freshest-adopted, per `adopt(_:)`/`hasUnsavedLocation`) attributes blob
/// is — arguably fresher than the web's own frozen-at-open-time snapshot. The same class of race
/// remains possible in principle: if some other attributes-writing flow's save completed between
/// this row's last render and the moment the user's edit commits, that write could still be
/// clobbered by this row's read-modify-write of a blob that (rarely) predates it by a beat. No
/// second attributes-writing flow exists in this build today (Task 8's Attachments section is
/// read-only), so this is a latent, not actual, risk — noted for whoever adds the next one.
struct LocationRow: View {
    @Binding var attributes: ItemAttributes

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    /// What `.onChange(of: isFocused)` should do once focus is actually lost — the single place
    /// that decides commit vs. cancel, so Enter/Escape/a genuine tap-away blur all funnel through
    /// one code path instead of each racing to flip `isEditing` themselves (see body doc comment).
    @State private var pendingExit: ExitReason = .commit

    private enum ExitReason { case commit, cancel }

    private var location: CapturedLocation? { attributes.location }

    var body: some View {
        Group {
            if isEditing {
                editingField
            } else if let location {
                populatedRow(location)
            } else {
                addButton
            }
        }
    }

    private var addButton: some View {
        Button(action: startEditing) {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                Text("Add a location")
            }
            .font(.caption)
        }
        .foregroundStyle(Color.secondary.opacity(0.7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add a location")
        .accessibilityIdentifier("detail.location.add")
    }

    private func populatedRow(_ location: CapturedLocation) -> some View {
        HStack(spacing: 6) {
            Button(action: startEditing) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("posted from \(location.label)")
                }
                .font(.caption)
            }
            .foregroundStyle(.secondary)
            // Same shape as Task 6's `pinPreview` fix (`LocationCapture`/`CaptureComposerView`):
            // an icon+text `HStack` sharing one identifier can expose BOTH children as separate
            // "Multiple matching elements found" hits instead of one combined element — collapse
            // to a single element with an explicit label up front rather than discovering the bug
            // live.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("posted from \(location.label)")
            .accessibilityIdentifier("detail.location.label")

            Button {
                commit("")
            } label: {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove location")
            .accessibilityIdentifier("detail.location.remove")
        }
    }

    private var editingField: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("e.g. Brooklyn, New York", text: $draft)
                .font(.caption)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    pendingExit = .commit
                    isFocused = false
                }
                .onKeyPress(.escape) {
                    pendingExit = .cancel
                    isFocused = false
                    return .handled
                }
                .accessibilityIdentifier("detail.location.field")
        }
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            switch pendingExit {
            case .commit: commit(draft)
            case .cancel: isEditing = false
            }
            pendingExit = .commit   // reset the default for the next time this row is opened
        }
    }

    private func startEditing() {
        draft = location?.label ?? ""
        isEditing = true
    }

    private func commit(_ rawValue: String) {
        isEditing = false
        guard let next = locationEditCommit(current: attributes, rawValue: rawValue) else { return }
        attributes = next
    }
}

#Preview("Add a location") {
    LocationRow(attributes: .constant(ItemAttributes()))
        .padding()
}

#Preview("Posted from") {
    LocationRow(attributes: .constant(ItemAttributes(
        location: CapturedLocation(label: "Brooklyn, New York", source: "manual"))))
        .padding()
}
