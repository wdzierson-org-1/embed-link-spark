import Foundation
import Supabase

/// One field of a queued edit: the value the user left, and when it was read from the editor.
/// `capturedAt` is the latest-wins key — a value captured later always replaces an earlier one,
/// whatever order the two are recorded in.
public struct PendingField<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var value: Value
    public var capturedAt: Date

    public init(_ value: Value, capturedAt: Date) {
        self.value = value
        self.capturedAt = capturedAt
    }
}

/// Every detail-sheet edit to ONE item that the server hasn't confirmed yet (plan 15, H5).
///
/// Field values follow `ItemPatch`'s conventions: `content` is the whole value exactly as the
/// editor holds it (a TipTap JSON document stays TipTap JSON — never flattened); `supplementalNote
/// == ""` means "clear the sticky note". `attributes` is recorded only for a location edit; it is
/// the whole blob the sheet held, but only its `location` is ever applied — to list rows here and,
/// at flush time, onto whatever `attributes` the server holds then (`PendingEdits.flush`), so a
/// queued location can never write back an old copy of `media`/`link` keys the server changed
/// meanwhile.
public struct PendingEdit: Codable, Equatable, Sendable {
    public let itemId: UUID
    public var title: PendingField<String>?
    public var description: PendingField<String>?
    public var content: PendingField<String>?
    public var supplementalNote: PendingField<String>?
    public var isPublic: PendingField<Bool>?
    public var attributes: PendingField<ItemAttributes>?
    /// Failed flushes so far.
    public var attempts: Int
    /// Bumped by every `PendingEdits.record` that changed something — a flush compares it to tell
    /// whether newer values arrived while it was sending.
    public var revision: Int
    public var updatedAt: Date

    public init(itemId: UUID, updatedAt: Date) {
        self.itemId = itemId
        attempts = 0
        revision = 0
        self.updatedAt = updatedAt
    }

    /// Every field of `patch`, stamped `capturedAt`.
    init(itemId: UUID, patch: ItemPatch, capturedAt: Date) {
        self.init(itemId: itemId, updatedAt: capturedAt)
        merge(patch, capturedAt: capturedAt)
    }

    public var isEmpty: Bool {
        title == nil && description == nil && content == nil && supplementalNote == nil
            && isPublic == nil && attributes == nil
    }

    /// The queued title/description/content/sticky/sharing values as a patch. `attributes` is left
    /// out on purpose — see the type's doc comment and `PendingEdits.flush`.
    public var fieldPatch: ItemPatch {
        ItemPatch(title: title?.value, description: description?.value, content: content?.value,
                  supplementalNote: supplementalNote?.value, isPublic: isPublic?.value)
    }

    /// `item` as the user last left it: every queued value laid over the server's row.
    public func applied(to item: Item) -> Item {
        var result = item
        if let title { result.title = title.value }
        if let description { result.description = description.value }
        if let content { result.content = content.value }
        if let supplementalNote { result.supplementalNote = supplementalNote.value.isEmpty ? nil : supplementalNote.value }
        if let isPublic { result.isPublic = isPublic.value }
        if let attributes { result.attributes.location = attributes.value.location }
        return result
    }

    /// Latest-wins per field: each field of `patch` replaces the queued one unless the queued one
    /// was captured later. Returns whether anything changed.
    @discardableResult
    mutating func merge(_ patch: ItemPatch, capturedAt: Date) -> Bool {
        let before = self
        title = Self.newer(title, patch.title, capturedAt)
        description = Self.newer(description, patch.description, capturedAt)
        content = Self.newer(content, patch.content, capturedAt)
        supplementalNote = Self.newer(supplementalNote, patch.supplementalNote, capturedAt)
        isPublic = Self.newer(isPublic, patch.isPublic, capturedAt)
        attributes = Self.newer(attributes, patch.attributes, capturedAt)
        return self != before
    }

    /// Drops every field `sent` confirms: a field the server now holds is no longer pending, unless
    /// a NEWER, different value was recorded after `sent`'s was captured. Returns whether anything
    /// was dropped.
    @discardableResult
    mutating func removeSent(_ sent: PendingEdit) -> Bool {
        let before = self
        title = Self.stillPending(title, after: sent.title)
        description = Self.stillPending(description, after: sent.description)
        content = Self.stillPending(content, after: sent.content)
        supplementalNote = Self.stillPending(supplementalNote, after: sent.supplementalNote)
        isPublic = Self.stillPending(isPublic, after: sent.isPublic)
        if let current = attributes, let confirmed = sent.attributes,
           current.capturedAt <= confirmed.capturedAt || current.value.location == confirmed.value.location {
            attributes = nil
        }
        return self != before
    }

    private static func newer<Value: Codable & Equatable & Sendable>(
        _ existing: PendingField<Value>?, _ value: Value?, _ capturedAt: Date
    ) -> PendingField<Value>? {
        guard let value else { return existing }
        if let existing, existing.capturedAt > capturedAt { return existing }
        return PendingField(value, capturedAt: capturedAt)
    }

