import Foundation
import os.log
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
    /// Sends the SERVER refused so far (reset by a successful send). Transport failures — offline,
    /// timed out — don't count: they must never delay or drop an edit (`PendingEdits.flush`).
    public var attempts: Int
    /// Not sent again before this — the exponential backoff after a refused send (nil = due now).
    public var nextAttemptAt: Date?
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

    /// Whether a flush may send this now (its backoff, if any, has passed).
    public func isDue(at date: Date) -> Bool {
        nextAttemptAt.map { $0 <= date } ?? true
    }

    /// The queued columns' names — for logs; never their values (the user's words stay private).
    public var fieldNames: [String] {
        [(title != nil, "title"), (description != nil, "description"), (content != nil, "content"),
         (supplementalNote != nil, "supplemental_note"), (isPublic != nil, "is_public"),
         (attributes != nil, "attributes.location")]
            .filter(\.0).map(\.1)
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
    ///
    /// Recording the value already queued again (the sheet re-journals everything unconfirmed on
    /// every dismiss and every trip to the background) is NOT a change — the queued field, its
    /// `capturedAt` included, stays as it is, so the entry's backoff isn't reset (final wave B). For
    /// `attributes` only the location counts, the one part ever applied.
    @discardableResult
    mutating func merge(_ patch: ItemPatch, capturedAt: Date) -> Bool {
        let before = self
        title = Self.newer(title, patch.title, capturedAt)
        description = Self.newer(description, patch.description, capturedAt)
        content = Self.newer(content, patch.content, capturedAt)
        supplementalNote = Self.newer(supplementalNote, patch.supplementalNote, capturedAt)
        isPublic = Self.newer(isPublic, patch.isPublic, capturedAt)
        if let queued = attributes, let incoming = patch.attributes, queued.value.location == incoming.location {
            // Same location: nothing to send that isn't queued already.
        } else {
            attributes = Self.newer(attributes, patch.attributes, capturedAt)
        }
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
        if let existing, existing.capturedAt > capturedAt || existing.value == value { return existing }
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
///   server confirmed. Only ever as the queue's own user with a valid token (`PendingEditsSession`),
///   and "the item is gone" is concluded only from a verified read. Offline/timeouts keep the entry
///   as it is (retried on the next flush, never backed off); a send the SERVER refuses backs off
///   exponentially and, after `maxRejections`, is dropped with an error log. `ItemStore.refresh()`
///   flushes before it fetches, so launch, foreground, View-tab appear and pull-to-refresh all
///   retry; a closing sheet flushes its own item at once.
/// - **Overlay.** `ItemStore` lays queued values over the rows it shows (`PendingEdit.applied(to:)`)
///   until they're confirmed, so the list never reverts to the server's older copy; `onChange`
///   tells it when to re-apply. A detail sheet starts from the same overlay (`sheetStart`).
@MainActor
public final class PendingEdits {
    public static let formatVersion = 1
    /// Refused sends before an edit is given up (with an error log).
    public static let maxRejections = 20
    /// Backoff after the n-th refused send: min(30 s × 2^(n−1), 6 h).
    public static func backoff(afterRejections rejections: Int) -> TimeInterval {
        min(30 * pow(2, Double(max(rejections - 1, 0))), 6 * 60 * 60)
    }

    public let userId: UUID
    public let directory: URL
    public private(set) var entries: [UUID: PendingEdit] = [:]
    /// Called with the affected item ids after every change (record, confirm, flush, discard).
    public var onChange: (@MainActor (Set<UUID>) -> Void)?

    private let now: () -> Date
    /// Who a send goes out as, and how "the item is gone" is proven — see `PendingEditsSession`.
    private let session: PendingEditsSession
    private var flushing: Set<UUID> = []

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

    /// `session` defaults to the app's own Supabase session (tests pass a stub).
    public init(userId: UUID, directory: URL, now: @escaping () -> Date = Date.init,
                session: PendingEditsSession = SupabasePendingEditsSession()) {
        self.userId = userId
        self.directory = directory
        self.now = now
        self.session = session
        load()
    }

    // MARK: - Reading

    public var isEmpty: Bool { entries.isEmpty }

    public func edit(for itemId: UUID) -> PendingEdit? { entries[itemId] }

    /// `item` with any queued values laid over it.
    public func overlay(_ item: Item) -> Item {
        entries[item.id]?.applied(to: item) ?? item
    }

    /// Where a detail sheet opened on `row` starts: `shown` — the row as the user last left it, with
    /// queued values laid over it (the sheet's fields and notes editor are seeded from this, so a
    /// new edit builds on a queued, undelivered note instead of silently replacing it) — and
    /// `server`, the server's own copy (the diff baseline, so queued values still count as
    /// unsaved). `row` may already be overlaid (a library card) or raw (an Ask citation, fetched
    /// straight from the server); `serverRow` is the store's server copy when it holds one.
    public func sheetStart(for row: Item, serverRow: Item?) -> (shown: Item, server: Item) {
        let server = serverRow ?? row
        return (overlay(server), server)
    }

    // MARK: - Writing

    /// Queues `patch`'s fields for `itemId`, latest-wins per field, and writes the entry to disk
    /// before returning. A genuinely new value makes the entry due again at once with a fresh
    /// refusal budget (`attempts` back to 0) — a new value gets a fresh send even while an older one
    /// was backing off. Re-recording values already queued changes nothing (see
    /// `PendingEdit.merge`): the sheet journals everything unconfirmed on every dismiss and every
    /// trip to the background, which must not defeat the backoff of an edit the server refuses.
    public func record(itemId: UUID, patch: ItemPatch, capturedAt: Date) {
        guard !patch.isEmpty else { return }
        var edit = entries[itemId] ?? PendingEdit(itemId: itemId, updatedAt: now())
        guard edit.merge(patch, capturedAt: capturedAt) else { return }
        edit.revision += 1
        edit.updatedAt = now()
        edit.nextAttemptAt = nil
        edit.attempts = 0
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

    /// PATCHes every queued item that is due (or just those of `itemIds`) with its newest values and
    /// forgets what the server confirmed; `apply` receives each saved row (to fold into a store)
    /// before its entry is updated. Items are sent concurrently; one already being flushed, or still
    /// backing off after a refused send, is skipped.
    ///
    /// - A send goes out only as the queue's own user with a currently valid token, checked inside
    ///   the item's write slot right before the PATCH (`PendingEditsSession.accessToken`). Signed
    ///   out or another account: the entry waits, untouched. No valid token right now (e.g. the
    ///   refresh can't reach the server): an ordinary failure — kept, not counted.
    /// - A queued location is applied onto the row's CURRENT `attributes` (read inside the same
    ///   slot), never written back as the stored blob — see `PendingEdit`.
    /// - Zero matched rows is NOT taken at its word: supabase-swift falls back to the anon key when
    ///   a token refresh fails, and RLS answers that with zero rows too. The entry is dropped as
    ///   "deleted" only when a read made with a verified token of this user finds no row.
    /// - Offline/timeouts keep the entry exactly as it is — never backed off, never counted —
    ///   so an edit goes out on the first flush after the network returns. A send the server
    ///   refuses counts: backoff min(30 s × 2^(n−1), 6 h), dropped with an error log after
    ///   `maxRejections`.
    /// - Embeddings refresh after a text change through `ItemEditor`'s own `EmbeddingRefresher`.
    public func flush(editor: ItemEditor, itemIds: [UUID]? = nil,
                      apply: @escaping @MainActor @Sendable (Item) -> Void = { _ in }) async {
        let due = now()
        let ids = (itemIds ?? Array(entries.keys)).filter {
            (entries[$0]?.isDue(at: due) ?? false) && !flushing.contains($0)
        }
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
                    _ = try await self.session.accessToken(for: self.userId)
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
            } catch PendingEditsSessionError.notSignedInAsOwner {
                return   // kept, untouched, for its own user's next session
            } catch ItemEditorError.itemNotFound {
                await settleNoMatchingRow(id)
                return
            } catch {
                if !Self.isTransient(error) { recordRejection(id) }
                return
            }
            guard let outcome else { return }
            if let saved = outcome.item { apply(saved) }
            let sent = outcome.context
            guard var edit = entries[id] else { return }
            edit.removeSent(sent)
            edit.attempts = 0
            edit.nextAttemptAt = nil
            store(edit)
            guard let remaining = entries[id], remaining.revision != sent.revision else { return }
        }
    }

    /// A send (or the attributes read) matched no row. Dropped as deleted only when a read made with
    /// a verified token of this queue's user agrees; if that can't be established, nothing is
    /// concluded — the entry stays exactly as it is.
    private func settleNoMatchingRow(_ id: UUID) async {
        do {
            let token = try await session.accessToken(for: userId)
            if try await session.rowExists(itemId: id, accessToken: token) {
                recordRejection(id)   // the row is there, yet the send matched nothing: refused
            } else {
                discard(itemId: id)
            }
        } catch {
            // Offline, signed out, or unverifiable: keep it for a later flush.
        }
    }

    /// The server refused a send: back off, and give up after `maxRejections`.
    private func recordRejection(_ id: UUID) {
        guard var edit = entries[id] else { return }
        edit.attempts += 1
        if edit.attempts >= Self.maxRejections {
            os_log(.error, "PendingEdits: dropping the queued edit for item %{public}@ after %d refused sends (fields: %{public}@)",
                   id.uuidString, edit.attempts, edit.fieldNames.joined(separator: ", "))
            discard(itemId: id)
            return
        }
        edit.nextAttemptAt = now().addingTimeInterval(Self.backoff(afterRejections: edit.attempts))
        store(edit, notify: false)
    }

    /// Couldn't reach the server (or gave up waiting): says nothing about the edit itself.
    static func isTransient(_ error: Error) -> Bool {
        error is URLError || error is CancellationError
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

// MARK: - Location writes (final wave B)

public extension ItemEditor {
    /// Saves a location edit ONTO THE ROW'S CURRENT `attributes`: the blob is read inside the item's
    /// write slot (after every earlier write to it has finished) and only its `location` is
    /// replaced — the same read-merge `PendingEdits.flush` applies to a queued location.
    ///
    /// Never the sheet's own copy of the blob: production writes `attributes` asynchronously
    /// (the transcription job's `media.transcript`/`media.kind`, enrichment's `enrichment.*`), so
    /// a copy read when the sheet opened can be minutes old, and writing it back would roll those
    /// keys back — and, since `media` and `enrichment.evidence` changes trigger
    /// `enqueue_enrichment_assessment`, re-queue enrichment too. (The read and the PATCH are two
    /// requests, so a server write landing between them can still be lost — a much smaller window
    /// than the sheet's lifetime; closing it needs a server-side jsonb merge.)
    ///
    /// Throws `ItemEditorError.itemNotFound` when the row can't be read.
    func saveLocation(itemId: UUID, location: CapturedLocation?) async throws -> Item {
        let outcome = try await saveLatest(itemId: itemId) { [self] in
            guard var attributes = try await currentAttributes(itemId: itemId) else {
                throw ItemEditorError.itemNotFound
            }
            attributes.location = location
            return (ItemPatch(attributes: attributes), ())
        }
        guard let saved = outcome?.item else { throw ItemEditorError.itemNotFound }   // unreachable: the patch is never empty
        return saved
    }
}

// MARK: - Session guard (plan 15 review)

public enum PendingEditsSessionError: Error, Equatable, Sendable {
    /// Signed out, or signed in as another account: the entry waits, untouched, for its owner.
    case notSignedInAsOwner
    /// The verifying read got no clear answer (not a 200) — nothing may be concluded from it.
    case unverifiable
}

/// Who `PendingEdits` sends as, and how it proves an item is really gone.
///
/// Why this exists: supabase-swift 2.54.1's `SupabaseClient.adapt` fetches the token with
/// `try? await auth.session.accessToken`, so when a token refresh fails the request still goes out
/// — with the default `Authorization: Bearer <anon key>`. Under RLS an anon PATCH matches zero rows
/// (`PGRST116`), which looks exactly like "the item was deleted"; `auth.currentUser` doesn't help
/// (it returns the stored user even when that session can no longer be refreshed).
public protocol PendingEditsSession: Sendable {
    /// A currently valid access token for `userId` — refreshed if needed; `auth.session` only ever
    /// returns a token with ≥ 30 s left. Throws `.notSignedInAsOwner` when signed out or signed in
    /// as someone else, or the refresh's own transport error when no valid token can be had now.
    func accessToken(for userId: UUID) async throws -> String
    /// Whether the item's row exists for the holder of `accessToken` — asked with exactly that
    /// token (never a fallback), so a `false` really means "not there for this user".
    func rowExists(itemId: UUID, accessToken: String) async throws -> Bool
}

public struct SupabasePendingEditsSession: PendingEditsSession {
    /// What `rowExists` reads through (tests pass a session with a stubbed protocol).
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func accessToken(for userId: UUID) async throws -> String {
        do {
            let session = try await StashClient.shared.auth.session
            guard session.user.id == userId else { throw PendingEditsSessionError.notSignedInAsOwner }
            return session.accessToken
        } catch let error as URLError {
            throw error                  // the refresh couldn't reach the server: transient
        } catch let error as PendingEditsSessionError {
            throw error
        } catch {
            // No session (signed out), or the refresh was refused (the SDK then signs out).
            throw PendingEditsSessionError.notSignedInAsOwner
        }
    }

    /// A direct PostgREST read — deliberately not through `StashClient`, whose `adapt` would swap
    /// in (or, on a failed refresh, fall back from) the token this check must use. Only a `200`
    /// with a JSON array is an answer; anything else is `.unverifiable`.
    public func rowExists(itemId: UUID, accessToken: String) async throws -> Bool {
        let (data, response) = try await urlSession.data(for: Self.rowExistsRequest(itemId: itemId, accessToken: accessToken))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PendingEditsSessionError.unverifiable }
        struct Row: Decodable { let id: UUID }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else {
            throw PendingEditsSessionError.unverifiable
        }
        return !rows.isEmpty
    }

    /// `GET /rest/v1/items?id=eq.<id>&select=id` with exactly `accessToken` — pure, for tests.
    static func rowExistsRequest(itemId: UUID, accessToken: String) -> URLRequest {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/rest/v1/items")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId.uuidString.lowercased())"),
                                    URLQueryItem(name: "select", value: "id")]))
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
