import Foundation
import Supabase

/// One row-level change decoded from the `items` realtime feed.
public enum ItemChange: Equatable, Sendable {
    /// An INSERT or UPDATE — the row must be re-read (the payload is never trusted as a list row:
    /// realtime records carry every column, including multi-KB `page_body`, and none of the
    /// decoding guarantees `Item.listColumns` reads have).
    case upsert(UUID)
    case delete(UUID)

    public enum Event: Sendable { case insert, update, delete }

    /// Pure decode of a postgres-changes payload (testable without a live `AnyAction`, whose
    /// initializers are internal to supabase-swift). INSERT/UPDATE read `record.id`; DELETE reads
    /// `oldRecord.id` — with the table's default replica identity that is the only column a
    /// delete carries.
    public init?(event: Event, record: [String: AnyJSON], oldRecord: [String: AnyJSON]) {
        let source = event == .delete ? oldRecord : record
        guard case .string(let raw)? = source["id"], let id = UUID(uuidString: raw) else { return nil }
        self = event == .delete ? .delete(id) : .upsert(id)
    }

    init?(_ action: AnyAction) {
        switch action {
        case .insert(let insert): self.init(event: .insert, record: insert.record, oldRecord: [:])
        case .update(let update): self.init(event: .update, record: update.record, oldRecord: update.oldRecord)
        case .delete(let delete): self.init(event: .delete, record: [:], oldRecord: delete.oldRecord)
        }
    }
}

/// The ids touched within one coalescing window. A later change to the same id wins: an upsert
/// followed by a delete is a delete; a delete followed by an upsert is an upsert (the re-read
/// then decides — a row that no longer exists simply comes back missing).
public struct ItemChangeBatch: Equatable, Sendable {
    public private(set) var upserted: Set<UUID> = []
    public private(set) var deleted: Set<UUID> = []

    public init() {}

    public var isEmpty: Bool { upserted.isEmpty && deleted.isEmpty }

    public mutating func add(_ change: ItemChange) {
        switch change {
        case .upsert(let id):
            deleted.remove(id)
            upserted.insert(id)
        case .delete(let id):
            upserted.remove(id)
            deleted.insert(id)
        }
    }
}

/// Fixed-window coalescer: the first change opens a window of `interval`; everything that
/// arrives inside it is delivered as ONE batch when it closes (so a burst — an enrichment
/// pipeline writing the same row four times — costs one re-fetch, and latency stays bounded
/// even under a steady stream, unlike a trailing debounce). Deliveries never overlap: changes
/// that arrive while a batch is still being applied open the next window only once that
/// delivery returns, so an older batch's re-fetch can never land after a newer one's.
public actor ItemChangeCoalescer {
    private let interval: Duration
    private let deliver: @Sendable (ItemChangeBatch) async -> Void
    private var pending = ItemChangeBatch()
    private var window: Task<Void, Never>?

    public init(interval: Duration, deliver: @escaping @Sendable (ItemChangeBatch) async -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    public func add(_ change: ItemChange) {
        pending.add(change)
        openWindowIfNeeded()
    }

    /// Drops anything not yet delivered (the observer is going away).
    public func cancel() {
        window?.cancel()
        window = nil
        pending = ItemChangeBatch()
    }

    private func openWindowIfNeeded() {
        guard window == nil, !pending.isEmpty else { return }
        window = Task { [interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await self.flush()
        }
    }

    private func flush() async {
        let batch = pending
        pending = ItemChangeBatch()
        if !batch.isEmpty { await deliver(batch) }
        // Still non-nil during `deliver`, so changes arriving meanwhile only accumulate.
        window = nil
        openWindowIfNeeded()
    }
}

/// Anything that can stream coalesced item changes for one user (the live Supabase feed, or a
/// test double).
public protocol ItemChangeObserving: Sendable {
    /// Runs until the calling task is cancelled.
    func observeItemChanges(userId: UUID, onBatch: @escaping @Sendable (ItemChangeBatch) async -> Void) async
}

public final class RealtimeObserver: ItemChangeObserving, Sendable {
    /// How long changes are gathered before one re-fetch (plan 15: 400 ms).
    public let coalesceInterval: Duration

    public init(coalesceInterval: Duration = .milliseconds(400)) {
        self.coalesceInterval = coalesceInterval
    }

    /// App-scope incremental feed (plan 15): decodes each INSERT/UPDATE/DELETE and hands the
    /// coalesced ids to `onBatch` — the caller re-fetches just those rows instead of re-querying
    /// page 1. Runs until the surrounding task is cancelled (sign-out tears down `MainTabView`).
    ///
    /// DELETE caveat: `items` uses the default replica identity, and Supabase only evaluates a
    /// `user_id` filter against a delete when replica identity is FULL, so deletes are normally
    /// not delivered on this filtered channel. They're decoded anyway (harmless, and correct the
    /// day replica identity changes); `ItemStore.refresh()`'s merge + existence check is what
    /// actually retires deleted rows.
    public func observeItemChanges(userId: UUID, onBatch: @escaping @Sendable (ItemChangeBatch) async -> Void) async {
        let channel = StashClient.shared.channel("items-changes-\(userId.uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public",
                                              table: "items",
                                              filter: .eq("user_id", value: userId))
        // subscribeWithError() is the current, non-deprecated API in supabase-swift 2.54.1
        // (deprecated `subscribe()` is `@MainActor` and itself just does `try? await
        // subscribeWithError()`). A failed subscribe degrades to "no live updates" — the
        // foreground/tab-appear refreshes and pull-to-refresh still keep the list current.
        try? await channel.subscribeWithError()
        let coalescer = ItemChangeCoalescer(interval: coalesceInterval, deliver: onBatch)
        for await action in changes {
            if let change = ItemChange(action) { await coalescer.add(change) }
        }
        await coalescer.cancel()
        await channel.unsubscribe()
    }

    /// Pre-plan-15 shape (one callback per coalesced burst, no ids) — kept source-compatible.
    public func observeItems(userId: UUID, onChange: @escaping @Sendable () async -> Void) async {
        await observeItemChanges(userId: userId) { _ in await onChange() }
    }
}
