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
/// description/notes text/location — whichever field failed) is always left exactly as typed, and
/// (plan 15) it is already queued in `PendingEdits`, so closing the sheet can't lose it. The NEXT
/// successful save on any field — or the queue delivering it — clears this back to `.saved`.
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

/// The editor every detail-sheet save and every pending-edit flush goes through (the sheet's own
/// and `MainTabView`'s app-scope flusher), so both share the UI-test network switches below.
@MainActor
enum DetailEditorFactory {
    static func make() -> ItemEditor {
        ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: SupabaseEmbeddingSyncer()))
    }

    private static var patcher: ItemPatching {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest-stall-item-writes") {
            return StalledItemPatcher()
        }
        if arguments.contains("--uitest-slow-item-writes") {
            return SlowItemPatcher(delay: .seconds(UITestTiming.seconds(after: "--uitest-slow-item-write-seconds") ?? 3))
        }
        #endif
        return SupabaseItemPatcher()
    }
}

#if DEBUG
/// Numeric UI-test launch arguments (`--flag <seconds>`), compiled out of Release.
private enum UITestTiming {
    static func seconds(after flag: String) -> Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }
}

/// `--uitest-stall-item-writes` (UI tests only, compiled out of Release): every item write hangs
/// for 10 s and then times out — a stalled link, the worst case for "close waits on the network" —
/// so `DetailUITests` can prove the sheet closes at once, the edit survives, and a later launch
/// (without the flag) delivers it. Reads and deletes still work.
private struct StalledItemPatcher: ItemPatching {
    private let real = SupabaseItemPatcher()

    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item {
        try? await Task.sleep(for: .seconds(10))
        throw URLError(.timedOut)
    }

    func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        try? await Task.sleep(for: .seconds(10))
        throw URLError(.timedOut)
    }

    func deleteItemCascade(itemId: UUID) async throws { try await real.deleteItemCascade(itemId: itemId) }
    func itemTags(itemId: UUID) async throws -> [StashTag] { try await real.itemTags(itemId: itemId) }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws {
        try await real.addTag(named: named, userId: userId, itemId: itemId)
    }
    func removeTag(tagId: UUID, itemId: UUID) async throws { try await real.removeTag(tagId: tagId, itemId: itemId) }
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] {
        try await real.suggestTags(title: title, content: content, description: description, available: available)
    }
}

/// `--uitest-slow-item-writes` (UI tests only, compiled out of Release): every item write waits
/// 3 s (`--uitest-slow-item-write-seconds <s>` to change it) and then really goes out — a slow link
/// that still succeeds, so `LibraryDetailUITests` can edit a field while an earlier save of it is
/// in flight and watch that save's response land (plan 16 review I-1). Reads, deletes and tags are
/// untouched.
private struct SlowItemPatcher: ItemPatching {
    private let real = SupabaseItemPatcher()
    let delay: Duration

    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item {
        try? await Task.sleep(for: delay)
        return try await real.patch(itemId: itemId, patch: patch)
    }

    func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        try await real.currentAttributes(itemId: itemId)
    }

    func deleteItemCascade(itemId: UUID) async throws { try await real.deleteItemCascade(itemId: itemId) }
    func itemTags(itemId: UUID) async throws -> [StashTag] { try await real.itemTags(itemId: itemId) }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws {
        try await real.addTag(named: named, userId: userId, itemId: itemId)
    }
    func removeTag(tagId: UUID, itemId: UUID) async throws { try await real.removeTag(tagId: tagId, itemId: itemId) }
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] {
        try await real.suggestTags(title: title, content: content, description: description, available: available)
    }
}
#endif

/// Everything one open detail sheet saves through — built ONCE per sheet (plan 15, L9). These used
/// to be separate `@State` initial values, and a `@State` initial value is evaluated on every
/// re-init of the view (every re-render of the presenter — e.g. any `store.items` change while the
/// sheet is open), constructing and discarding an editor, two embedding refreshers, a transcription
/// service, a debouncer, a generation counter and a notes model (with a TipTap JSON parse) each
/// time. `@StateObject`'s autoclosure runs once for the view's lifetime.
@MainActor
final class DetailSheetServices: ObservableObject {
    let editor: ItemEditor
    let fieldDebouncer = Debouncer(interval: DetailSheetServices.fieldDebounceInterval)
    /// Plan 14 Task 2 ("Transcribe with speakers"), final wave B: starts and watches the server's
    /// transcription job — the job writes the item (and its embeddings) itself.
    let transcriptionService = TranscriptionService()
    let summaryGenerator = SummaryGenerator()
    /// The signed-in user's durable queue of unconfirmed edits — the same instance the app-scope
    /// `ItemStore` lays over the library (`PendingEdits.shared(for:)`).
    let pendingEdits: PendingEdits
    /// Notes' own draft/debounce state (Plan 8 Task 5, hoisted out in fix round 1 — see
    /// `NotesEditorModel`'s own doc comment).
    let notesModel: NotesEditorModel
    /// Guards the field-autosave (400ms) vs. notes-autosave (600ms) race (fix round 1, review
    /// finding #2) — see `SaveGeneration`'s own doc comment (StashKit).
    private let saveGeneration = SaveGeneration()
    /// The newest generation handed out — lets the detail fetch tell whether a save started while
    /// it was in flight (L4).
    private(set) var latestGeneration = 0
    /// Autosaves (fields, notes, location) still in flight, and whether the one that finished last
    /// failed — the footer caption follows these, not the save generation, so a newer Sharing
    /// toggle or transcription (which bump the generation) can never leave "Saving…" stuck.
    var savesInFlight = 0
    var lastSaveFailed = false
    /// Set when the sheet goes away: from then on its debounced autosaves stay quiet and the
    /// dismiss-time journal + flush own anything unsaved (plan 15, H5).
    var isClosed = false
    /// A rich-note draft queued by `journalUnconfirmedEdits` (app backgrounded mid-draft): once the
    /// server echoes that exact content back, the draft is in the document and leaves the field.
    var journaledRichDraft: (typed: String, content: String)?

