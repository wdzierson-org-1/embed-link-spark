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
/// (see `ItemDetailView.titleBinding`/`descriptionBinding`). No `ItemEditor`/network awareness
/// lives here. Restyled (Task 6) onto `StashType`/`StashColor` tokens — behavior/identifiers
/// unchanged.
///
/// Only the LOCATION this row produces is ever saved (final wave B): `ItemDetailView` writes it
/// onto the server's current attributes (`ItemEditor.saveLocation`, read in the item's write
/// slot), never this sheet's copy of the blob — production writes other attributes keys
/// asynchronously (the transcription job's `media.transcript`, enrichment's `enrichment.*`), and a
/// whole-blob write of a copy read when the sheet opened would roll them back.
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

    /// Plan 16: an inline action — `inlineButton` (Medium 15, never smaller), `muted` (the old
    /// 70 % `muted` was 2.9:1), with a 44 pt target (`.stashPlain`).
    private var addButton: some View {
        Button(action: startEditing) {
            HStack(spacing: 4) {
                StashMapPin().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16).accessibilityHidden(true)
                Text("Add a location")
            }
            .stashFont(.inlineButton)
            .foregroundStyle(StashColor.muted)
        }
        .buttonStyle(.stashPlain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add a location")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("detail.location.add")
    }

    /// Plan 16: the location reads as a fact (`meta`, like the drawer's other values) and edits on
    /// a tap; the label and the × each take a 44 pt target (`.stashPlain`). They sit 16 pt apart
    /// (was 6) so the ×'s target — 22 pt either side of its centre — ends where the label's
    /// starts: a tap on the end of the label never removes the location.
    private func populatedRow(_ location: CapturedLocation) -> some View {
        HStack(spacing: 16) {
            Button(action: startEditing) {
                HStack(spacing: 4) {
                    StashMapPin().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16).accessibilityHidden(true)
                    Text("posted from \(location.label)")
                }
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
            }
            .buttonStyle(.stashPlain)
            // Same shape as Task 6's `pinPreview` fix (`LocationCapture`/`CaptureComposerView`):
            // an icon+text `HStack` sharing one identifier can expose BOTH children as separate
            // "Multiple matching elements found" hits instead of one combined element — collapse
            // to a single element with an explicit label up front rather than discovering the bug
            // live.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("posted from \(location.label)")
            .accessibilityHint("Edits the location")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("detail.location.label")

            Button {
                commit("")
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
            }
            .buttonStyle(.stashPlain)
            .stashIconControl("Remove location", systemImage: "xmark.circle.fill")
            .accessibilityIdentifier("detail.location.remove")
        }
    }

    /// Plan 16 (2b review N-4): the field types at the supporting size (`secondary`, 15) — an input
    /// a person types into reads at more than the 13 pt fact it edits — its pin a size with it.
    private var editingField: some View {
        HStack(spacing: 6) {
            StashMapPin().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16).accessibilityHidden(true)
                .stashFont(.secondary)
                .foregroundStyle(StashColor.muted)
                .accessibilityHidden(true)
            TextField("Location", text: $draft,
                      prompt: Text("e.g. Brooklyn, New York").foregroundStyle(StashColor.muted))
                .stashFont(.secondary)
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
