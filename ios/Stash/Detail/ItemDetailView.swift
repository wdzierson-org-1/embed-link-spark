import SwiftUI
import StashKit

/// Mirrors the web's `saveStatus` (`idle | saving | saved`, `useEditItemSave.ts`), driving
/// `detail.autosave`'s caption. Per this task's brief, only `.saving` gets its own copy
/// ("Saving…") — `.idle`/`.saved` both render the web's resting-state copy, "Changes saved
/// automatically".
///
/// `.failed(String)` (final wave, item D — DISCLOSED extension beyond web parity: the web has no
/// equivalent inline error state here either): every save catch site used to fall back to `.idle`,
/// which rendered the exact same resting "Changes saved automatically" caption a genuine success
/// does — a failed save was silently indistinguishable from one that worked. `.failed` renders
/// `detail.autosave.error` in `StashColor.destructive` instead; the unsaved draft (title/
/// description/notes text — whichever field failed) is always left exactly as typed either way, so
/// nothing is lost, and the NEXT successful save on any field clears it back to `.saved`. Applied
/// to every save site here (field autosave, notes, attributes-on-success) for consistency, not just
/// the notes path this fix round's brief called out by line number.
enum SaveStatus: Equatable {
    case idle, saving, saved
    case failed(String)
}

/// The sheet's three focusable text inputs (final wave, item B) — one shared `@FocusState` rather
/// than three independent `Bool`s, specifically so the keyboard accessory's "hide keyboard" button
/// can defocus WHICHEVER of the three is currently active. Previously that button hardcoded
/// `notesFocused = false`, so it was a dead tap unless notes specifically had focus (confirmed
/// live: tapping it while title/description was focused left the keyboard up). `NotesEditor`
/// itself binds into this same enum via `equals: .notes`, not a private `Bool` of its own — see
/// its own doc comment for why a `FocusState<DetailField?>.Binding` has to be threaded all the way
/// down for that to work.
enum DetailField: Hashable {
    case title, description, notes
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
    /// Notes' own draft/debounce state (Plan 8 Task 5, hoisted out in fix round 1 — see
    /// `NotesEditorModel`'s own doc comment) — same one-per-sheet lifetime as `editor` above, built
    /// once in `init` from the item's initial content.
    @State private var notesModel: NotesEditorModel
    /// Guards the field-autosave (400ms) vs. notes-autosave (600ms) race (fix round 1, review
    /// finding #2): two independent debounced save paths can have their responses land out of
    /// dispatch order, and without this, an older response landing last could revert whatever a
    /// newer one already committed — see `SaveGeneration`'s own doc comment (StashKit) for the
    /// full rationale and the established codebase precedent it mirrors.
    @State private var saveGeneration = SaveGeneration()

    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ContentTabKey
    @State private var isLoadingDetail = false
    /// One shared enum-keyed `@FocusState` for all three text inputs (final wave, item B — was
    /// three independent `Bool`s, `titleFocused`/`descriptionFocused`/`notesFocused`; see
    /// `DetailField`'s own doc comment for why unifying them was the fix). Declared here, not
    /// inside `NotesEditor` itself, and threaded down through `ItemDetailContent` as a
    /// `FocusState<DetailField?>.Binding`: a `.toolbar(placement: .keyboard)` attached several
    /// levels deep inside this sheet's `ScrollView`/`ItemDetailContent`'s tab-switch
    /// `@ViewBuilder` never actually registered its accessory (confirmed live —
    /// `detail.dismissKeyboard` never appeared, even right after focusing). Hoisting both the
    /// `@FocusState` and the `.toolbar` itself up to this view's own top level — see `body`'s own
    /// `NavigationStack` wrap below — fixed it.
    @FocusState private var focusedField: DetailField?

