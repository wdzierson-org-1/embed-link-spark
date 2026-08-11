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