    init(item: Item, userId: UUID) {
        editor = DetailEditorFactory.make()
        pendingEdits = PendingEdits.shared(for: userId)
        notesModel = NotesEditorModel(item: item)
    }

    /// 400 ms after the last title/description/sticky keystroke. `--uitest-field-debounce-seconds
    /// <s>` (UI tests only, compiled out of Release) lengthens it, so a UI test can close the sheet
    /// INSIDE it: the close journals from `onDisappear`, which runs after the dismiss animation —
    /// later than 400 ms after XCUITest's last keystroke, so the autosave always went first.
    nonisolated private static var fieldDebounceInterval: Duration {
        #if DEBUG
        if let seconds = UITestTiming.seconds(after: "--uitest-field-debounce-seconds") {
            return .milliseconds(Int(seconds * 1000))
        }
        #endif
        return .milliseconds(400)
    }

    func nextGeneration() -> Int {
        latestGeneration = saveGeneration.next()
        return latestGeneration
    }

    func isLatest(_ generation: Int) -> Bool { saveGeneration.isLatest(generation) }
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
/// untouched, just no longer surfaced here.
///
/// **Saving (plan 15, H5).** Every autosave still PATCHes as the user types, but the values go
/// into the user's durable `PendingEdits` queue first and leave it only once the server confirms
/// them. Closing the sheet (X or swipe) never waits on the network: it dismisses at once, queues
/// whatever the server hasn't confirmed yet (a save in flight, one that failed, one still in its
/// debounce, a rich-note draft), and starts sending it. The library shows queued values until
/// they land; every later refresh retries what's left.
///
/// **Loading (M5/L4/L6).** Only `page_body` is missing from a list row. The sheet fetches it only
/// when it isn't already there (reopened items and citation sheets skip the round trip), never
/// hides an already-present summary behind a spinner, and says "Couldn't load" (with a retry) if
/// the fetch fails instead of showing misleading empty copy.
struct ItemDetailView: View {
    @State private var item: Item
    /// The last row the SERVER is known to hold — the initial row, our own confirmed saves, or an
    /// observed server update. The diff baseline for everything still unsaved (as `baseline`, the
    /// row as the fields show it); see `adopt(_:)`.
    @State private var snapshot: Item
    @State private var saveStatus: SaveStatus = .idle
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?
    @State private var isDeleted = false
    @StateObject private var services: DetailSheetServices
    @State private var transcriptionErrorMessage: String?
    @State private var isGeneratingSummary = false
    @State private var summaryErrorMessage: String?

    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedTab: ContentTabKey
    /// The `page_body` read (M5/L6) — see `loadDetailIfNeeded`.
    @State private var sourceLoad: DetailSourceLoad = .idle
    /// One shared enum-keyed `@FocusState` for all three text inputs (final wave, item B — see
    /// `DetailField`'s own doc comment). Threaded down through `ItemDetailContent` as a
    /// `FocusState<DetailField?>.Binding`; the footer's hide-keyboard control needs "is ANY of
    /// title/description/notes focused" and "clear whichever one is".
    @FocusState private var focusedField: DetailField?

    init(item: Item, store: ItemStore) {
        // Start from the row as the user last left it — queued (unconfirmed) edits laid over it —
        // whether it came from a library card (already overlaid) or an Ask citation (a raw server
        // read, plan 15 review): seeding the fields and the notes editor from the server's copy
        // would let a new edit silently replace a queued, undelivered note. The diff baseline stays
        // the server's copy, so queued values still count as unsaved here.
        let start = PendingEdits.shared(for: store.userId)
            .sheetStart(for: item, serverRow: store.serverRow(withId: item.id))
        // Plan 16: a title that is only a storage object name starts as an EMPTY field (its
        // placeholder is the card's type label — `titleField`); see `baseline`.
        _item = State(initialValue: ItemDisplay.editableRow(start.shown))
        _snapshot = State(initialValue: start.server)
        self.store = store
        _selectedTab = State(initialValue: contentTabsConfig(for: item.type).defaultTab)
        _services = StateObject(wrappedValue: DetailSheetServices(item: start.shown, userId: store.userId))
    }

    /// `snapshot` as the text fields show it — what every autosave, the dismiss journal and `adopt`
    /// diff the fields against. Plan 16: an object-name title (`f200ad94-….m4a`, Will's device
    /// screenshot) is shown as an empty field and reads as empty here too, so the untouched field
    /// is never an edit — opening and closing the sheet never writes a title, and the object name
    /// stays for the server's jobs to replace with an AI title (`ItemDisplay.editableRow`).
    private var baseline: Item { ItemDisplay.editableRow(snapshot) }

    /// The fields measured against `baseline` AND this item's durable queue — the one rule the
    /// autosave, the dismiss journal and `adopt` share (`DetailFieldEdits`). Plan 16 review I-1 and
    /// Task 4c: against `baseline` alone, putting the title, the description or the sticky note back
    /// after another value of it was sent (in flight, or failed and queued) — a clear, or deleting
    /// " x" again — looked like no edit, and the sent value came back into the field and onto the
    /// server. The queue holds every save from the moment it starts until the server confirms it.
    private var fieldEdits: DetailFieldEdits {
        DetailFieldEdits(local: item, baseline: baseline, queued: services.pendingEdits.edit(for: item.id))
    }

    /// A plain note's draft measured against what the server confirmed AND the queue (Task 4c,
    /// `PlainNoteDraft`): cleared after its text was sent, it still has to be sent. Rich notes are
    /// append-only and keep their own `draft != savedDraft` check.
    private var plainNote: PlainNoteDraft {
        let notes = services.notesModel
        return PlainNoteDraft(draft: notes.draft, saved: notes.savedDraft,
                              queued: services.pendingEdits.edit(for: item.id)?.content?.value)
    }

