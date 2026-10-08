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
/// successful save on any field clears this back to `.saved`, and so does everything that failed
/// since then landing some other way: a flush or a later write delivering it, or a server row the
/// sheet adopts already holding it (`ItemDetailView.settleSaveCaption`; batch B fix round 1).
enum SaveStatus: Equatable {
    case idle, saving, saved
    case failed(String)
}

/// The sheet's focusable text inputs (final wave, item B) — one shared `@FocusState` rather than
/// independent `Bool`s, specifically so the footer's "hide keyboard" button can defocus WHICHEVER
/// is currently active. Previously that button hardcoded `notesFocused = false`, so it was a dead
/// tap unless notes specifically had focus (confirmed live: tapping it while title/description was
/// focused left the keyboard up). `NotesEditor` itself binds into this same enum via `equals:
/// .notes`, not a private `Bool` of its own — see its own doc comment for why a
/// `FocusState<DetailField?>.Binding` has to be threaded all the way down for that to work.
/// Plan 16 (Task 4d): `SharingSection`'s sticky note binds in the same way (`.stickyNote`) — with
/// a focus of its own, the hide-keyboard control never appeared for it.
enum DetailField: Hashable {
    case title, description, notes, stickyNote
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
        if let failures = UITestWriteFailures.shared {
            return FailingItemPatcher(failures: failures)
        }
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

/// `--uitest-fail-item-writes <item id> <n>` (UI tests only, compiled out of Release): the first
/// `n` PATCHes of that item fail at once, as offline, and every later one really goes out — a link
/// that drops and comes back between two writes. `LibraryDetailUITests` fails a note's save and a
/// share this way, and lets the flush the failed share starts through (batch B fix round 1, review
/// I-1). Every other item, and every read, delete and tag call, is untouched.
private struct FailingItemPatcher: ItemPatching {
    private let real = SupabaseItemPatcher()
    let failures: UITestWriteFailures

    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item {
        if failures.failsNextWrite(of: itemId) { throw URLError(.notConnectedToInternet) }
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

/// `--uitest-fail-item-writes`' budget: one count for the whole app, read from the launch arguments
/// once, because every editor the app makes (each sheet's, the app-scope flusher's) builds its own
/// patcher, and the writes to fail are counted across all of them.
private final class UITestWriteFailures: @unchecked Sendable {
    static let shared: UITestWriteFailures? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--uitest-fail-item-writes"), index + 2 < arguments.count,
              let itemId = UUID(uuidString: arguments[index + 1]), let count = Int(arguments[index + 2])
        else { return nil }
        return UITestWriteFailures(itemId: itemId, count: count)
    }()

    private let itemId: UUID
    private let lock = NSLock()
    private var remaining: Int

    private init(itemId: UUID, count: Int) {
        self.itemId = itemId
        remaining = count
    }

    /// Whether this write of `itemId` fails: one of the item's first `count` writes.
    func failsNextWrite(of itemId: UUID) -> Bool {
        guard itemId == self.itemId else { return false }
        return lock.withLock {
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
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
    /// The saves that failed since the last one that worked — what "Couldn't save — try again."
    /// reports (batch B fix round 1, review I-1). Its values stay queued, so a later write can
    /// deliver them; once every one has landed, the error goes (`settleSaveCaption`).
    var failedSaves: [FailedSave] = []
    /// Set when the sheet goes away: from then on its debounced autosaves stay quiet and the
    /// dismiss-time journal + flush own anything unsaved (plan 15, H5).
    var isClosed = false
    /// A rich note's box bookkeeping (StashKit's `RichNoteBox.Ledger`; batch B). `removed` is
    /// everything taken off the start of the box so far, append-only (fix round 2): a note save
    /// notes it as it takes the box's text, and when the save lands only what is still there of its
    /// text leaves the box. `queued` holds the documents the sheet queued from the box without seeing
    /// them land, the journal's drafts and failed saves: once the sheet shows one, its text leaves
    /// the box (`reconcileNotesDraft`). A failed save's document used to be forgotten, so the
    /// sheet's own flush delivered it, the sheet showed it, and the next Done appended the text again.
    var richNote = RichNoteBox.Ledger()
    /// `pendingEdits.deliveryCount` when the sheet last READ the server's row (fix round 2, 4e
    /// re-review M-4; batch B fix round 2, re-review N-1): set as the sheet opens and at every server
    /// row it adopts, and nowhere else — a carried toggle or save leaves it. Whatever the queue
    /// delivered after it, `snapshot` doesn't show, and the delivered ledger does: a failed toggle
    /// (`undoingFailedToggle`) and the save error (`haveLanded`) read those fields from the ledger.
    var knownDeliveries: Int
    /// The patches of this sheet's saves whose PATCH hasn't returned, by save generation — the
    /// `sending` of `ItemDetailView.fieldEdits` (Task 4e, 4d review P-1). A flush queued ahead of
    /// one of them can deliver its value and confirm it before the save's turn; a field the save
    /// carries must still stay as the user left it when that row arrives.
    var sending: [Int: ItemPatch] = [:]
    /// The text fields typed into since the field autosave last ran — the `typedSinceSave` of
    /// `ItemDetailView.fieldEdits` (Task 4e fix round 1, review M-1): what is still in the debounce,
    /// recorded nowhere yet, so a flushed row arriving meanwhile must not replace it. The field
    /// bindings add to it; `saveChangedFields` empties it as it records (a field it leaves out
    /// needs no save, and must take a server value again).
    var typedSinceSave: Set<SheetTextField> = []
    /// The title as the user last typed, pasted or dictated it into the field (Task 4e, 4d review
    /// N-3): `keepTitleOnOneLine` resolves only a change that came from the field — never a title
    /// the server sends while the field has focus.
    var typedTitle: String?

    init(item: Item, userId: UUID) {
        editor = DetailEditorFactory.make()
        let queue = PendingEdits.shared(for: userId)
        pendingEdits = queue
        notesModel = NotesEditorModel(item: item)
        knownDeliveries = queue.deliveryCount
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
    /// One shared enum-keyed `@FocusState` for every text input (final wave, item B — see
    /// `DetailField`'s own doc comment). Threaded down through `ItemDetailContent` and
    /// `SharingSection` as a `FocusState<DetailField?>.Binding`; the footer's hide-keyboard control
    /// needs "is ANY of title/description/notes/sticky note focused" and "clear whichever one is".
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
    /// server. The queue holds every save from the moment it starts until the server confirms it —
    /// or a flush ahead of the save delivers it; the sheet's saves still on their way (`sending`)
    /// cover that gap (Task 4e, 4d review P-1), and so does what was typed and is still in the
    /// autosave's debounce (`typedSinceSave`, fix round 1, review M-1).
    private var fieldEdits: DetailFieldEdits {
        DetailFieldEdits(local: item, baseline: baseline, queued: services.pendingEdits.edit(for: item.id),
                         sending: Array(services.sending.values), typedSinceSave: services.typedSinceSave)
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
                HStack(spacing: 12) {
                    DetailEyebrow(item: item)
                    closeButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(StashColor.ink)
                ScrollView {
                    // Every child below carries its own explicit top gap (the sheet's 14/24
                    // rhythm); `ItemDetailContent`/`DetailsDrawer`/`SharingSection` each open with
                    // a `SectionHeader`, which supplies its own `DetailLayout.section` gap.
                    VStack(alignment: .leading, spacing: 0) {
                        titleField
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
                                       focus: $focusedField, setPublic: setPublic)
                    }
                    .padding(.horizontal, DetailLayout.inset)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
                footerBar
            }
            .background(StashColor.surface.ignoresSafeArea())
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
        // A write of this item landed (batch B fix round 1, review I-1): a flush whose rows this
        // sheet's store never hands it (the app's refresh, under an Ask citation sheet) can deliver a
        // save that failed in front of the user. Adopt those delivered fields as the baseline too,
        // preserving edits still being typed or sent, so a later revert is measured against what
        // actually reached the server rather than the citation's stale row.
        .onReceive(NotificationCenter.default.publisher(for: .stashPendingEditDelivered)) { note in
            guard note.userInfo?["itemId"] as? UUID == item.id else { return }
            if let received = DetailFieldEdits.receivingDeliveries(local: item, snapshot: snapshot,
                                                                   knownDeliveries: services.knownDeliveries,
                                                                   queue: services.pendingEdits,
                                                                   sending: Array(services.sending.values),
                                                                   typedSinceSave: services.typedSinceSave) {
                adopt(received.row, fields: received.fields, isServerRow: false)
            } else {
                settleSaveCaption()
            }
        }
        // Leaving the foreground with the sheet still open (app switcher, lock, Control Center):
        // queue what's unsaved now. `.inactive` too — a kill from the app switcher isn't
        // guaranteed to deliver `.background` first. The next foreground refresh sends it. The
        // sheet stays open, so a share still in flight is left to its own PATCH (Task 4d).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, !isDeleted { journalUnconfirmedEdits(closing: false) }
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
            .background(focusedField == .title ? StashColor.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    // 1pt (was 2pt) — matches every other hairline/focus stroke on the sheet.
                    .strokeBorder(focusedField == .title ? StashColor.ink : Color.clear, lineWidth: 1)
            )
            .overlay {
                if focusedField == .title {
                    Rectangle().stroke(StashColor.spot, lineWidth: 3).padding(-2).allowsHitTesting(false)
                }
            }
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
            .background(focusedField == .description ? StashColor.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    // 1pt (was 2pt) — matches every other hairline/focus stroke on the sheet.
                    .strokeBorder(focusedField == .description ? StashColor.ink : Color.clear, lineWidth: 1)
            )
            .overlay {
                if focusedField == .description {
                    Rectangle().stroke(StashColor.spot, lineWidth: 3).padding(-2).allowsHitTesting(false)
                }
            }
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
                CardImageMosaic(height: 224)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 384)
        .clipShape(RoundedRectangle(cornerRadius: StashRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: StashRadius.object).strokeBorder(StashColor.line, lineWidth: 1))
        .stashCardShadow()
        .padding(14)
        .background { StashDotGrid() }
        .accessibilityIdentifier("detail.heroImage")
    }

    private var hairline: some View {
        Rectangle().fill(StashColor.ink).frame(height: 1)
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
                .foregroundStyle(StashColor.white)
                .frame(width: 28, height: 28)
                .background(StashColor.ink)
                .overlay(Rectangle().strokeBorder(StashColor.white.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.stashPlain)
        .stashIconControl("Close", systemImage: "xmark")
        .accessibilityIdentifier("detail.done")
        // VoiceOver first (2b review N-9): as the ZStack's last child it is otherwise reached
        // late. Unverified by UI tests — XCUITest's snapshot keeps its own order — so it's on the
        // device VoiceOver check.
        .accessibilitySortPriority(1)
    }

    /// Pinned footer bar (hairline top): "Delete item" left, autosave status + hide-keyboard
    /// right — port of `EditItemSheet.tsx`'s footer, plus (final wave, F7) the sheet's one
    /// keyboard-dismiss control: a pinned SIBLING below the ScrollView, so it's reachable whichever
    /// of the sheet's text inputs (`DetailField`: title, description, notes, sticky note) is
    /// focused, wherever the sheet is scrolled.
    ///
    /// Plan 16: at the accessibility sizes the autosave line moves under "Delete item" (a row of
    /// its own, full width) instead of squeezing beside it; below them the row is as before, the
    /// caption wrapping onto a second line if it must. Task 4d (2b review M-3): at those sizes the
    /// line is there only while it says something that matters. The resting "Changes saved
    /// automatically" took two more lines under Delete, and the pinned footer about a fifth of the
    /// screen at AX3. Task 4e (4d review B-3): there, "Saving…" is a spinner in the Delete row
    /// (`savingIndicator`). As a line under Delete it grew the footer ~400 ms into every pause in
    /// typing and took it away again — covering the bottom of what was being typed, and moving it.
    /// An error still takes the line under Delete: it stays until something changes, and matters.
    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        deleteButton
                        Spacer(minLength: 8)
                        if saveStatus == .saving, dynamicTypeSize < .accessibility4 {
                            savingIndicator
                        }
                        dismissKeyboardButton
                    }
                    // The row is at least its controls' 44 pt, and the spinner never taller, so a
                    // save never changes the row's height (Task 4e).
                    .frame(minHeight: 44)
                    if case .failed = saveStatus {
                        autosaveLabel
                    }
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
                    .stashFont(.secondary)
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("detail.deleteError")
            }
        }
        .padding(.horizontal, DetailLayout.inset)
        .padding(.vertical, 10)
        .background(StashColor.surface)
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

    /// "Saving…" at the accessibility sizes (Task 4e, 4d review B-3): a spinner in the Delete row,
    /// before the hide-keyboard control, so the pinned footer keeps its height while a save is on
    /// its way. It takes the caption's identifier, and VoiceOver reads it as "Saving…". The
    /// spinner scales with the text size (43.7 pt at AX3), so its layout is capped at the row's
    /// 44 pt: uncapped, it made the row 1.3 pt taller at AX3 — measured — and the footer moved.
    ///
    /// Only up to AX3 (fix round 1, review M-3). At AX5 — measured on iOS 17.0 — "Delete item" is
    /// 274 pt wide and the hide-keyboard control 44, so the row needs 326 pt without a spinner and
    /// ~376 with one: it overflowed even a 393 pt-wide phone, and "Delete item" moved 10 pt left
    /// while it saved. The narrowest supported phone (375 pt) has 335 inside the insets — no room
    /// for any spinner, `.controlSize(.small)` included. At AX3 the row with it needs ~303 pt.
    /// So at AX4 and AX5 there is no "Saving…"; an error still shows under Delete.
    private var savingIndicator: some View {
        ZStack { StashCursor() }
            .foregroundStyle(StashColor.muted)
            .frame(maxWidth: 44, maxHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saving…")
            .accessibilityIdentifier("detail.autosave")
    }

    /// `.failed` (final wave, item D) renders as its own `detail.autosave.error` identifier in
    /// `StashColor.destructive`, distinct from the resting `detail.autosave` identifier every
    /// other state shares — so a UI test (or VoiceOver user) can tell "saved" and "failed, please
    /// retry" apart without parsing label text. Plan 16: `meta`, and the resting caption `muted`
    /// (it was `faint`, 2.79:1).
    @ViewBuilder private var autosaveLabel: some View {
        if case .failed(let message) = saveStatus {
            Text(message)
                .stashFont(.secondary)
                .foregroundStyle(StashColor.destructive)
                .accessibilityIdentifier("detail.autosave.error")
        } else {
            StashStatusLine(text: saveStatus == .saving ? "saving…" : "changes save automatically",
                            busy: saveStatus == .saving)
                .foregroundStyle(StashColor.muted)
                .accessibilityIdentifier("detail.autosave")
        }
    }

    // MARK: - Field bindings (title/description autosave)

    private var titleBinding: Binding<String> {
        Binding(get: { item.title ?? "" }, set: { newValue in
            services.typedTitle = newValue
            services.typedSinceSave.insert(.title)
            item.title = newValue
            scheduleFieldSave()
        })
    }

    /// Plan 16: the title field wraps (`axis: .vertical`), but a title is one line of text. A
    /// vertical-axis field inserts a line break on Return, so while the user is typing in it the
    /// change is resolved by what it inserted (StashKit's `OneLineTitleEdit`, 2b review I-1): a
    /// bare Return — over a selection too — leaves the title as it was and ends editing, as the
    /// single-line field did; a Return that also accepted an autocorrection keeps the correction
    /// and ends editing; a pasted line break becomes a space. The line break is only ever on
    /// screen for the one update this takes — the 400 ms autosave never sees it.
    ///
    /// Only a change that came from the field is resolved (`services.typedTitle`, Task 4e — 4d
    /// review N-3). A title the server sends while the field has focus (an AI title, another
    /// device) is shown as the server has it: resolved here, one ending in a line break ended
    /// editing under the user's fingers, and the sheet then wrote its one-line copy back as if the
    /// user had typed it. The user's own next edit of such a title still makes it one line.
    private func keepTitleOnOneLine(was oldTitle: String?, now newTitle: String?) {
        guard focusedField == .title, newTitle == services.typedTitle,
              let edit = OneLineTitleEdit.resolve(old: oldTitle, new: newTitle) else { return }
        item.title = edit.title
        if edit.endsEditing { focusedField = nil }
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { item.description ?? "" }, set: { newValue in
            services.typedSinceSave.insert(.description)
            item.description = newValue
            scheduleFieldSave()
        })
    }

    /// Sticky-note text (`SharingSection`) rides the same debounced field-autosave path as
    /// title/description — `saveChangedFields` measures it against `baseline` and the queue.
    private var supplementalNoteBinding: Binding<String> {
        Binding(get: { item.supplementalNote ?? "" }, set: { newValue in
            services.typedSinceSave.insert(.supplementalNote)
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
    /// (writes to one item finish in order, so that's the newest). Returns how the save ended
    /// (below).
    ///
    /// `send` replaces the plain PATCH of `patch` — a location edit is written onto the server's
    /// current attributes instead (`saveAttributes`); `patch` is still what gets queued.
    ///
    /// Plan 16 (review I-1, Task 4c m-3): the landing is StashKit's `DetailFieldEdits.landing`, in
    /// its one safe order. When the save lands after the user changed a field it sent — e.g.
    /// cleared "Gro" inside the next debounce, so no newer save has queued the clear yet — the
    /// field's value is queued before `adopt` reads the queue (not once the sheet has closed: its
    /// journal already did). The confirm then keeps it, the list row is laid over what is still
    /// queued, `adopt` keeps the field as it is, and the next autosave (or the close) sends it.
    ///
    /// Task 4d: captures come from the queue's strictly increasing clock (`captureTime`), and the
    /// PATCH goes out through `PendingEdits.send`, which at its turn leaves out any field a write
    /// that landed first (a flush) already put on the server with a later capture — so a save
    /// made before a close, a reopen and a retype never lands over the retyped value (review P-3).
    ///
    /// Task 4e (4d review A-2, B-1, P-1): the result is one of three outcomes (`DetailSaveOutcome`).
    /// - `.landed(row)`: the PATCH went out.
    /// - `.alreadyDelivered`: nothing was left to send — a flush queued ahead of the save delivered
    ///   every field already. That is saved, and it lands like any save, against the values the
    ///   flush delivered (`DetailFieldEdits.landing(_:capturedAt:local:snapshot:…)`): a field the
    ///   user moved on from meanwhile is queued, and a sheet whose store never sees the flush's row
    ///   (an Ask citation sheet) learns what the server holds. Read as "not saved", it left a rich
    ///   note's paragraph in the box, to be appended a second time (A-2).
    /// - `.failed`.
    /// While the PATCH is on its way, the sheet keeps the patch in `services.sending`: if a flush
    /// ahead delivers the value first, its row must not overwrite a field the user has since moved
    /// on from (P-1, `fieldEdits`).
    ///
    /// Fix round 1 (review C-1): a save that lands while a newer one has started isn't adopted — the
    /// newest decides the fields — but what it put on the server is carried into the sheet at once
    /// (`DetailFieldEdits.carrying`): its fields into `snapshot`, its note document into the fields
    /// too. The newest save may have nothing left to send and land against `snapshot`, and an Ask
    /// citation sheet's store never hands it a flushed row; skipped, a note saved under a newer
    /// title edit landed unseen, left the box, and the next note — appended to the old document —
    /// deleted it from the server.
    @MainActor
    private func save(_ patch: ItemPatch, send: ((Date) async throws -> Item)? = nil) async -> DetailSaveOutcome {
        let pendingEdits = services.pendingEdits
        let capturedAt = pendingEdits.captureTime()
        pendingEdits.record(itemId: item.id, patch: patch, capturedAt: capturedAt)
        let generation = services.nextGeneration()
        services.savesInFlight += 1
        services.sending[generation] = patch
        saveStatus = .saving
        var sheetSave: SheetSave?
        do {
            let itemId = item.id
            let editor = services.editor
            if let send {
                let row = try await send(capturedAt)
                sheetSave = SheetSave(item: row, patch: patch, serverHolds: patch)
            } else {
                sheetSave = try await pendingEdits.send(patch, capturedAt: capturedAt, itemId: itemId, editor: editor)
            }
        } catch {
            sheetSave = nil
        }
        services.sending[generation] = nil
        var outcome = DetailSaveOutcome.failed
        if let sheetSave {
            let landed = DetailFieldEdits.landing(sheetSave, capturedAt: capturedAt, local: item, snapshot: snapshot,
                                                  queue: pendingEdits, sheetIsOpen: !services.isClosed,
                                                  at: pendingEdits.captureTime(), sending: Array(services.sending.values),
                                                  typedSinceSave: services.typedSinceSave, apply: store.applyDetail)
            if services.isLatest(generation) {
                adopt(landed.row, fields: landed.fields, isServerRow: sheetSave.item != nil)
            } else {
                let carried = DetailFieldEdits.carrying(sheetSave, landed: landed, local: item, snapshot: snapshot)
                item = carried.local
                snapshot = carried.snapshot
                reconcileNotesDraft(with: carried.snapshot)
            }
            outcome = DetailSaveOutcome(sheetSave)
        }
        if outcome == .failed {
            services.failedSaves.append(FailedSave(patch: patch, capturedAt: capturedAt))
        } else {
            services.failedSaves.removeAll()
        }
        services.lastSaveFailed = outcome == .failed
        services.savesInFlight -= 1
        if services.savesInFlight == 0 {
            saveStatus = services.lastSaveFailed ? .failed("Couldn't save — try again.") : .saved
            // The sheet's server row may hold it already: a realtime echo of this PATCH whose
            // response was lost (batch B fix round 1).
            settleSaveCaption()
        }
        return outcome
    }

    /// "Couldn't save — try again." reports the saves that failed since the last one that worked
    /// (`services.failedSaves`). Once every one of them has landed, the error has nothing left to
    /// report, and the caption goes back to "Changes saved automatically" (batch B fix round 1,
    /// review I-1). Landed means a write delivered each field, or a newer value of it — the sheet's
    /// own Sharing flush, the app's refresh, a later save, or a Sharing toggle (an un-share removes
    /// the sticky note) — or what the server holds as far as the app knows already holds it: the
    /// sheet's last server row, with whatever the queue delivered after that row was read laid over
    /// it (`DetailFieldEdits.haveLanded`). Checked wherever that can change: as a save fails, as a
    /// row is adopted, and as the queue says a write of the item landed (`.stashPendingEditDelivered`).
    ///
    /// It used to be checked only in `adopt`, for "nothing left queued for the item". A flush hands
    /// its row to `adopt` before it updates the queue's entry, so the error stayed up over a note the
    /// flush had just delivered, with the box empty under it, and nothing checked again.
    ///
    /// Fix round 2: the row alone used to vouch, though the queue may have delivered the field since
    /// it was read (re-review N-1: a revert to "Y" that failed right after the app's refresh
    /// delivered "Z" read as saved); and a toggle's PATCH went out past the queue's ledger, so an
    /// un-share that removed a sticky note whose save failed left the error up with nothing to retry
    /// (N-2).
    private func settleSaveCaption() {
        guard case .failed = saveStatus, services.savesInFlight == 0,
              DetailFieldEdits.haveLanded(services.failedSaves, snapshot: snapshot,
                                          knownDeliveries: services.knownDeliveries, queue: services.pendingEdits)
        else { return }
        services.failedSaves.removeAll()
        services.lastSaveFailed = false
        saveStatus = .saved
    }

    /// The debounced field autosave (400ms after the last title/description/sticky keystroke).
    /// Naturally idempotent — nothing unsaved (`DetailFieldEdits.textPatch`) is a no-op. Marked
    /// @MainActor deliberately: it's reached through `Debouncer`, its own (non-Main) actor, whose
    /// internal `Task` doesn't inherit the main actor. Quiet once the sheet has closed — the
    /// dismiss-time journal + flush own anything still unsaved then.
    ///
    /// Fix round 1 (review M-1): what was typed leaves the debounce here, so the typed-since-save
    /// flags are cleared as the patch is recorded (`save` records before it first waits). A field
    /// the patch leaves out needs no save — it equals the server's value and nothing is queued — and
    /// must take a server value again (an AI title, say); one it carries is protected by the queue.
    @MainActor
    private func saveChangedFields() async {
        guard !services.isClosed else { return }
        services.typedSinceSave.removeAll()
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
    /// (`PendingEdits.sendLocation` — read in the item's write slot, only `location` replaced,
    /// with the successful write recorded in the delivered ledger). The
    /// sheet's blob can be minutes old while production writes `attributes` asynchronously (the
    /// transcription job's `media.transcript`, enrichment's `enrichment.*`); PATCHing it whole
    /// rolled those back and re-queued enrichment.
    @MainActor
    private func saveAttributes(_ attributes: ItemAttributes) async {
        guard !services.isClosed else { return }
        let itemId = item.id
        let location = attributes.location
        let editor = services.editor
        let pendingEdits = services.pendingEdits
        _ = await save(ItemPatch(attributes: attributes)) { capturedAt in
            try await pendingEdits.sendLocation(location, capturedAt: capturedAt, itemId: itemId, editor: editor)
        }
    }

    /// L5: the Sharing toggle flips at once (optimistic) and bumps the save generation like every
    /// other save. It is not written ahead to `PendingEdits`. Un-sharing an item with a sticky note
    /// clears the note in the same PATCH (the section asks first). The footer caption is left to
    /// the autosaves (`save(_:)`) — this toggle reports in its own section, and never sets or
    /// strands "Saving…" (plan 15 review). Returns whether the switch can stay where the user put
    /// it — false means `SharingSection` shows its error.
    ///
    /// - Landing goes through `DetailFieldEdits.landing`, like every save: the confirm — which
    ///   drops a note queued before an un-share — comes before the list row is laid, so the list
    ///   never keeps showing the dropped note (Task 4d, review m-1).
    /// - Failing goes through `DetailFieldEdits.undoingFailedToggle` (Task 4d, review P-4 and F1).
    ///   The switch shows what the server holds as far as the sheet knows (its last server row) —
    ///   normally the old value, with a failed un-share's note back (Task 4c) — and
    ///   `SharingSection` shows its inline error, unless that row already holds what the user
    ///   asked for. The queue is settled to match the switch: left on, any other Sharing value
    ///   queued is taken back; left off, private is queued again (Task 4e, 4d review A-3 and B-2),
    ///   because that row can be wrong the dangerous way — an Ask citation sheet never sees a flush
    ///   that published the item underneath it, and a share can reach the server while its
    ///   response is lost. So a share the user saw fail is never left published past the next
    ///   flush; the cost is one PATCH of a value the server usually holds already. If the sheet has
    ///   closed meanwhile (the PATCH outlives it), nothing changes: the close journaled the toggle
    ///   the user last saw, and its flush retries it (plan 15).
    /// - Fix round 1 (review M-2): with the sheet open, that flush starts at once — one attempt. If
    ///   it gets through, an item published underneath the sheet is private again right away; if it
    ///   fails too (a dead link is the usual reason the toggle failed), private goes out at the close
    ///   or the app's next refresh, as before. A share made on another device before it lands is
    ///   undone by it (privacy first). The sheet adopts the row it delivers (fix round 2).
    /// - Fix rounds 1–2 (review M-4): for a failed SHARE, "what the server holds" is what the app
    ///   knows of it — the sheet's last server row, or a Sharing value the app's queue delivered
    ///   after that row was read (`services.knownDeliveries`), in whatever order that happened.
    ///   A sheet opened on a queued un-share that a flush delivered, then turned on, shows private
    ///   and the error when the share fails. It is never left on, with no error, over an item the
    ///   app made private — except inside the read-to-adopt window `adopt` documents, where the
    ///   server still stays private. A failed UN-share is never turned back on by a share the queue
    ///   delivered: over one, it settles off with no error, and the item is public until the
    ///   re-asserted private lands (above).
    /// - Batch B fix round 2 (re-review N-2): the PATCH goes out through the queue's write slot, as
    ///   before, and lands in its delivered ledger like every other write of the item
    ///   (`PendingEdits.sendToggle`; still never written ahead). An un-share that removes a sticky
    ///   note whose save failed is the newer value of the note, so "Couldn't save — try again." goes
    ///   once it lands; and a later failed toggle finds this one among the queue's deliveries.
    /// - A toggle that lands while a newer save has started isn't adopted, but the sheet's last
    ///   server row takes its fields (`DetailFieldEdits.carryingToggle`, fix round 2 of 4e; in
    ///   StashKit and tested since batch B). The reference stays where the last row read put it:
    ///   the ledger shows the toggle as delivered after it. (It used to move on to the queue's count
    ///   here, which hid any other field the queue had delivered since the row was read.)
    @MainActor
    private func setPublic(_ isPublic: Bool) async -> Bool {
        let pendingEdits = services.pendingEdits
        let noteBefore = item.supplementalNote
        let patch = services.editor.togglePublic(item: item, to: isPublic)
        item.isPublic = isPublic
        if patch.supplementalNote == "" { item.supplementalNote = nil }
        let capturedAt = pendingEdits.captureTime()
        let generation = services.nextGeneration()
        do {
            let saved = try await pendingEdits.sendToggle(patch, capturedAt: capturedAt, itemId: item.id,
                                                          editor: services.editor)
            let landed = DetailFieldEdits.landing(patch, capturedAt: capturedAt, as: saved, local: item,
                                                  baseline: baseline, queue: pendingEdits,
                                                  sheetIsOpen: !services.isClosed, at: pendingEdits.captureTime(),
                                                  sending: Array(services.sending.values),
                                                  typedSinceSave: services.typedSinceSave, apply: store.applyDetail)
            if services.isLatest(generation) {
                adopt(saved, fields: landed)
            } else {
                // A newer save has started: the sheet's last server row still takes the toggle's
                // fields (the carry), so a later failed toggle settles on them. The reference stays
                // put: the ledger shows the toggle as delivered after the row was read.
                snapshot = DetailFieldEdits.carryingToggle(patch, snapshot: snapshot)
            }
            return true
        } catch {
            let sheetIsOpen = !services.isClosed
            item = DetailFieldEdits.undoingFailedToggle(to: isPublic, noteBefore: noteBefore,
                                                        knownDeliveries: services.knownDeliveries,
                                                        local: item, baseline: baseline, queue: pendingEdits,
                                                        sheetIsOpen: sheetIsOpen, at: pendingEdits.captureTime())
            if sheetIsOpen, !item.isPublic {
                // Private was queued again: send it now, not at the close or the app's next
                // refresh (fix round 1, review M-2). The sheet adopts the row it delivers (fix
                // round 2): the flush sends whatever else is queued too — a failed save's "Y" — and
                // an Ask citation sheet's store never hands it that row, so a later revert to the
                // old value was measured against a stale row and never sent.
                let itemId = item.id
                let editor = services.editor
                let store = store
                let services = services
                Task { @MainActor in
                    await pendingEdits.flush(editor: editor, itemIds: [itemId]) { row in
                        store.applyDetail(row)
                        if !services.isClosed { adopt(row) }
                    }
                }
            }
            return item.isPublic == isPublic
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
    ///
    /// Task 4e (4d review A-2): the bookkeeping runs whenever the text IS saved — `.landed`, and
    /// `.alreadyDelivered` (a flush queued ahead delivered this very document first). It used to
    /// run only when the save returned a row, so a rich draft "abc" stayed in the box after the
    /// flush had delivered it; " def" added later went out as a new paragraph "abc def" — the
    /// note's text in the document twice, and a rich note can't be edited on iOS.
    ///
    /// Fix round 2 (4e re-review): saves can overlap — Done with "abc" on a slow link, " def"
    /// typed, Done again — so a landing takes off the box only what of its text is still there
    /// (`takeSavedText`); and every landed save brings its document into the sheet, so the next
    /// note is built on it.
    ///
    /// Batch B (4e re-review 2): a rich note's save that FAILED is kept (`RichNoteBox.Ledger.failed`)
    /// — its document stays queued, and a later write delivers it: the flush `setPublic` starts, the
    /// app's refresh, or a realtime echo of this very PATCH whose response was lost. Once the sheet
    /// shows that document, the text leaves the box (`reconcileNotesDraft`), checked at once against
    /// the document already shown. Forgotten, the text stayed in the box while the sheet showed it,
    /// and the next Done appended it a second time.
    @MainActor
    private func flushNotes() async {
        guard !services.isClosed else { return }
        let notes = services.notesModel
        guard notes.isRich ? notes.draft != notes.savedDraft : plainNote.needsSave else { return }
        let typed = notes.draft
        let removedAtSave = services.richNote.removed
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
        let isSaved = await save(ItemPatch(content: newContent)).isSaved
        if notes.isRich {
            if isSaved {
                takeSavedText(typed, removedAt: removedAtSave)
            } else if let box = services.richNote.failed(typed, document: newContent, removedAt: removedAtSave,
                                                         shown: item.content, box: notes.draft) {
                notes.draft = box
                notes.savedDraft = ""
            }
        } else if isSaved {
            notes.savedDraft = typed
        }
    }

    /// A rich note's save of `typed` — the box's text when the save took it, with
    /// `services.richNote.removed` at `removedAt` then — is saved: what of `typed` is still at the
    /// box's start leaves it, anything typed after stays (`RichNoteBox.Ledger.saved`; fix round 2,
    /// 4e re-review). What earlier landings took off the box since is gone already: two
    /// overlapping saves ("abc", then "abc def") used to leave "def" behind, and the next Done
    /// appended it a second time.
    private func takeSavedText(_ typed: String, removedAt: String) {
        let notes = services.notesModel
        notes.draft = services.richNote.saved(typed, removedAt: removedAt, box: notes.draft)
        notes.savedDraft = ""
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
    ///
    /// Task 4d (review P-4): a share still in flight is queued only when the sheet is `closing` —
    /// never when the app merely leaves the foreground with the sheet open, where a failure would
    /// flip the switch back in front of the user while the queued copy published the item anyway
    /// (`DetailFieldEdits.journaledSharing`). Task 4e (4d review A-1): the Sharing value counts as
    /// unconfirmed when it differs from a queued one too — a sheet opened on a queued share and
    /// turned off journals the off, which the old rule (off equals the server's value) left out, so
    /// the queued share was published by the next flush.
    private func unconfirmedPatch(closing: Bool) -> (patch: ItemPatch, richDraft: (typed: String, content: String)?) {
        var patch = fieldEdits.textPatch
        patch.isPublic = fieldEdits.journaledSharing(closing: closing)
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

    /// Writes `unconfirmedPatch(closing:)` to the durable queue, synchronously.
    private func journalUnconfirmedEdits(closing: Bool) {
        let (patch, richDraft) = unconfirmedPatch(closing: closing)
        guard !patch.isEmpty else { return }
        services.pendingEdits.record(itemId: item.id, patch: patch, capturedAt: services.pendingEdits.captureTime())
        if let richDraft { services.richNote.journaled(richDraft.typed, document: richDraft.content) }
    }

    /// The sheet is gone (X, swipe, or programmatic): queue whatever the server hasn't confirmed —
    /// synchronously, before anything else can happen — and start sending it. Nothing here waits:
    /// the send runs in its own task, after any of this sheet's saves still in flight
    /// (`ItemWriteQueue`); if it fails, the entry stays queued for the next refresh.
    private func handleDismiss() {
        guard !isDeleted, !services.isClosed else { return }
        services.isClosed = true
        journalUnconfirmedEdits(closing: true)
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
    /// after sending "Gro", nor a " x" response a description the user put back — or while one of
    /// this sheet's saves is still sending it (Task 4e, 4d review P-1): a flush queued ahead of
    /// the save can deliver its "Y" and confirm it, and that row must not replace the "X" the user
    /// has typed back since — or while what the user typed is still in the autosave's debounce
    /// (fix round 1, review M-1: a failed autosave's "Y", or one another sheet left queued,
    /// delivered by a flush inside that debounce).
    ///
    /// Fix round 2: `isServerRow` — `incoming` was read from the server (not built from `snapshot`
    /// for a save with nothing left to send), and the sheet takes it as reflecting everything the
    /// queue had delivered when the row is ADOPTED (`services.knownDeliveries`): `setPublic`'s
    /// failure, and since batch B fix round 2 the save error's check, read every field delivered
    /// after that from the ledger. That is an approximation (batch B, 4e re-review 2): the ledger
    /// counts deliveries, not when a row was read, so one that lands between the row's read and this
    /// call counts as seen though the row predates it. The window is normally about one round trip
    /// wide. For the row a sheet opened on it can be longer (fix round 1, review m-3b, by reading):
    /// an Ask citation sheet's own saves and flushes update only its own store, and a library row
    /// stays the server's copy from before a delivery while other fields of the item are still
    /// queued. In it, a failed share can be left on with no error over an item a queued un-share
    /// made private; nothing publishes it — the server stays private — but the user is told nothing.
    /// And a failed save of a field such a delivery changed can lose its error when its value is
    /// what the stale row shows; it stays queued, and goes out at the close or the next refresh.
    /// Closing it would need a delivery number on every row.
    private func adopt(_ incoming: Item, fields: Item? = nil, isServerRow: Bool = true) {
        let next = fields ?? fieldEdits.adopting(incoming)
        snapshot = incoming
        item = next
        if isServerRow { services.knownDeliveries = services.pendingEdits.deliveryCount }
        reconcileNotesDraft(with: incoming)
        // A failed save this row — or the queue — has since delivered is no longer failed.
        settleSaveCaption()
    }

    /// Keeps the notes draft honest when the server's content catches up with it, once the caller
    /// has folded the row into the fields: a plain draft the server now holds counts as saved, and a
    /// rich note's text leaves the box once the document the sheet SHOWS is one it was queued as —
    /// the journal's draft or a failed save (batch B). Both choices are StashKit's
    /// (`RichNoteBox.Ledger.adopting`), handed the row as it arrived and the fields as they now
    /// stand (fix round 1, review m-2). Reading the row's document for a rich note lost one: a sheet
    /// opened on a queued note keeps its own copy over the row, and the next note, appended to that
    /// copy, replaced the server's document.
    private func reconcileNotesDraft(with incoming: Item) {
        let notes = services.notesModel
        let next = services.richNote.adopting(incoming, shown: item, isRich: notes.isRich,
                                              notes: NotesDraftState(draft: notes.draft, savedDraft: notes.savedDraft))
        if next.draft != notes.draft { notes.draft = next.draft }
        if next.savedDraft != notes.savedDraft { notes.savedDraft = next.savedDraft }
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