    init(item: Item, store: ItemStore) {
        _item = State(initialValue: item)
        _snapshot = State(initialValue: item)
        self.store = store
        _selectedTab = State(initialValue: contentTabsConfig(for: item.type).defaultTab)
        _notesModel = State(initialValue: NotesEditorModel(item: item))
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
                        // Outer spacing 0 (was 18 — a value that belonged to neither this fix
                        // round's `DetailLayout.gap`(14)/`.section`(24) tier): every child below
                        // now carries its own explicit top gap instead, so the sheet's rhythm
                        // reads as one deliberate 14/24 scale rather than a flat 18 throughout.
                        // `ItemDetailContent`/`DetailsDrawer`/`SharingSection` need none here —
                        // each opens with a `SectionHeader`, which already supplies its own
                        // `DetailLayout.section` gap above itself.
                        VStack(alignment: .leading, spacing: 0) {
                            DetailEyebrow(item: item)
                            titleField
                                .padding(.top, DetailLayout.gap)
                            descriptionField
                                .padding(.top, DetailLayout.gap)
                            if item.type == .image, let url = item.thumbnailURL {
                                heroImage(url)
                                    .padding(.top, DetailLayout.gap)
                            }
                            if item.type == .link, let urlString = item.url, !urlString.isEmpty {
                                DetailURLBar(urlString: urlString)
                                    .padding(.top, DetailLayout.gap)
                            }
                            ItemDetailContent(item: item, selectedTab: $selectedTab, isLoadingDetail: isLoadingDetail,
                                              notesModel: notesModel, notesFocused: $focusedField,
                                              scheduleNotesFlush: scheduleNotesFlush, flushNotesNow: flushNotesNow)

                            // No standalone divider here anymore — `DetailsDrawer`'s own
                            // `SectionHeader` ("DETAILS") already draws the hairline that used to
                            // live on this ad-hoc `Rectangle`, right above its own label at the
                            // same `DetailLayout.section` gap every other section uses.
                            DetailsDrawer(item: item, attributes: attributesBinding)

                            SharingSection(item: item, editor: editor,
                                            supplementalNote: supplementalNoteBinding, onSaved: handleSaved)
                        }
                        .padding(.horizontal, DetailLayout.inset)
                        .padding(.top, 44)
                        .padding(.bottom, 24)
                    }
                    footerBar
                }
                .background(StashColor.paper.ignoresSafeArea())

                closeButton
            }
            .presentationCornerRadius(StashRadius.sheet)
            // Keyboard-minimize accessory (same control Task 3 gave the capture composer) — see
            // `focusedField`'s doc comment above for why this lives here, at the top level, rather
            // than on any one field's own view. `focusedField = nil` (final wave, item B — was
            // hardcoded to only clear notes' own focus) defocuses whichever of title/description/
            // notes is currently active, so this button actually works no matter which field the
            // keyboard is up for.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
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
                // Belt-and-braces (fix round 1, review finding #1): `closeButton` already flushes
                // notes before calling `dismiss()`, but `onDisappear` fires on ANY path out of this
                // sheet (a system swipe-to-dismiss, not just the Done button), so notes gets the
                // same explicit flush here too — same reasoning `saveChangedFields()` already
                // covers fields with. `flushNotesNow` first: it's the one path that's new/hasn't
                // already run once via `closeButton` in the tap-Done case (redundant-but-safe there
                // — `NotesEditorModel`'s own guard makes a second flush with nothing new to save a
                // no-op).
                //
                // `fieldDebouncer.cancel()` before the explicit `saveChangedFields()` (final wave,
                // item E/7): without this, a still-pending 400ms field debounce from a keystroke
                // typed just before dismiss could fire its OWN `saveChangedFields()` call after
                // this one already ran — harmless in outcome (both diff against `snapshot`, so a
                // second call with nothing left unsaved is a no-op), but it's a redundant network
                // round trip and an unnecessary `saveGeneration` bump for no reason once this
                // explicit call is about to cover the same save anyway.
                Task {
                    await flushNotesNow()
                    await fieldDebouncer.cancel()
                    await saveChangedFields()
                }
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
    /// wash/ring both key off `focusedField == .title` here.
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
            .focused($focusedField, equals: .title)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(focusedField == .title ? StashColor.violet300.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    // 1pt (was 2pt) — matches every other hairline/focus stroke on the sheet.
                    .strokeBorder(focusedField == .title ? StashColor.violet300 : Color.clear, lineWidth: 1)
            )
            .accessibilityIdentifier("detail.title")
            // Final wave: the 6pt horizontal padding above exists to grow the tap/focus target,
            // not to push the TEXT off `DetailLayout.inset` — negating it here shifts the whole
            // padded+background+overlay assembly left by 6pt so the glyph's own left edge lands
            // exactly on `DetailLayout.inset` (20), flush with the eyebrow/URL bar above it,
            // while the hit target itself keeps its full width.
            .padding(.horizontal, -6)
    }

    private var descriptionField: some View {
        TextField("Add a description…", text: descriptionBinding, axis: .vertical)
            .font(StashType.body())
            .foregroundStyle(StashColor.muted)
            // Body line spacing (DESIGN.md "~1.55 at 14pt") — same delta `MarkdownBlocksView`'s
            // paragraphs and the content tabs' plain-text fallback both already use, so the
            // description reads at the same rhythm as the rest of the sheet's body text.
            .lineSpacing(14 * 0.55)
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .description)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(focusedField == .description ? StashColor.violet300.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    // 1pt (was 2pt) — matches every other hairline/focus stroke on the sheet.
                    .strokeBorder(focusedField == .description ? StashColor.violet300 : Color.clear, lineWidth: 1)
            )
            .accessibilityIdentifier("detail.description")
            // Final wave — same compensation as `titleField` above: negate the 6pt hit-padding
            // so the text's left edge lands on `DetailLayout.inset`, not `inset + 6`.
            .padding(.horizontal, -6)
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
    /// close button, in place of the former toolbar "Done". Flushes any pending notes edit BEFORE
    /// dismissing (fix round 1, review finding #1) — the 600ms debounce alone can't be trusted to
    /// have fired yet on a fast "type then tap Done" sequence, so this awaits the flush first
    /// rather than relying solely on `onDisappear`'s own belt-and-braces call.
    private var closeButton: some View {
        Button {
            Task {
                await flushNotesNow()
                dismiss()
            }
        } label: {
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
        .padding(.horizontal, DetailLayout.inset)
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

    /// `.failed` (final wave, item D) renders as its own `detail.autosave.error` identifier in
    /// `StashColor.destructive`, distinct from the resting `detail.autosave` identifier every
    /// other state shares — so a UI test (or VoiceOver user) can tell "saved" and "failed, please
    /// retry" apart without parsing label text.
    @ViewBuilder private var autosaveLabel: some View {
        if case .failed(let message) = saveStatus {
            Text(message)
                .font(StashType.meta())
                .foregroundStyle(StashColor.destructive)
                .accessibilityIdentifier("detail.autosave.error")
        } else {
            Text(saveStatus == .saving ? "Saving…" : "Changes saved automatically")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
                .accessibilityIdentifier("detail.autosave")
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
    /// "in-progress draft" worth debouncing here. The optimistic `item.attributes = newValue`
    /// write (before the save's own await resolves) is exactly what `adopt(_:)`'s
    /// `hasUnsavedLocation` flag protects from a racing realtime refresh — see
    /// `mergePreservingDetail`'s doc comment.
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
    /// thread. Every other async entry point here (`performDelete`, `flushNotes`) is reached
    /// directly from a SwiftUI event closure (Button action / onDisappear) or another already-
    /// `@MainActor` method, so it's already MainActor-isolated with no intervening actor hop.
    ///
    /// `saveGeneration`-guarded (fix round 1, review finding #2): captures its own generation
    /// before dispatching, and only applies the response — `handleSaved`/`saveStatus` alike — if
    /// no NEWER save (this same field debounce firing again, OR a notes autosave) has started in
    /// the meantime. See `SaveGeneration`'s own doc comment (StashKit) for the full race this
    /// guards against.
    @MainActor
    private func saveChangedFields() async {
        let titleNow = item.title ?? ""
        let descriptionNow = item.description ?? ""
        let patch = changedFields(from: snapshot, title: titleNow, description: descriptionNow,
                                   supplementalNote: item.supplementalNote ?? "")
        guard !patch.isEmpty else { return }
        let gen = saveGeneration.next()
        saveStatus = .saving
        do {
            let merged = try await editor.save(itemId: item.id, patch: patch)
            guard saveGeneration.isLatest(gen) else { return }
            handleSaved(merged)
            saveStatus = .saved
        } catch {
            guard saveGeneration.isLatest(gen) else { return }
            // Final wave, item D: was `.idle`, which rendered the same resting "Changes saved
            // automatically" caption a real success does — a failed field save was silently
            // indistinguishable from one that worked. `item.title`/`item.description` are left
            // exactly as typed (nothing here reverts them), so the draft itself is never lost;
            // the next successful save on any field clears this back to `.saved`.
            saveStatus = .failed("Couldn't save — try again.")
        }
    }

    /// `LocationRow`'s save path (via `attributesBinding` above): an attributes-only `ItemPatch`
    /// is never `.isEmpty` (so `editor.save` never throws `.emptyPatch` here), and never schedules
    /// an embedding refresh (`ItemPatch.touchesTextFields` deliberately excludes `attributes` —
    /// web parity, `itemOperations.ts:100-101`). No dedicated error UI on failure, matching the
    /// web's own fire-and-forget `catch { console.error(...) }` in `EditItemLocationSection.tsx`:
    /// a failed save just means the next realtime/detail refresh's `adopt` shows whatever the
    /// server actually has, rather than the optimistic local edit silently drifting from it — that
    /// reasoning is unchanged by final wave item D/minor 5 below, so the catch here deliberately
    /// stays silent rather than also switching to `.failed`.
    /// `saveGeneration`-guarded on success same as every other save site here (fix round 1).
    @MainActor
    private func saveAttributes(_ attributes: ItemAttributes) async {
        let gen = saveGeneration.next()
        do {
            let merged = try await editor.save(itemId: item.id, patch: ItemPatch(attributes: attributes))
            guard saveGeneration.isLatest(gen) else { return }
            handleSaved(merged)
            // Final wave, item E/minor 5: this path never set `saveStatus` at all before, so a
            // location edit right after a `.failed` field/notes save left the destructive caption
            // on screen even though the location save that just ran succeeded. Every other save
            // site here already sets `.saved` on success; this just brings location in line.
            saveStatus = .saved
        } catch {
            print("Location save failed (non-fatal): \(error)")
        }
    }

    /// Debounced (per-keystroke) notes flush trigger, handed to `NotesEditor` via
    /// `ItemDetailContent` — see `NotesEditorModel.scheduleSave`'s own doc comment.
    private func scheduleNotesFlush() {
        notesModel.scheduleSave { await self.flushNotes() }
    }

    /// Explicit, immediate notes flush (fix round 1, review finding #1) — the Done button /
    /// `onDisappear` path, and the blur handler `NotesEditor` itself installs for both modes now.
    /// See `NotesEditorModel.flushNow`'s own doc comment for why this exists at all.
    private func flushNotesNow() async {
        await notesModel.flushNow { await self.flushNotes() }
    }

    /// The actual notes save (Plan 8 Task 5, split out of `NotesEditor` in fix round 1 so
    /// `ItemDetailView` can trigger it directly — see `NotesEditorModel`'s own doc comment for
    /// why): plain notes save the whole draft as-is; rich notes wrap the draft as a new paragraph
    /// via `appendNoteParagraph` onto the CURRENT `item.content` (read live here, not a value
    /// `NotesEditorModel` itself would otherwise have to keep re-synced — this is exactly why the
    /// model doesn't own this method). `saveGeneration`-guarded like every other save site here.
    ///
    /// Idempotence guard (final wave, item C / minor 6) right before the rich-mode append: with
    /// rich appends now firing only on blur/Done/`onDisappear` (never per-keystroke — see
    /// `NotesEditor`'s own doc comment), the only way a save response here can still get dropped
    /// by `saveGeneration` is a genuinely-overlapping field/attributes save winning the race. On a
    /// drop, this method returns before ever clearing `notesModel.draft` (draft is cleared ONLY on
    /// confirmed — i.e. still-latest — success, unchanged from before this fix round), so the draft
    /// is still sitting there ready to be re-appended on the NEXT flush. But that dropped save DID
    /// reach the server; if a realtime/`adopt` refresh has folded it into `item.content` by the
    /// time that next flush runs, blindly re-appending the same draft again would duplicate the
    /// paragraph server-side. `tipTapLastParagraphText` (StashKit) checks for exactly that: if the
    /// trimmed draft is already the document's trailing paragraph, this treats it as already saved
    /// — clears the draft and returns without another network call — rather than trusting the
    /// draft's local "still pending" state alone. DISCLOSED: not a complete fix — if that refresh
    /// hasn't landed yet, `item.content` is still stale and the duplicate can still happen once;
    /// closing that fully would need re-fetching the row before every append, which is more
    /// round-trip cost than this rare double-save race justifies.
    @MainActor
    private func flushNotes() async {
        guard notesModel.draft != notesModel.savedDraft else { return }
        let typed = notesModel.draft
        let newContent: String
        if notesModel.isRich {
            let note = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return }
            if tipTapLastParagraphText(item.content) == note {
                notesModel.draft = ""
                notesModel.savedDraft = ""
                return
            }
            newContent = appendNoteParagraph(to: item.content, note: note)
        } else {
            newContent = typed
        }
        let gen = saveGeneration.next()
        saveStatus = .saving
        do {
            let merged = try await editor.save(itemId: item.id, patch: ItemPatch(content: newContent))
            guard saveGeneration.isLatest(gen) else { return }
            if notesModel.isRich {
                notesModel.draft = ""
                notesModel.savedDraft = ""
            } else {
                notesModel.savedDraft = typed
            }
            handleSaved(merged)
            saveStatus = .saved
        } catch {
            guard saveGeneration.isLatest(gen) else { return }
            // Final wave, item D: was `.idle` — see `saveChangedFields`'s matching catch above for
            // the full rationale; applied here too since this was the exact case the brief called
            // out ("failed notes save reads 'Changes saved automatically'"). The draft is never
            // touched on this path, so nothing typed is lost.
            saveStatus = .failed("Couldn't save — try again.")
        }
    }

    /// Shared by every successful `editor.save` call site (field autosave, location, notes):
    /// folds the merged server row into local state and keeps the background grid in sync so it
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
    /// nulling an already-loaded value): `title`/`description`/`supplementalNote`/`attributes`/
    /// `content` (the last added fix round 1, review finding #2, alongside `SaveGeneration` — see
    /// that type's own doc comment for how the two guards divide the work) are the fields under
    /// active local editing in this build, so we compute "is there an unsaved edit in flight" for
    /// each — has it already diverged from `snapshot`, our last confirmed-saved baseline? — and
    /// hand those five flags in. `snapshot` itself always advances to `incoming` here, since its
    /// only job is being the next diff baseline for `changedFields`.
    private func adopt(_ incoming: Item) {
        let next = mergePreservingDetail(
            local: item,
            incoming: incoming,
            hasUnsavedTitle: (item.title ?? "") != (snapshot.title ?? ""),
            hasUnsavedDescription: (item.description ?? "") != (snapshot.description ?? ""),
            hasUnsavedSupplementalNote: (item.supplementalNote ?? "") != (snapshot.supplementalNote ?? ""),
            hasUnsavedLocation: item.attributes != snapshot.attributes,
            hasUnsavedContent: (item.content ?? "") != (snapshot.content ?? "")
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
