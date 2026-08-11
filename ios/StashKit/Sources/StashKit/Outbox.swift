import Foundation

public struct OutboxEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case note, url, file }
    public var id: UUID
    public var kind: Kind
    public var payload: [String: String]
    public var createdAt: Date
    public var attempts: Int
}

/// One JSON file per pending capture. Survives crashes and offline periods;
/// plan 3 moves the directory into the App Group container.
public actor Outbox {
    private let directory: URL
    private var isDraining = false

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "StashOutbox")
    }

    public func enqueue(_ kind: OutboxEntry.Kind, payload: [String: String]) throws {
        let entry = OutboxEntry(id: UUID(), kind: kind, payload: payload, createdAt: Date(), attempts: 0)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: entry.id), options: .atomic)
    }

    public func pending() -> [OutboxEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? JSONDecoder().decode(OutboxEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func drain(api: CaptureAPI, accessToken: String) async -> Int {
        guard !isDraining else { return 0 }
        isDraining = true
        defer { isDraining = false }
        var sent = 0
        for var entry in pending() {
            do {
                _ = try await send(entry, api: api, accessToken: accessToken)
                try? FileManager.default.removeItem(at: fileURL(for: entry.id))
                sent += 1
            } catch {
                entry.attempts += 1
                if let data = try? JSONEncoder().encode(entry) {
                    try? data.write(to: fileURL(for: entry.id), options: .atomic)
                }
            }
        }
        return sent
    }

    private func send(_ entry: OutboxEntry, api: CaptureAPI, accessToken: String) async throws -> Item {
        let isPublic = entry.payload["is_public"] == "true"
        switch entry.kind {
        case .note:
            return try await api.addNote(content: entry.payload["content"] ?? "",
                                         title: entry.payload["title"], isPublic: isPublic,
                                         accessToken: accessToken)
        case .url:
            return try await api.addURL(entry.payload["url"] ?? "",
                                        note: entry.payload["content"] ?? "", isPublic: isPublic,
                                        accessToken: accessToken)
        case .file:
            return try await api.addFile(path: entry.payload["file_path"] ?? "",
                                         mimeType: entry.payload["mime_type"] ?? "application/octet-stream",
                                         fileSize: entry.payload["file_size"].flatMap(Int.init),
                                         content: entry.payload["content"], isPublic: isPublic,
                                         accessToken: accessToken)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