    private static func stillPending<Value: Codable & Equatable & Sendable>(
        _ current: PendingField<Value>?, after sent: PendingField<Value>?
    ) -> PendingField<Value>? {
        guard let current, let sent else { return current }
        return current.capturedAt <= sent.capturedAt || current.value == sent.value ? nil : current
    }
}

/// The durable queue of detail-sheet edits the server hasn't confirmed (plan 15, H5): what makes
/// closing the sheet instant without ever losing what the user typed.
///
/// - **Per user, on disk.** One JSON file per item under `AppGroup.userScopedURL("StashPendingEdits",
///   userId:)`, written atomically (`Data.write(options: .atomic)`) the moment an edit is
///   recorded, so a crash, a kill from the app switcher, or a relaunch days later still has it.
///   Another account's edits are never visible (separate directory). An unreadable file is
///   skipped and removed; the rest still load.
/// - **Write-ahead.** The sheet records each save's fields BEFORE sending them and confirms them
///   after the PATCH succeeds (`record` → PATCH → `confirm`); on dismiss it records whatever is
///   still unconfirmed (in flight, failed, or still in a debounce). Anything left here was never
///   confirmed by the server.
/// - **Latest wins per field** (`PendingField.capturedAt`), so recording an old value late can't
///   replace a newer one, and a confirmed save never drops a newer value typed after it.
/// - **Flush** (`flush(editor:)`) PATCHes each queued item through `ItemEditor.saveLatest` — after
///   any write to that item already in flight, with the newest queued values — and forgets what the
///   server confirmed. A failure keeps the entry (`attempts + 1`); an item that no longer exists
///   drops it. `ItemStore.refresh()` flushes before it fetches, so launch, foreground, View-tab
///   appear and pull-to-refresh all retry; a closing sheet flushes its own item at once.
/// - **Overlay.** `ItemStore` lays queued values over the rows it shows (`PendingEdit.applied(to:)`)
///   until they're confirmed, so the list never reverts to the server's older copy; `onChange`
///   tells it when to re-apply.
@MainActor
public final class PendingEdits {
    public static let formatVersion = 1

    public let userId: UUID
    public let directory: URL
    public private(set) var entries: [UUID: PendingEdit] = [:]
    /// Called with the affected item ids after every change (record, confirm, flush, discard).
    public var onChange: (@MainActor (Set<UUID>) -> Void)?

    private let now: () -> Date
    /// Who the app is signed in as at send time. A queued edit only ever goes out under its own
    /// user's session: a flush still waiting behind a stalled request when the account switches
    /// would otherwise be sent with the NEW account's token, match no row (RLS) and be dropped as
    /// if the item had been deleted.
    private let sessionUserId: @MainActor () -> UUID?
    private var flushing: Set<UUID> = []

    private struct NotSignedInAsOwner: Error {}

    private static var instances: [UUID: PendingEdits] = [:]

    /// The app's one queue for `userId` — the detail sheet and the app-scope `ItemStore` must share
    /// it, so a record in one is seen by the other at once.
    public static func shared(for userId: UUID) -> PendingEdits {
        if let existing = instances[userId] { return existing }
        let created = PendingEdits(userId: userId, directory: defaultDirectory(for: userId))
        instances[userId] = created
        return created
    }

    public static func defaultDirectory(for userId: UUID) -> URL {
        AppGroup.userScopedURL("StashPendingEdits", userId: userId)
    }

    /// `sessionUserId` defaults to the app's signed-in user (tests pass their own).
    public init(userId: UUID, directory: URL, now: @escaping () -> Date = Date.init,
                sessionUserId: (@MainActor () -> UUID?)? = nil) {
        self.userId = userId
        self.directory = directory
        self.now = now
        self.sessionUserId = sessionUserId ?? { StashClient.shared.auth.currentUser?.id }
        load()
    }

    // MARK: - Reading

    public var isEmpty: Bool { entries.isEmpty }

    public func edit(for itemId: UUID) -> PendingEdit? { entries[itemId] }

    /// `item` with any queued values laid over it.
    public func overlay(_ item: Item) -> Item {
        entries[item.id]?.applied(to: item) ?? item
    }

    // MARK: - Writing

    /// Queues `patch`'s fields for `itemId`, latest-wins per field, and writes the entry to disk
    /// before returning.
    public func record(itemId: UUID, patch: ItemPatch, capturedAt: Date) {
        guard !patch.isEmpty else { return }
        var edit = entries[itemId] ?? PendingEdit(itemId: itemId, updatedAt: now())
        guard edit.merge(patch, capturedAt: capturedAt) else { return }
        edit.revision += 1
        edit.updatedAt = now()
        store(edit)
    }

