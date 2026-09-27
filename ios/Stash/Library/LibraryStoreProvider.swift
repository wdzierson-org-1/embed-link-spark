import Foundation
import StashKit

/// Owns the signed-in user's `ItemStore` at app scope (plan 15, "Instant library"): created once
/// per signed-in user, the first time `StashApp` renders `MainTabView` for them — synchronously
/// hydrated from the disk cache, so the View tab has cards before it is ever shown — and torn down
/// on sign-out/account deletion together with every cached page and image.
///
/// Deliberately NOT `@Observable`: `store(for:)` runs inside `StashApp.body`, and the store it
/// hands out is itself observable; nothing here needs to trigger a re-render.
@MainActor
final class LibraryStoreProvider {
    /// Single source of truth for page size — the store's short-page "hasMore" check and the
    /// fetcher's SQL LIMIT must agree, or pagination silently breaks.
    static let pageSize = 50

    private var current: ItemStore?

    func store(for userId: UUID) -> ItemStore {
        if let current, current.userId == userId { return current }
        if let previous = current { Task { await previous.close() } }
        let store = ItemStore(userId: userId,
                              fetcher: SupabaseItemsFetcher(pageSize: Self.pageSize),
                              pageSize: Self.pageSize,
                              cache: ItemCache())
        current = store
        return store
    }

    /// Sign-out / account deletion: stop the store's cache writes first (so a late write can't
    /// re-create what's about to be deleted), then drop every cached page and image.
    func purge() async {
        let previous = current
        current = nil
        await previous?.close()
        LibraryCaches.purgeAll()
    }
}

/// Everything the View tab keeps on disk/in memory for the signed-in account.
enum LibraryCaches {
    static func purgeAll() {
        ItemCache().deleteAll()
        ImagePipeline.shared.purge()
    }
}