    /// "Transcribing…" while this app watches a job for the item (`TranscriptionActivity`, app-wide)
    /// or while the item itself says the server's job is running (`media.transcript` — e.g. a
    /// fresh recording's first transcription, or a run started before a relaunch).
    private var isTranscribing: Bool {
        TranscriptionActivity.shared.isRunning(item.id)
            || (TranscriptJobState(attributes: item.attributes)?.isRunning(at: Date()) ?? false)
    }

    var body: some View {
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
                    // Every child below carries its own explicit top gap (the sheet's 14/24
                    // rhythm); `ItemDetailContent`/`DetailsDrawer`/`SharingSection` each open with
                    // a `SectionHeader`, which supplies its own `DetailLayout.section` gap.
                    VStack(alignment: .leading, spacing: 0) {
                        DetailEyebrow(item: item)
                        titleField
                            .padding(.top, DetailLayout.gap)
                        descriptionField
                            .padding(.top, DetailLayout.gap)
                        // Web parity (`EditItemSheet.tsx`'s `hasImage` gate): `(type === 'image'
                        // || type === 'link') && file_path` — `item.thumbnailURL` is that same
                        // "file_path present" check (`ItemRules.swift`).
                        if (item.type == .image || item.type == .link), let url = item.thumbnailURL {
                            heroImage(url)
                                .padding(.top, DetailLayout.gap)
                        }
                        if item.type == .link, let urlString = item.url, !urlString.isEmpty {
                            DetailURLBar(urlString: urlString)
                                .padding(.top, DetailLayout.gap)
                        }
                        ItemDetailContent(item: item, selectedTab: $selectedTab,
                                          sourceLoad: sourceLoad,
                                          onRetryDetail: { Task { await loadDetailIfNeeded() } },
                                          notesModel: services.notesModel, notesFocused: $focusedField,
                                          scheduleNotesFlush: scheduleNotesFlush, flushNotesNow: flushNotesNow,
                                          isTranscribing: isTranscribing,
                                          transcriptionErrorMessage: transcriptionErrorMessage,
                                          onTranscribeWithSpeakers: { Task { await retranscribe() } },
                                          isGeneratingSummary: isGeneratingSummary,
                                          summaryErrorMessage: summaryErrorMessage,
                                          onGenerateSummary: { Task { await generateSummary() } })

                        // `DetailsDrawer`'s own `SectionHeader` ("DETAILS") draws the hairline.
                        DetailsDrawer(item: item, attributes: attributesBinding)

                        SharingSection(item: item, supplementalNote: supplementalNoteBinding,
                                       setPublic: setPublic)
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
        .task { await loadDetailIfNeeded() }
        .task { await followRunningTranscription() }
        .onChange(of: store.items) { _, _ in
            // The server's version, never the list's (which shows queued edits over it).
            guard let updated = store.serverRow(withId: item.id), updated != snapshot else { return }
            let transcriptSettled = Self.transcriptJobSettled(from: snapshot, to: updated)
            adopt(updated)
            // The server's transcription job just finished (realtime): list rows carry no
            // `page_body`, so read the new transcript — unless this app's own watcher is about to
            // deliver the finished row anyway.
            if transcriptSettled, updated.pageBody == nil, !TranscriptionActivity.shared.isRunning(item.id) {
                Task { await loadDetailIfNeeded(force: true) }
            }
        }
        // Leaving the foreground with the sheet still open (app switcher, lock, Control Center):
        // queue what's unsaved now. `.inactive` too — a kill from the app switcher isn't
        // guaranteed to deliver `.background` first. The next foreground refresh sends it.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !isDeleted { journalUnconfirmedEdits() }
        }
        .onAppear { services.isClosed = false }
        // Fires on every way out — X, swipe, or a programmatic dismissal.
        .onDisappear { handleDismiss() }
        .confirmationDialog("Delete this item? This can't be undone.", isPresented: $showDeleteConfirm,
                             titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Flow surface pieces

    /// Object title (panel) per DESIGN.md: 500 · 28 / 1.2 · −0.02em, inline-editable — "no input
    /// chrome at rest; violet wash on hover; wash + ring on focus." Touch has no hover, so the
    /// wash/ring both key off `focusedField == .title` here.
    ///
    /// Plan 16: the placeholder is what the card shows once the field is left empty — the type
    /// label ("Voice note", "Photo", …) on an audio, image, video or file item (an object-name
    /// title opens as an empty field, see `baseline`; a cleared one is saved as "" and reads the
    /// same, M-6), "Untitled" on any other type.
    ///
    /// Plan 16 (HIG + accessibility): the `panelTitle` role (28 pt, scaling with `.title`), and the
    /// title WRAPS — a vertical-axis field — so no part of it is ever cut off (it used to scroll
    /// sideways out of view in one line, at every size). It is still one line of text: Return
    /// ends editing, as it did, and a pasted line break becomes a space (`keepTitleOnOneLine`).
    /// The placeholder is `muted` (`prompt:`; the system grey is 1.7:1 and this one names the
    /// item), and VoiceOver calls the field "Title" — not its placeholder, which would announce a
    /// typed title as "Voice note" or "Untitled". A vertical-axis field is a text view underneath,
    /// which a bare XCUITest `.tap()` doesn't always focus — UI tests tap until it has focus
    /// (`tapUntilFocused`).
    private var titleField: some View {
        let placeholder = ItemDisplay.titlePlaceholder(for: snapshot)
        return TextField("Title", text: titleBinding,
                         prompt: Text(placeholder).foregroundStyle(StashColor.muted), axis: .vertical)
            .stashFont(.panelTitle)
            .stashTracking(-0.02, role: .panelTitle)
            .foregroundStyle(StashColor.ink)
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .onChange(of: item.title) { oldTitle, newTitle in keepTitleOnOneLine(was: oldTitle, now: newTitle) }
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
            .detailFieldTapTarget { focusedField = .title }
    }

    /// Plan 16: reading text — the `reading` role, 17 pt (was 14) — in `muted` (5.38:1), with a
    /// `muted` placeholder (`prompt:`); VoiceOver names the field "Description".
    private var descriptionField: some View {
        TextField("Description", text: descriptionBinding,
                  prompt: Text("Add a description…").foregroundStyle(StashColor.muted), axis: .vertical)
            .stashFont(.reading)
            .foregroundStyle(StashColor.muted)
            // Body line spacing (DESIGN.md "~1.55") — the same leading `MarkdownBlocksView`'s
            // paragraphs and the content tabs' plain-text fallback use, so the description reads
            // at the rhythm of the rest of the sheet's reading text; it grows with the text.
            .stashLeading(0.55, role: .reading)
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
            .detailFieldTapTarget { focusedField = .description }
    }

    /// Contained hero, radius 16 + card shadow — `.image` items, and (plan 12 fix round 3) any
    /// `.link` item whose `thumbnailURL` resolves (a scraped og-image), matching web's `hasImage`
    /// gate. Plan 15: loaded through the app's `ImagePipeline` (memory + disk cache, decoded at the
    /// sheet's width instead of the original's full resolution) — a hero the card already showed
    /// comes straight off disk.
    private func heroImage(_ url: URL) -> some View {
        CachedImage(url: url, fit: DetailHeroSizing.fit) { phase in
            if case .success(let image) = phase {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
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
    /// close button. Plan 15 (H5): closes at once, never waiting on a save — `handleDismiss` (via
    /// `onDisappear`, which a swipe-to-dismiss reaches too) queues and sends anything unconfirmed.
    ///
    /// Plan 16: sheet chrome, so the 28 pt circle and its glyph keep their size at every text size
    /// (the Large Content Viewer shows "Close" large) — but it takes taps across 44×44 pt
    /// (`.stashPlain` puts the target on the label; the 14 pt inset stays outside the button).
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(StashType.decorative(.semibold, size: 12))
                .foregroundStyle(StashColor.muted)
                .frame(width: 28, height: 28)
                .background(StashColor.paper, in: Circle())
                .overlay(Circle().strokeBorder(StashColor.hairline, lineWidth: 1))
        }
        .buttonStyle(.stashPlain)
        .stashIconControl("Close", systemImage: "xmark")
        .accessibilityIdentifier("detail.done")
        .padding(14)
    }

    /// Pinned footer bar (hairline top): "Delete item" left, autosave status + hide-keyboard
    /// right — port of `EditItemSheet.tsx`'s footer, plus (final wave, F7) the sheet's one
    /// keyboard-dismiss control: a pinned SIBLING below the ScrollView, so it's reachable no
    /// matter which of the three fields (`DetailField`) is focused or where the sheet is
    /// scrolled.
    ///
    /// Plan 16: at the accessibility sizes the autosave line moves under "Delete item" (a row of
    /// its own, full width) instead of squeezing beside it; below them the row is as before, the
    /// caption wrapping onto a second line if it must.
    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        deleteButton
                        Spacer(minLength: 8)
                        dismissKeyboardButton
                    }
                    autosaveLabel
                }
            } else {
                HStack {
                    deleteButton
                    Spacer(minLength: 8)
                    autosaveLabel
                        .multilineTextAlignment(.trailing)
                    dismissKeyboardButton
                }
            }
            if let deleteErrorMessage {
                Text(deleteErrorMessage)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("detail.deleteError")
            }
        }
        .padding(.horizontal, DetailLayout.inset)
        .padding(.vertical, 10)
        .background(StashColor.paper)
        .overlay(alignment: .top) { hairline }
    }

    /// The sheet's one keyboard-dismiss control, while any field has focus: a `CircleIcon` (its
    /// own 44 pt target), named for VoiceOver and the Large Content Viewer. `.plain`, as every
    /// circle button is: under the default (borderless) style the button's frame stayed the 40 pt
    /// circle — the circle's 44 pt target overhang didn't count (measured).
    @ViewBuilder private var dismissKeyboardButton: some View {
        if focusedField != nil {
            Button {
                focusedField = nil
            } label: {
                CircleIcon(systemImage: "keyboard.chevron.compact.down")
            }
            .buttonStyle(.plain)
            .stashIconControl("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
            .accessibilityIdentifier("detail.dismissKeyboard")
        }
    }

    /// Plan 16: an inline action — `inlineButton` (Medium 15, was a 12 pt caption) in
    /// `destructive` (5.06:1), with a 44 pt target (`.stashPlain`; it was the 85×17 pt word). It
    /// keeps its one line and its width before the autosave caption beside it gives way.
    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            if isDeleting {
                ProgressView()
            } else {
                Label("Delete item", systemImage: "trash")
                    .stashFont(.inlineButton)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.stashPlain)
        .foregroundStyle(StashColor.destructive)
        .disabled(isDeleting)
        .layoutPriority(1)
        .accessibilityIdentifier("detail.delete")
    }

    /// `.failed` (final wave, item D) renders as its own `detail.autosave.error` identifier in
    /// `StashColor.destructive`, distinct from the resting `detail.autosave` identifier every
    /// other state shares — so a UI test (or VoiceOver user) can tell "saved" and "failed, please
    /// retry" apart without parsing label text. Plan 16: `meta`, and the resting caption `muted`
    /// (it was `faint`, 2.79:1).
    @ViewBuilder private var autosaveLabel: some View {
        if case .failed(let message) = saveStatus {
            Text(message)
                .stashFont(.meta)
                .foregroundStyle(StashColor.destructive)
                .accessibilityIdentifier("detail.autosave.error")
        } else {
            Text(saveStatus == .saving ? "Saving…" : "Changes saved automatically")
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
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

    /// Plan 16: the title field wraps (`axis: .vertical`), but a title is one line of text. A
    /// vertical-axis field inserts a line break on Return, so while the user is typing in it: a
    /// Return (the old title plus one line break) is taken back out and ends editing, as it did in
    /// the single-line field; a pasted line break becomes a space. The line break is only ever on
    /// screen for the one update this takes — the 400 ms autosave never sees it. Titles that
    /// arrive from the server are left alone (the field isn't focused then).
    private func keepTitleOnOneLine(was oldTitle: String?, now newTitle: String?) {
        guard focusedField == .title, let newTitle, newTitle.contains(where: \.isNewline) else { return }
        if newTitle.filter({ !$0.isNewline }) == (oldTitle ?? "") {
            item.title = oldTitle
            focusedField = nil
        } else {
            item.title = String(newTitle.map { $0.isNewline ? " " : $0 })
        }
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { item.description ?? "" }, set: { newValue in
            item.description = newValue
            scheduleFieldSave()
        })
    }

    /// Sticky-note text (`SharingSection`) rides the same debounced field-autosave path as
    /// title/description — `saveChangedFields` measures it against `baseline` and the queue.
    private var supplementalNoteBinding: Binding<String> {
        Binding(get: { item.supplementalNote ?? "" }, set: { newValue in
            item.supplementalNote = newValue
            scheduleFieldSave()
        })
    }

    /// Backs `LocationRow` (Task 8). A location commit is a discrete, deliberate action
    /// (Enter/blur/remove-X — never per-keystroke), so it saves immediately rather than through
    /// `fieldDebouncer`. The optimistic `item.attributes = newValue` write is what `adopt(_:)`'s
    /// unsaved-location check protects from a racing refresh.
    private var attributesBinding: Binding<ItemAttributes> {
        Binding(get: { item.attributes }, set: { newValue in
            item.attributes = newValue
            Task { await saveAttributes(newValue) }
        })
    }

    private func scheduleFieldSave() {
        Task { await services.fieldDebouncer.call { await saveChangedFields() } }
    }

    // MARK: - Save / delete

    /// The one path every autosave takes (fields, notes, location). The values go into
    /// `PendingEdits` FIRST (write-ahead: a failure, a crash or a close mid-save can't lose them),
    /// then the PATCH — sent through `ItemWriteQueue`, so it never overtakes an earlier write to
    /// this item. On success the store gets the server's row, the queue forgets what the server
    /// confirmed, and — when no newer save started meanwhile (`SaveGeneration`, fix round 1) — the
    /// sheet adopts it. On failure the typed value stays on screen and in the queue. The footer
    /// says "Saving…" while any autosave is in flight and then reports how the last one ended
    /// (writes to one item finish in order, so that's the newest). Returns the saved row, or nil
    /// when the save failed.
    ///
    /// `send` replaces the plain PATCH of `patch` — a location edit is written onto the server's
    /// current attributes instead (`saveAttributes`); `patch` is still what gets queued.
    ///
    /// Plan 16 (review I-1, Task 4c m-3): the landing is StashKit's `DetailFieldEdits.landing`, in
    /// its one safe order. When the save lands after the user changed a field it sent — e.g.
    /// cleared "Gro" inside the next debounce, so no newer save has queued the clear yet — the
    /// field's value is queued before `adopt` reads the queue (not once the sheet has closed: its
    /// journal already did). The confirm then keeps it, `adopt` keeps the field as it is, and the
    /// next autosave (or the close) sends it.
    @MainActor
    private func save(_ patch: ItemPatch, send: (() async throws -> Item)? = nil) async -> Item? {
        let capturedAt = Date()
        let pendingEdits = services.pendingEdits
        pendingEdits.record(itemId: item.id, patch: patch, capturedAt: capturedAt)
        let generation = services.nextGeneration()
        services.savesInFlight += 1
        saveStatus = .saving
        var saved: Item?
        do {
            let itemId = item.id
            let editor = services.editor
            let result = try await (send ?? { try await editor.save(itemId: itemId, patch: patch) })()
            let landed = DetailFieldEdits.landing(patch, capturedAt: capturedAt, as: result, local: item,
                                                  baseline: baseline, queue: pendingEdits,
                                                  sheetIsOpen: !services.isClosed, at: Date())
            store.applyDetail(result)
            if services.isLatest(generation) { adopt(result, fields: landed) }
            saved = result
        } catch {
            saved = nil
        }
        services.lastSaveFailed = saved == nil
        services.savesInFlight -= 1
        if services.savesInFlight == 0 {
            saveStatus = services.lastSaveFailed ? .failed("Couldn't save — try again.") : .saved
        }
        return saved
    }

    /// The debounced field autosave (400ms after the last title/description/sticky keystroke).
    /// Naturally idempotent — nothing unsaved (`DetailFieldEdits.textPatch`) is a no-op. Marked
    /// @MainActor deliberately: it's reached through `Debouncer`, its own (non-Main) actor, whose
    /// internal `Task` doesn't inherit the main actor. Quiet once the sheet has closed — the
    /// dismiss-time journal + flush own anything still unsaved then.
    @MainActor
    private func saveChangedFields() async {
        guard !services.isClosed else { return }
        let patch = fieldEdits.textPatch
        guard !patch.isEmpty else { return }
        _ = await save(patch)
    }

    /// `LocationRow`'s save (via `attributesBinding`). An attributes-only patch never schedules an
    /// embedding refresh (`ItemPatch.touchesTextFields` excludes `attributes` — web parity). Plan
    /// 15 (M8): a failure is no longer silent — the footer shows it, the new location stays on
    /// screen, and it's queued like any other field (flushed onto the server's CURRENT attributes,
    /// see `PendingEdits.flush`) instead of vanishing when the sheet closes.
    ///
    /// Final wave B: the save itself goes onto the server's current attributes too
    /// (`ItemEditor.saveLocation` — read in the item's write slot, only `location` replaced). The
    /// sheet's blob can be minutes old while production writes `attributes` asynchronously (the
    /// transcription job's `media.transcript`, enrichment's `enrichment.*`); PATCHing it whole
    /// rolled those back and re-queued enrichment.
    @MainActor
    private func saveAttributes(_ attributes: ItemAttributes) async {
        guard !services.isClosed else { return }
        let itemId = item.id
        let location = attributes.location
        let editor = services.editor
        _ = await save(ItemPatch(attributes: attributes)) {
            try await editor.saveLocation(itemId: itemId, location: location)
        }
    }

    /// L5: the Sharing toggle flips at once (optimistic) and bumps the save generation like every
    /// other save; on failure it flips back (so the switch never claims a state the server doesn't
    /// hold) and `SharingSection` shows its inline error. Not written ahead to `PendingEdits` —
    /// a failed share while the sheet is open is reverted, not retried later. If the sheet closes
    /// while this is still in flight, the dismiss journal queues the toggle the user last saw.
    /// Un-sharing an item with a sticky note clears the note in the same PATCH (the section asks
    /// first); if that fails, the note comes back — whether the server holds it or the queue still
    /// has to deliver it (Task 4c, `DetailFieldEdits.undoingFailedUnshare`: the field reads the
    /// queue, so an empty field under a queued note would otherwise be sent as a clear). The footer
    /// caption is left to the autosaves (`save(_:)`) — this toggle reports in its own section, and
    /// never sets or strands "Saving…" (plan 15 review).
    @MainActor
    private func setPublic(_ isPublic: Bool) async -> Bool {
        let before = (isPublic: item.isPublic, note: item.supplementalNote)
        let patch = services.editor.togglePublic(item: item, to: isPublic)
        let clearsNote = patch.supplementalNote == ""
        item.isPublic = isPublic
        if clearsNote { item.supplementalNote = nil }
        let capturedAt = Date()
        let generation = services.nextGeneration()
        do {
            let saved = try await services.editor.save(itemId: item.id, patch: patch)
            store.applyDetail(saved)
            services.pendingEdits.confirm(itemId: saved.id, patch: patch, capturedAt: capturedAt)
            if services.isLatest(generation) { adopt(saved) }
            return true
        } catch {
            if item.isPublic == isPublic { item.isPublic = before.isPublic }
            if clearsNote {
                item = DetailFieldEdits.undoingFailedUnshare(noteBefore: before.note, local: item, baseline: baseline,
                                                             queue: services.pendingEdits, at: Date())
            }
            return false
        }
    }

    /// Debounced (per-keystroke) notes flush trigger, handed to `NotesEditor` via
    /// `ItemDetailContent` — see `NotesEditorModel.scheduleSave`'s own doc comment.
    private func scheduleNotesFlush() {
        services.notesModel.scheduleSave { await self.flushNotes() }
    }

    /// Explicit, immediate notes flush — the blur handler `NotesEditor` installs for both modes.
    private func flushNotesNow() async {
        await services.notesModel.flushNow { await self.flushNotes() }
    }

    /// The actual notes save: plain notes save the whole draft as-is; rich notes wrap the draft as
    /// a new paragraph via `appendNoteParagraph` onto the CURRENT `item.content` (the TipTap JSON
    /// itself never round-trips through the plain-text field).
    ///
    /// Idempotence guard (final wave, item C / minor 6): if the trimmed draft is already the
    /// document's trailing paragraph (an earlier save of it landed and was folded back in), the
    /// draft is treated as saved rather than appended twice.
    ///
    /// Plan 15: the draft bookkeeping runs on every successful save (the text WAS saved), not only
    /// the newest one, and a rich draft the user kept typing into during the save keeps whatever
    /// was typed after the saved part instead of being wiped.
    ///
    /// Task 4c: a plain draft is measured against the queue too (`plainNote`) — cleared while its
    /// text was still in flight (or queued after a failed send), it is back at `savedDraft` yet
    /// still has to be sent.
    @MainActor
    private func flushNotes() async {
        guard !services.isClosed else { return }
        let notes = services.notesModel
        guard notes.isRich ? notes.draft != notes.savedDraft : plainNote.needsSave else { return }
        let typed = notes.draft
        let newContent: String
        if notes.isRich {
            let note = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return }
            if tipTapLastParagraphText(item.content) == note {
                notes.draft = ""
                notes.savedDraft = ""
                return
            }
            newContent = appendNoteParagraph(to: item.content, note: note)
        } else {
            newContent = typed
        }
        guard await save(ItemPatch(content: newContent)) != nil else { return }
        if notes.isRich {
            notes.removeSavedPrefix(typed)
        } else {
            notes.savedDraft = typed
        }
    }

    /// Plan 14 Task 2 ("Transcribe with speakers"). Final wave B: the SERVER's transcription job
    /// (`transcribe-audio { itemId, rebuild: true }`, deployed v28) does the work and every write —
    /// any file size (long recordings are split server-side, no gateway timeout in the way), and
    /// the transcript/description land as the job's writes rather than user edits that would shut
    /// enrichment out of them. `TranscriptionService` starts it, watches `media.transcript`, and
    /// hands back the finished row, read after any save of this sheet already in flight (so
    /// adopting it can't roll one back). The busy state lives app-wide (`TranscriptionActivity`,
    /// plan 15 M9), so it lasts the whole run, even across closing and reopening this item, and a
    /// second run can't be started meanwhile.
    @MainActor
    private func retranscribe() async {
        guard !isTranscribing else { return }
        transcriptionErrorMessage = nil
        do {
            let outcome = try await services.transcriptionService.retranscribe(item: item)
            applyTranscription(outcome, reportFailure: true)
        } catch TranscriptionServiceError.alreadyRunning {
            // A run started earlier (maybe from a sheet since closed) is still going; its result
            // reaches this sheet through the store.
        } catch TranscriptionServiceError.stoppedWatching {
            // The job outlasted the wait (it finishes server-side — the item still says it's
            // running) or finished but couldn't be read back: nothing wrong to report.
        } catch {
            // The job never started (web parity copy, `TranscriptContent.tsx`): nothing changed.
            transcriptionErrorMessage = "Couldn’t update the transcript. The original is preserved. Please try again."
        }
    }

    /// A job was already running when the sheet opened — a fresh recording's first transcription,
    /// or a rebuild started before the sheet was closed or the app relaunched: follow it, so the
    /// transcript appears here when it lands. Ends (the job carries on) when the sheet closes.
    @MainActor
    private func followRunningTranscription() async {
        guard let job = TranscriptJobState(attributes: item.attributes), job.isRunning(at: Date()) else { return }
        guard let outcome = try? await services.transcriptionService.follow(itemId: item.id) else { return }
        applyTranscription(outcome, reportFailure: false)
    }

    /// Whether `new` (a server row) reports the item's transcription job settled — done or failed —
    /// where `old` didn't show that same state.
    private static func transcriptJobSettled(from old: Item, to new: Item) -> Bool {
        guard let job = TranscriptJobState(attributes: new.attributes), job.status == .done || job.status == .failed
        else { return false }
        return TranscriptJobState(attributes: old.attributes) != job
    }

    /// Folds a settled job's row into the list and the sheet (the user's unsaved edits are kept —
    /// `adopt`). A failure is only reported for a run the user started here, and only when the
    /// Transcript tab isn't already saying it.
    @MainActor
    private func applyTranscription(_ outcome: TranscriptionOutcome, reportFailure: Bool) {
        switch outcome {
        case .finished(let row):
            store.applyDetail(row)
            adopt(row)
        case .failed(let row, let reason):
            if let row {
                store.applyDetail(row)
                adopt(row)
            }
            guard reportFailure else { return }
            // No transcript on screen: the Transcript tab itself now says why
            // (`ItemDisplay.transcriptFailureText`) — an inline error would only repeat it.
            let tabExplainsFailure = (item.pageBody ?? "").isEmpty
                && (sourceLoad == .idle || sourceLoad == .loaded)
                && ItemDisplay.transcriptFailureText(for: item) != nil
            guard !tabExplainsFailure else { return }
            transcriptionErrorMessage = reason == "no_speech"
                ? "No speech was detected in this recording."
                : "Couldn’t update the transcript. Please try again."
        }
    }

    /// "Generate summary" in an empty Summary tab (plan 15; web parity `useItemSourceContent`).
    /// `summarize-content` writes `items.summary` (and refreshes embeddings) itself — the sheet just
    /// shows the text and keeps the list in step.
    @MainActor
    private func generateSummary() async {
        guard !isGeneratingSummary else { return }
        isGeneratingSummary = true
        summaryErrorMessage = nil
        defer { isGeneratingSummary = false }
        do {
            let summary = try await services.summaryGenerator.generate(itemId: item.id)
            item.summary = summary
            snapshot.summary = summary
            if var row = store.serverRow(withId: item.id) {
                row.summary = summary
                store.applyDetail(row)
            }
        } catch SummaryGenerationError.noSourceContent {
            summaryErrorMessage = "There's no captured content to summarize yet."
        } catch {
            summaryErrorMessage = "Couldn't generate a summary. Please try again."
        }
    }

    // MARK: - Close (plan 15, H5)

    /// Everything on screen the server hasn't confirmed, as one patch: fields that differ from the
    /// server's last row (in flight, failed, or still in a debounce) — and a title, description or
    /// sticky note that differs from a value still queued for it (plan 16, I-1 and Task 4c: a clear
    /// or a revert closed straight after the other value was sent) — an optimistic Sharing flip, a
    /// location edit, and the notes draft (a plain note whole, measured against the queue too; a
    /// rich draft appended as a new paragraph — never flattened). Only what the user actually
    /// changed: a field another device updated meanwhile matches `baseline` and is left alone.
    private func unconfirmedPatch() -> (patch: ItemPatch, richDraft: (typed: String, content: String)?) {
        var patch = fieldEdits.textPatch
        if item.isPublic != baseline.isPublic { patch.isPublic = item.isPublic }
        if item.attributes.location != baseline.attributes.location { patch.attributes = item.attributes }
        var richDraft: (typed: String, content: String)?
        let notes = services.notesModel
        if notes.isRich {
            if notes.draft != notes.savedDraft {
                let note = notes.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty, tipTapLastParagraphText(item.content) != note {
                    let content = appendNoteParagraph(to: item.content, note: note)
                    patch.content = content
                    richDraft = (notes.draft, content)
                }
            }
        } else if plainNote.needsSave {
            patch.content = notes.draft
        }
        return (patch, richDraft)
    }

    /// Writes `unconfirmedPatch()` to the durable queue, synchronously.
    private func journalUnconfirmedEdits() {
        let (patch, richDraft) = unconfirmedPatch()
        guard !patch.isEmpty else { return }
        services.pendingEdits.record(itemId: item.id, patch: patch, capturedAt: Date())
        if let richDraft { services.journaledRichDraft = richDraft }
    }

    /// The sheet is gone (X, swipe, or programmatic): queue whatever the server hasn't confirmed —
    /// synchronously, before anything else can happen — and start sending it. Nothing here waits:
    /// the send runs in its own task, after any of this sheet's saves still in flight
    /// (`ItemWriteQueue`); if it fails, the entry stays queued for the next refresh.
    private func handleDismiss() {
        guard !isDeleted, !services.isClosed else { return }
        services.isClosed = true
        journalUnconfirmedEdits()
        let itemId = item.id
        let pendingEdits = services.pendingEdits
        guard pendingEdits.edit(for: itemId) != nil else { return }
        let editor = services.editor
        let store = store
        Task { @MainActor in
            await pendingEdits.flush(editor: editor, itemIds: [itemId]) { store.applyDetail($0) }
        }
    }

    /// Folds a fresher SERVER row into the sheet — an enrichment finishing, another device's edit,
    /// our own save coming back, or the `page_body` fetch. The merge is StashKit's
    /// `DetailFieldEdits.adopting` (over `mergePreservingDetail`): every field the user has changed
    /// locally (differs from `baseline`, the last server row as the fields show it) keeps the local
    /// value; everything else takes the server's. `snapshot` always advances to `incoming`.
    /// `fields` is that merge when the caller already made it — a landed save's, which
    /// `DetailFieldEdits.landing` returns.
    ///
    /// Plan 15: the location check compares `location` only — Task 5 made nested attributes
    /// loss-less, so a whole-blob compare also tripped whenever the server rewrote e.g.
    /// `media.transcript`, pinning the sheet to its stale blob. A pending location now keeps just
    /// the location over the server's (fresh) attributes. An optimistic Sharing flip is kept the
    /// same way (L5).
    ///
    /// Plan 16: the title is compared and merged as the field shows it (`ItemDisplay.editableRow`)
    /// — an untouched empty placeholder field takes a server title that arrives meanwhile (the
    /// transcription job's AI title, via realtime), and a new object name still reads as empty.
    /// The title, the description and the sticky note are each kept while a write of them is
    /// still queued (review I-1, Task 4c): a "Gro" response can't refill a field the user cleared
    /// after sending "Gro", nor a " x" response a description the user put back.
    private func adopt(_ incoming: Item, fields: Item? = nil) {
        let next = fields ?? fieldEdits.adopting(incoming)
        snapshot = incoming
        item = next
        reconcileNotesDraft(with: incoming)
        // A failed save the queue has since delivered (e.g. flushed on foreground) is no longer
        // failed — the caption shouldn't keep saying so.
        if case .failed = saveStatus, services.savesInFlight == 0, unconfirmedPatch().patch.isEmpty,
           services.pendingEdits.edit(for: item.id) == nil {
            services.lastSaveFailed = false
            saveStatus = .saved
        }
    }

    /// Keeps the notes draft honest when the server's content catches up with it: a queued rich
    /// draft leaves the field once the document contains it; a plain draft the server now holds
    /// counts as saved.
    private func reconcileNotesDraft(with incoming: Item) {
        let notes = services.notesModel
        if notes.isRich {
            guard let journaled = services.journaledRichDraft, incoming.content == journaled.content else { return }
            services.journaledRichDraft = nil
            notes.removeSavedPrefix(journaled.typed)
        } else if notes.draft != notes.savedDraft, (incoming.content ?? "") == notes.draft {
            notes.savedDraft = notes.draft
        }
    }

    @MainActor
    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        deleteErrorMessage = nil
        do {
            try await services.editor.delete(itemId: item.id)
            services.pendingEdits.discard(itemId: item.id)
            isDeleted = true
            dismiss()
            // Fire-and-forget, matching the save paths' "closing never waits on the network"
            // ethos — the grid will drop the row itself once this resolves.
            Task { await store.refresh() }
        } catch ItemEditorError.deleteMatchedNoRows {
            // Final wave (F6): a well-understood, non-transient shape (RLS/stale id) — "try
            // again" would be actively wrong copy here.
            deleteErrorMessage = "Couldn't delete this item — it may not exist anymore or you may not have permission."
        } catch {
            // Everything else (network failure, `.deleteResponseUnreadable`, …) is plausibly
            // transient — "try again" is still the right steer.
            deleteErrorMessage = "Couldn't delete — try again."
        }
    }

    /// `page_body` is the one column list reads leave out (tens of KB per item). Plan 15:
    /// - M5: fetched only when the row doesn't already carry it — a reopened item keeps it from
    ///   earlier in the session, and a citation sheet's row was just fetched with it.
    /// - L4: the whole row is adopted only when no save started (or was in flight) while it was
    ///   being read — otherwise it may predate that save, and only its `page_body` is used.
    /// - L6: a failure is remembered, so the source tabs say "Couldn't load" with a retry instead
    ///   of empty-state copy that reads as "there's nothing here".
    ///
    /// `force` re-reads even though a `page_body` is on screen — it's known to be stale (the
    /// server's transcription job just replaced it). The old text stays up while the read runs.
    @MainActor
    private func loadDetailIfNeeded(force: Bool = false) async {
        guard needsSourceContent(item.type), force || item.pageBody == nil, sourceLoad != .loading else { return }
        sourceLoad = .loading
        let itemId = item.id
        let generationAtStart = services.latestGeneration
        let writesInFlightAtStart = ItemWriteQueue.shared.isBusy(itemId)
        do {
            let detail = try await SupabaseItemsFetcher().fetchDetail(id: itemId)
            let savedSinceStart = writesInFlightAtStart || ItemWriteQueue.shared.isBusy(itemId)
                || services.latestGeneration != generationAtStart
            if savedSinceStart {
                item.pageBody = detail.pageBody
                snapshot.pageBody = detail.pageBody
                if var row = store.serverRow(withId: itemId) {
                    row.pageBody = detail.pageBody
                    store.applyDetail(row)
                }
            } else {
                adopt(detail)
                store.applyDetail(detail)
            }
            sourceLoad = .loaded
        } catch {
            // A read cancelled because the sheet went away isn't a failure worth showing.
            sourceLoad = Task.isCancelled ? .idle : .failed
        }
    }
}

private extension View {
    /// Plan 16 (HIG: 44 pt targets): the title and description are inline fields with no chrome
    /// at rest, and one line of them is shorter than 44 pt — a one-line description is ~25 pt, the
    /// title ~38 at the default text size. This takes taps across at least 44 pt of height without
    /// growing the layout (an overhang, like `stashMinimumHitTarget`), and a tap on the overhang
    /// focuses the field — a bare overhang would swallow it. Taps on the field itself still reach
    /// the field. The sheet's 14 pt gaps keep these overhangs apart from each other and from the
    /// URL bar's "Open link" target.
    func detailFieldTapTarget(_ focus: @escaping () -> Void) -> some View {
        background {
            Color.clear
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture(perform: focus)
                // Touch only: VoiceOver reaches the field itself.
                .accessibilityHidden(true)
        }
    }
}
