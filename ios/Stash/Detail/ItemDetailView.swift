import SwiftUI
import StashKit

/// Mirrors the web's `saveStatus` (`idle | saving | saved`, `useEditItemSave.ts`), driving
/// `detail.autosave`'s caption. Per this task's brief, only `.saving` gets its own copy
/// ("Saving…") — `.idle`/`.saved` both render the web's resting-state copy, "Changes saved
/// automatically" (`EditItemAutoSaveIndicator.tsx`'s own `default:` case).
enum SaveStatus {
    case idle, saving, saved
}

/// Detail sheet presented from a Library card tap, rebuilt to DESIGN.md's detail-panel anatomy
/// (`§Components`, "Detail panel"): one scrolling flow surface — eyebrow (`DetailEyebrow`) →
/// inline-editable title/description → contained media → URL bar (`DetailURLBar`, link items) →
/// content tabs (`ItemDetailContent`) → Details drawer (`DetailsDrawer`, which also owns the
/// editable location row as its own "Location" fact — Fix round 1, review finding #1: the web
/// only ever mounts the location editor inside this drawer, never a second time near the top, so
/// the standalone `LocationRow` call that used to live here was removed rather than duplicating
/// the fact) → Sharing (`SharingSection`) → a pinned footer bar (delete left, autosave right).
/// Tags UI is retired (`DESIGN.md` — "No tag UI on cards or panel"); `tags` data itself is
/// untouched, just no longer surfaced here. On appear, fetches the
/// full row (adding `page_body`, which the grid's list query omits) for types whose tabs need it,
/// then merges it back into `store` so the list stays current too.
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
    @FocusState private var titleFocused: Bool
    @FocusState private var descriptionFocused: Bool
    /// Backs `NotesEditor`'s `TextEditor` (Plan 8 Task 5) — declared here, not inside `NotesEditor`
    /// itself, and threaded down through `ItemDetailContent` as a `FocusState<Bool>.Binding`: a
    /// `.toolbar(placement: .keyboard)` attached several levels deep inside this sheet's
    /// `ScrollView`/`ItemDetailContent`'s tab-switch `@ViewBuilder` never actually registered its
    /// accessory (confirmed live — `detail.dismissKeyboard` never appeared, even right after
    /// focusing). Hoisting both the `@FocusState` and the `.toolbar` itself up to this view's own
    /// top level (same depth `titleFocused`/`descriptionFocused` already live at) — see `body`'s
    /// own `NavigationStack` wrap below — fixed it.
    @FocusState private var notesFocused: Bool

    init(item: Item, store: ItemStore) {
        _item = State(initialValue: item)
        _snapshot = State(initialValue: item)
        self.store = store
        _selectedTab = State(initialValue: contentTabsConfig(for: item.type).defaultTab)
    }

    var body: some View {
        // `NavigationStack` wrap (Plan 8 Task 5, no navigation chrome of its own — hidden via
        // `.toolbar(.hidden, for: .navigationBar)` below, since this sheet already has its own
        // custom `closeButton`, not a system back/close bar item): required for
        // `.toolbar(placement: .keyboard)` to actually register an accessory at all inside a
        // `.sheet(item:)` presentation — confirmed live, moving the toolbar to this view's own
        // top level (this file's prior state, no `NavigationStack`) was NOT sufficient on its own;
        // `CaptureComposerView`'s identical-looking `.toolbar(placement: .keyboard)` works without
        // one only because it's a plain `TabView` tab, never presented modally.
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                // `footerBar` is a genuine VStack SIBLING below the ScrollView, not a
                // `.safeAreaInset`/overlay pinned on top of it. An inset never actually shrinks the
                // ScrollView's own laid-out frame — it only nudges the CONTENT's scroll offset
                // limits — so the ScrollView's outer frame (what XCUITest and any other hit-testing
                // consults to decide "is this element already on screen") still nominally extends
                // the full sheet height, footer included; short content (e.g. Details/Sharing on an
                // item with little else) then rests visually under the pinned footer even though
                // its element is reported "within bounds". A true sibling makes the ScrollView's
                // frame stop exactly where the footer begins, so nothing can ever land behind it.
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            DetailEyebrow(item: item)
                            titleField
                            descriptionField
                            if item.type == .image, let url = item.thumbnailURL {
                                heroImage(url)
                            }
                            if item.type == .link, let urlString = item.url, !urlString.isEmpty {
                                DetailURLBar(urlString: urlString)
                            }
                            ItemDetailContent(item: item, selectedTab: $selectedTab, isLoadingDetail: isLoadingDetail,
                                              editor: editor, saveStatus: $saveStatus, notesFocused: $notesFocused,
                                              onSaved: handleSaved)

                            hairline

                            DetailsDrawer(item: item, attributes: attributesBinding)

                            SharingSection(item: item, editor: editor,
                                            supplementalNote: supplementalNoteBinding, onSaved: handleSaved)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 44)
                        .padding(.bottom, 24)
                    }
                    footerBar
                }
                .background(StashColor.paper.ignoresSafeArea())

                closeButton
            }
            .presentationCornerRadius(StashRadius.sheet)
            // `NotesEditor`'s keyboard-minimize accessory (same control Task 3 gave the capture
            // composer) — see `notesFocused`'s doc comment above for why this lives here, at the
            // top level, rather than on `NotesEditor` itself.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        notesFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityIdentifier("detail.dismissKeyboard")
                    .accessibilityLabel("Hide keyboard")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
    }

    // MARK: - Flow surface pieces

    /// Object title (panel) per DESIGN.md: 500 · 28 / 1.2 · −0.02em, inline-editable — "no input
    /// chrome at rest; violet wash on hover; wash + ring on focus." Touch has no hover, so the
    /// wash/ring both key off `titleFocused` here.
    private var titleField: some View {
        // Deliberately single-line (no `axis: .vertical`) — a vertical-axis `TextField` renders
        // as a `UITextView` under the hood, which `testEditSmoke`'s tap-then-`typeText` helper
        // (`clearField`/`replaceText`) proved live doesn't reliably gain keyboard focus from a
        // plain `.tap()` the way a single-line `UITextField` does ("Neither element nor any
        // descendant has keyboard focus" — confirmed against this exact wrapper). A long title
        // scrolls horizontally rather than wrapping to a second line; acceptable given the test
        // contract this field must keep working under.
        TextField("Untitled", text: titleBinding)
            .font(StashType.panelTitle())
            .stashTracking(-0.02, size: 28)
            .foregroundStyle(StashColor.ink)
            .textFieldStyle(.plain)
            .focused($titleFocused)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(titleFocused ? StashColor.violet300.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    .strokeBorder(titleFocused ? StashColor.violet300 : Color.clear, lineWidth: 2)
            )
            .accessibilityIdentifier("detail.title")
    }

    private var descriptionField: some View {
        TextField("Add a description…", text: descriptionBinding, axis: .vertical)
            .font(StashType.body())
            .foregroundStyle(StashColor.muted)
            .textFieldStyle(.plain)
            .focused($descriptionFocused)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(descriptionFocused ? StashColor.violet300.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    .strokeBorder(descriptionFocused ? StashColor.violet300 : Color.clear, lineWidth: 2)
            )
            .accessibilityIdentifier("detail.description")
    }

    /// Contained hero, radius 16 + card shadow — image items only (video/audio players are out of
    /// scope for this task; "as today" per the brief, and today there are none).
    private func heroImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(.tertiarySystemFill).aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 384)
        .clipShape(RoundedRectangle(cornerRadius: StashRadius.card, style: .continuous))
        .stashCardShadow()
        .accessibilityIdentifier("detail.heroImage")
    }

    private var hairline: some View {
        Rectangle().fill(StashColor.hairline).frame(height: 1)
    }

    /// The iOS close affordance — a hairline circle × top-trailing, matching the web sheet's own
    /// close button, in place of the former toolbar "Done".
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StashColor.muted)
                .frame(width: 28, height: 28)
                .background(StashColor.paper, in: Circle())
                .overlay(Circle().strokeBorder(StashColor.hairline, lineWidth: 1))
        }
        .padding(14)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("detail.done")
    }

    /// Pinned footer bar (hairline top): "Delete item" left, autosave status right — port of
    /// `EditItemSheet.tsx`'s footer.
    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                deleteButton
                Spacer()
                autosaveLabel
            }
            if let deleteErrorMessage {
                Text(deleteErrorMessage)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("detail.deleteError")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(StashColor.paper)
        .overlay(alignment: .top) { hairline }
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            if isDeleting {
                ProgressView()
            } else {
                Label("Delete item", systemImage: "trash")
                    .font(StashType.meta())
            }
        }
        .foregroundStyle(StashColor.destructive)
        .disabled(isDeleting)
        .accessibilityIdentifier("detail.delete")
    }

    @ViewBuilder private var autosaveLabel: some View {
        Text(saveStatus == .saving ? "Saving…" : "Changes saved automatically")
            .font(StashType.meta())
            .foregroundStyle(StashColor.faint)
            .accessibilityIdentifier("detail.autosave")
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

    /// Sticky-note text (Task 9's `SharingSection`) rides the same debounced field-autosave
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
