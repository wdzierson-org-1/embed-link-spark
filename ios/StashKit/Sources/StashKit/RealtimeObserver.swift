import Foundation
import Supabase

public final class RealtimeObserver: Sendable {
    public init() {}

    /// Runs until the surrounding .task is cancelled (view disappears / sign-out).
    public func observeItems(userId: UUID, onChange: @escaping @Sendable () async -> Void) async {
        let channel = StashClient.shared.channel("items-changes-\(userId.uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public",
                                              table: "items",
                                              filter: .eq("user_id", value: userId))
        // subscribeWithError() is the current, non-deprecated API in supabase-swift 2.54.1
        // (deprecated `subscribe()` is `@MainActor` and itself just does `try? await
        // subscribeWithError()` — inlined here to avoid the deprecation warning and the
        // unnecessary actor hop). observeItems has no throwing surface (see task-11-brief.md
        // Interfaces), so a failed subscribe degrades to "no live updates, pull-to-refresh
        // still works" rather than crashing or surfacing an error the caller can't consume.
        try? await channel.subscribeWithError()
        let debouncer = Debouncer(interval: .milliseconds(400))
        for await _ in changes {
            await debouncer.call(onChange)
        }
        await channel.unsubscribe()
    }
}
