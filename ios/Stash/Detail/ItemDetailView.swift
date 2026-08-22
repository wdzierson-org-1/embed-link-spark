import SwiftUI
import StashKit

/// Detail sheet presented from a Library card tap: optional hero image (image items only), an
/// editable header (title/description autosave — Task 8), an "Open Link" button for link items,
/// the segmented content section, a notes-append composer, a tags manager and public/private
/// toggle with its sticky-note lifecycle (Task 9), and delete. On appear, fetches the full row
/// (adding `page_body`, which the grid's list query omits) for types whose tabs need it, then
/// merges it back into `store` so the list stays current too.
struct ItemDetailView: View {
    @State private var item: Item
    /// The last row we know is confirmed saved — either from the initial load, our own most
    /// recent successful save, or an observed server update with no local edit in flight. This
    /// is the diff baseline `changedFields` compares the live draft against; see `adopt(_:)`.
    @State private var snapshot: Item
    @State private var saveStatus: SaveStatus = .idle
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleted = false

    // One editor (and its EmbeddingRefresher's per-item debounce state) per detail sheet, per
    // the plan's interface contract. Declared @State, not a plain `let`: this View struct's
    // `init` re-runs on every re-render of the presenting view (e.g. whenever `store.items`
    // changes for ANY item while this sheet is open, since LibraryView's body — and hence the
    // `.sheet(item:)` content closure — re-evaluates). A plain stored property would be silently
    // reconstructed on every such pass, losing in-flight debounce state; @State's storage is
    // preserved across re-renders for the lifetime of this view's identity. Same reasoning
    // applies to `fieldDebouncer`.
    @State private var editor = ItemEditor(patcher: SupabaseItemPatcher(),
                                            refresher: EmbeddingRefresher(syncer: SupabaseEmbeddingSyncer()))
    @State private var fieldDebouncer = Debouncer(interval: .milliseconds(400))

    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ContentTabKey
    @State private var isLoadingDetail = false