    /// A PATCH carrying `patch` (captured at `capturedAt`) succeeded: forget each of its fields
    /// unless a newer, different value was recorded since.
    public func confirm(itemId: UUID, patch: ItemPatch, capturedAt: Date) {
        guard var edit = entries[itemId],
              edit.removeSent(PendingEdit(itemId: itemId, patch: patch, capturedAt: capturedAt))
        else { return }
        store(edit)
    }

    /// Forgets everything queued for `itemId` (the item was deleted).
    public func discard(itemId: UUID) {
        guard entries.removeValue(forKey: itemId) != nil else { return }
        try? FileManager.default.removeItem(at: fileURL(for: itemId))
        onChange?([itemId])
    }

    // MARK: - Flush

    /// PATCHes every queued item (or just `itemIds`) with its newest values and forgets what the
    /// server confirmed; `apply` receives each saved row (to fold into a store) before its entry is
    /// updated. Items are sent concurrently; one already being flushed is skipped.
    ///
    /// A queued location is applied onto the row's CURRENT `attributes` (read inside the same
    /// per-item write slot), never written back as the stored blob — see `PendingEdit`.
    /// Failures keep the entry with `attempts + 1`; `ItemEditorError.itemNotFound` (the row is
    /// gone) drops it. Embeddings refresh after a text change through `ItemEditor`'s own
    /// `EmbeddingRefresher`.
    public func flush(editor: ItemEditor, itemIds: [UUID]? = nil,
                      apply: @escaping @MainActor @Sendable (Item) -> Void = { _ in }) async {
        let ids = (itemIds ?? Array(entries.keys)).filter { entries[$0] != nil && !flushing.contains($0) }
        guard !ids.isEmpty else { return }
        flushing.formUnion(ids)
        defer { flushing.subtract(ids) }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { @MainActor in await self.flushOne(id, editor: editor, apply: apply) }
            }
        }
    }

    private func flushOne(_ id: UUID, editor: ItemEditor, apply: @MainActor (Item) -> Void) async {
        // A second round only when newer values were recorded while the first was in flight.
        for _ in 0..<3 {
            let outcome: QueuedSave<PendingEdit>?
            do {
                outcome = try await editor.saveLatest(itemId: id) { [weak self] in
                    guard let self, let edit = self.entries[id], !edit.isEmpty else { return nil }
                    guard self.sessionUserId() == self.userId else { throw NotSignedInAsOwner() }
                    var patch = edit.fieldPatch
                    if let pending = edit.attributes {
                        guard let current = try await editor.currentAttributes(itemId: id) else {
                            throw ItemEditorError.itemNotFound
                        }
                        if current.location != pending.value.location {
                            var next = current
                            next.location = pending.value.location
                            patch.attributes = next
                        }
                    }
                    return (patch, edit)
                }
            } catch is NotSignedInAsOwner {
                return   // kept, untouched, for its own user's next session
            } catch ItemEditorError.itemNotFound where sessionUserId() == userId {
                discard(itemId: id)
                return
            } catch {
                if var edit = entries[id] {
                    edit.attempts += 1
                    store(edit, notify: false)
                }
                return
            }
            guard let outcome else { return }
            if let saved = outcome.item { apply(saved) }
            let sent = outcome.context
            guard var edit = entries[id] else { return }
            edit.removeSent(sent)
            edit.attempts = 0
            store(edit)
            guard let remaining = entries[id], remaining.revision != sent.revision else { return }
        }
    }

    // MARK: - Disk

    private struct Envelope: Codable {
        let version: Int
        let userId: UUID
        let edit: PendingEdit
    }

    public func fileURL(for itemId: UUID) -> URL {
        directory.appendingPathComponent("\(itemId.uuidString.lowercased()).json", isDirectory: false)
    }

    /// Keeps `edit` (or drops it when empty) in memory and on disk, then notifies.
    private func store(_ edit: PendingEdit, notify: Bool = true) {
        let id = edit.itemId
        let url = fileURL(for: id)
        if edit.isEmpty {
            entries[id] = nil
            try? FileManager.default.removeItem(at: url)
        } else {
            entries[id] = edit
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(Envelope(version: Self.formatVersion, userId: userId, edit: edit))
                try data.write(to: url, options: [.atomic])
            } catch {
                // Still queued in memory for this session (and still flushed); only a relaunch
                // before the next successful write could lose it.
                print("PendingEdits: couldn't write \(url.lastPathComponent): \(error)")
            }
        }
        if notify { onChange?([id]) }
    }

    private func load() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
            else {
                try? fileManager.removeItem(at: url)   // torn or garbage: nothing recoverable in it
                continue
            }
            guard envelope.version == Self.formatVersion, envelope.userId == userId,
                  envelope.edit.itemId == id, !envelope.edit.isEmpty
            else { continue }
            entries[id] = envelope.edit
        }
    }
}
