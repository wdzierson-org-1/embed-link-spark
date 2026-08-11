import Foundation

public extension Item {
    /// Port of src/utils/itemSearch.ts — same five fields, substring, case-insensitive.
    func matches(searchQuery: String) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return [title, content, description, url, supplementalNote]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(q) }
    }

    /// Port of src/utils/documentProcessing.ts — summary is the one reliable signal.
    var isProcessingDocument: Bool { type == .document && (summary ?? "").isEmpty }

    /// file_path is either a storage path or a full remote URL (both exist in prod).
    var thumbnailURL: URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        if filePath.hasPrefix("http") { return URL(string: filePath) }
        return StashConfig.publicStorageURL(for: filePath)
    }
}

// Hashable (not just Equatable) so it can back a SwiftUI Picker selection / ForEach id
// in Task 12's ItemDetailView — a no-associated-value enum synthesizes it for free.
public enum ContentTabKey: Sendable, Hashable { case summary, original, notes, transcript }
public struct ContentTab: Sendable, Equatable {
    public let key: ContentTabKey
    public let label: String
}
public struct ContentTabsConfig: Sendable, Equatable {
    public let title: String
    public let defaultTab: ContentTabKey
    public let tabs: [ContentTab]
}

/// Port of src/utils/editPanelTabs.ts.
public func contentTabsConfig(for type: ItemType) -> ContentTabsConfig {
    switch type {
    case .link, .document:
        return .init(title: "Notes & Summary", defaultTab: .summary, tabs: [
            .init(key: .summary, label: "Summary"),
            .init(key: .original, label: "Original Content"),
            .init(key: .notes, label: "Notes"),
        ])
    case .audio, .video:
        return .init(title: "Notes & Transcript", defaultTab: .notes, tabs: [
            .init(key: .notes, label: "Notes"),
            .init(key: .transcript, label: "Transcript"),
        ])
    default:
        return .init(title: "Notes", defaultTab: .notes, tabs: [.init(key: .notes, label: "Notes")])
    }
}

/// Detail views need summary/page_body fetched (list omits page_body).
public func needsSourceContent(_ type: ItemType) -> Bool {
    contentTabsConfig(for: type).tabs.contains { $0.key != .notes }
}

/// Reconciles a fresher server row (`incoming` — a realtime-triggered list refresh, a detail
/// fetch, or our own save response) against a detail sheet's local draft (`local`), without
/// regressing a field the user is actively editing or a field this particular row simply wasn't
/// fetched with.
///
/// Extracted from `ItemDetailView.adopt(_:)` (finding #2, final review — see that call site for
/// how the three `hasUnsaved*` flags are computed from `local`/`snapshot`). Original semantics
/// preserved exactly: `title`/`description`/`supplementalNote` defer to `local` whenever the
/// corresponding `hasUnsaved*` flag is set (there's an unsaved edit in flight, so `incoming` is
/// stale relative to it), and every other field takes `incoming` as-is.
///
/// `pageBody` gets one addition, independent of the unsaved-edit flags: `Item.listColumns` (what
/// every realtime-triggered `store.refresh()` re-queries with) never selects `page_body`, so a
/// list-row `incoming` always carries `pageBody == nil` — not because the server cleared it, but
/// because that fetch's column set never asked for it. Enrichment only ever *writes* that column,
/// so a nil here can never mean "cleared"; only "not fetched this time." Before this fix, `adopt`
/// took `incoming.pageBody` unconditionally, so every realtime refresh while a sheet was open
/// nulled an already-loaded page_body and flipped the Original Content/Transcript tab to its
/// empty state until the sheet was reopened and re-fetched it. A non-nil `incoming.pageBody`
/// (from a detail fetch or a PATCH response — both `Item.detailColumns`) is a real value and
/// always wins, same as any other always-fresh field.
///
/// `summary` needs no equivalent guard: unlike `pageBody`, it IS part of `Item.listColumns`, so
/// every incoming row — list or detail — carries a real value for it.
public func mergePreservingDetail(local: Item, incoming: Item, hasUnsavedTitle: Bool,
                                   hasUnsavedDescription: Bool, hasUnsavedSupplementalNote: Bool) -> Item {
    var result = incoming
    if hasUnsavedTitle { result.title = local.title }
    if hasUnsavedDescription { result.description = local.description }
    if hasUnsavedSupplementalNote { result.supplementalNote = local.supplementalNote }
    if incoming.pageBody == nil { result.pageBody = local.pageBody }
    return result
}