    init(item: Item, store: ItemStore) {
        _item = State(initialValue: item)
        _snapshot = State(initialValue: item)
        self.store = store
        _selectedTab = State(initialValue: contentTabsConfig(for: item.type).defaultTab)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if item.type == .image, let url = item.thumbnailURL {
                        heroImage(url)
                    }
                    ItemDetailHeader(item: item, title: titleBinding, description: descriptionBinding,
                                      attributes: attributesBinding, saveStatus: saveStatus)
                    if item.type == .link, let urlString = item.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Open Link", systemImage: "arrow.up.right.square")
                        }
                        .accessibilityIdentifier("detail.openLink")
                    }
                    ItemDetailContent(item: item, selectedTab: $selectedTab, isLoadingDetail: isLoadingDetail)
                    // Gated to the Notes tab (rather than always-visible below every tab) so it
                    // reads as "here's how you add to what you're looking at" instead of a
                    // floating control under unrelated Summary/Original/Transcript content.
                    if selectedTab == .notes {
                        NotesAppendComposer(item: item, editor: editor, onSaved: handleSaved)
                    }
                    Divider()
                    ItemTagsSection(item: item, editor: editor)
                    Divider()
                    PublicToggleSection(item: item, editor: editor,
                                         supplementalNote: supplementalNoteBinding, onSaved: handleSaved)
                    deleteSection
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("detail.done")
                }
            }
        }
        .task { await loadDetailIfNeeded() }
        .onChange(of: store.items) { _, items in
            guard let updated = items.first(where: { $0.id == item.id }) else { return }
            adopt(updated)
        }
        .onDisappear {
            // Deleting already dismisses (and there's nothing left server-side to PATCH).
            guard !isDeleted else { return }
            Task { await saveChangedFields() }
        }
        .confirmationDialog("Delete this item? This can't be undone.", isPresented: $showDeleteConfirm,
                             titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func heroImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(.tertiarySystemFill).aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("detail.heroImage")
    }

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                if isDeleting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Delete Item", systemImage: "trash").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isDeleting)
            .accessibilityIdentifier("detail.delete")
            if let deleteErrorMessage {
                Text(deleteErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("detail.deleteError")
            }
        }
    }

    // MARK: - Field bindings (title/description autosave)

    private var titleBinding: Binding<String> {
        Binding(get: { item.title ?? "" }, set: { newValue in
            item.title = newValue
            scheduleFieldSave()
        })
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { item.description ?? "" }, set: { newValue in
            item.description = newValue
            scheduleFieldSave()
        })
    }

    /// Sticky-note text (Task 9's `PublicToggleSection`) rides the same debounced field-autosave
    /// path as title/description — `saveChangedFields` already diffs `supplementalNote` against
    /// `snapshot` (wired in Task 8, unused until now since nothing mutated it before this task).
    private var supplementalNoteBinding: Binding<String> {
        Binding(get: { item.supplementalNote ?? "" }, set: { newValue in
            item.supplementalNote = newValue
            scheduleFieldSave()
        })
    }

    /// Backs `LocationRow` (Task 8). Unlike title/description/supplementalNote, a location commit
    /// is already a discrete, deliberate action (Enter/blur/remove-X — never per-keystroke), so
    /// this saves immediately rather than routing through `fieldDebouncer`: there's no
    /// "in-progress draft" worth debouncing here, same reasoning `NotesAppendComposer`'s own doc
    /// comment gives for its own atomic save. The optimistic `item.attributes = newValue` write
    /// (before the save's own await resolves) is exactly what `adopt(_:)`'s `hasUnsavedLocation`
    /// flag protects from a racing realtime refresh — see `mergePreservingDetail`'s doc comment.
    private var attributesBinding: Binding<ItemAttributes> {
        Binding(get: { item.attributes }, set: { newValue in
            item.attributes = newValue
            Task { await saveAttributes(newValue) }
        })
    }

    private func scheduleFieldSave() {
        Task { await fieldDebouncer.call { await saveChangedFields() } }
    }

    // MARK: - Save / delete

    /// The debounced field-autosave action (fires 400ms after the last keystroke, per field
    /// binding above) AND the final save on sheet dismiss (`.onDisappear`) both call this
    /// directly — it's naturally idempotent (an empty diff against `snapshot` is a no-op), so
    /// there's no need to cancel one path when the other fires; whichever runs second just finds
    /// nothing left to save.
    ///
    /// Marked @MainActor deliberately (unlike this view's other private methods): this is the
    /// one call path reached through `Debouncer`, which is its own (non-Main) actor — its
    /// internal `Task` inherits *that* actor's isolation, not whatever actor originally scheduled
    /// the call. Without this annotation, the @State mutations below could run off the main
    /// thread. Every other async entry point here (`performDelete`, `NotesAppendComposer.append`)
    /// is reached directly from a SwiftUI event closure (Button action / onDisappear), which is
    /// already MainActor-isolated with no intervening actor hop.
    @MainActor
    private func saveChangedFields() async {
        let titleNow = item.title ?? ""
        let descriptionNow = item.description ?? ""
        let patch = changedFields(from: snapshot, title: titleNow, description: descriptionNow,
                                   supplementalNote: item.supplementalNote ?? "")
        guard !patch.isEmpty else { return }
        saveStatus = .saving
        do {
            let merged = try await editor.save(itemId: item.id, patch: patch)
            handleSaved(merged)
            saveStatus = .saved
        } catch {
            saveStatus = .idle
        }
    }

    /// `LocationRow`'s save path (via `attributesBinding` above): an attributes-only `ItemPatch`
    /// is never `.isEmpty` (so `editor.save` never throws `.emptyPatch` here), and never schedules
    /// an embedding refresh (`ItemPatch.touchesTextFields` deliberately excludes `attributes` —
    /// web parity, `itemOperations.ts:100-101`). No dedicated error UI on failure, matching the
    /// web's own fire-and-forget `catch { console.error(...) }` in `EditItemLocationSection.tsx`:
    /// a failed save just means the next realtime/detail refresh's `adopt` shows whatever the
    /// server actually has, rather than the optimistic local edit silently drifting from it.
    @MainActor
    private func saveAttributes(_ attributes: ItemAttributes) async {
        do {
            let merged = try await editor.save(itemId: item.id, patch: ItemPatch(attributes: attributes))
            handleSaved(merged)
        } catch {
            print("Location save failed (non-fatal): \(error)")
        }
    }

    /// Shared by every successful `editor.save` call site (field autosave, notes append): folds
    /// the merged server row into local state and keeps the background grid in sync so it
    /// doesn't wait on the next realtime broadcast to reflect the edit.
    private func handleSaved(_ merged: Item) {
        adopt(merged)
        store.applyDetail(merged)
    }

    /// Detail-sheet realtime hygiene: `store.items` (and our own save responses) can bring a
    /// fresher row for this item at any time — an enrichment pipeline finishing, another
    /// device's edit, or our own PATCH echoing back. The actual merge is StashKit's
    /// `mergePreservingDetail` (finding #2, final review — see its doc comment for the full
    /// rationale, including why `pageBody` needs its own guard against list-row refreshes
    /// nulling an already-loaded value): `title`/`description`/`supplementalNote`/`attributes`
    /// (the last added by Task 8's `LocationRow`, alongside Task 9's sticky-note field) are the
    /// fields under active local editing in this build, so we compute "is there an unsaved edit
    /// in flight" for each — has it already diverged from `snapshot`, our last confirmed-saved
    /// baseline? — and hand those four flags in. `snapshot` itself always advances to `incoming`
    /// here, since its only job is being the next diff baseline for `changedFields`.
    private func adopt(_ incoming: Item) {
        let next = mergePreservingDetail(
            local: item,
            incoming: incoming,
            hasUnsavedTitle: (item.title ?? "") != (snapshot.title ?? ""),
            hasUnsavedDescription: (item.description ?? "") != (snapshot.description ?? ""),
            hasUnsavedSupplementalNote: (item.supplementalNote ?? "") != (snapshot.supplementalNote ?? ""),
            hasUnsavedLocation: item.attributes != snapshot.attributes
        )
        snapshot = incoming
        item = next
    }

    @MainActor
    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        deleteErrorMessage = nil
        do {
            try await editor.delete(itemId: item.id)
            isDeleted = true
            dismiss()
            // Fire-and-forget, matching the save paths' "closing never waits on the network"
            // ethos — the grid will drop the row itself once this resolves (and, redundantly,
            // via the realtime subscription's own broadcast of the delete).
            Task { await store.refresh() }
        } catch {
            deleteErrorMessage = "Couldn't delete — try again."
        }
    }

    /// list queries omit page_body (can be tens of KB/item); fetch the full row here instead.
    private func loadDetailIfNeeded() async {
        guard needsSourceContent(item.type) else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        if let detail = try? await SupabaseItemsFetcher().fetchDetail(id: item.id) {
            adopt(detail)
            store.applyDetail(detail)
        }
    }
}
