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

    /// Per-user Outbox root: `.../Application Support/StashOutbox/<uid-lowercased>`.
    ///
    /// Fix for a Critical final-review finding: this used to be a single directory shared by
    /// every account that ever signed into the device (`.../StashOutbox`, no user segment). The
    /// composer drains the Outbox with whatever session's JWT is CURRENT at drain time — not
    /// whichever user's session was current when an entry was queued — so a note or URL captured
    /// offline under user A survived a sign-out/sign-in as user B and was silently created in B's
    /// account on the next drain. Scoping the directory by user id closes that: user B's `Outbox`
    /// resolves to a directory user A's queued entries were never written into, so a drain can
    /// never cross the account boundary no matter whose session happens to be active.
    ///
    /// Plan 3 is expected to move this directory into the shared App Group container (so the
    /// share extension can enqueue into the same Outbox the app drains) — that migration MUST
    /// preserve this per-user segment; collapsing back to one shared directory across accounts
    /// would reopen this leak.
    public static func defaultDirectory(userId: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "StashOutbox").appending(path: userId.uuidString.lowercased())
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

    /// - Parameters:
    ///   - userId: Needed to build the fresh `makeUploadPath` a `local_file_path` entry uploads
    ///     to — see the `local_file_path` handling below.
    ///   - upload: Injectable for tests; defaults to the real `uploadToStorage`. Only ever called
    ///     for a `.file` entry whose payload contains `local_file_path` (a locally-recorded file
    ///     not yet uploaded) — a `.file` entry with an already-uploaded `file_path` (Task 3) never
    ///     touches this closure.
    public func drain(api: CaptureAPI, accessToken: String, userId: UUID,
                      // Wrapped in a closure literal rather than passing the `uploadToStorage`
                      // function value directly (as sketched in the task brief): a bare reference
                      // triggers "converting non-Sendable function value to '@Sendable ...' may
                      // introduce data races" on this toolchain — the same reason
                      // `CaptureViewModel`'s `upload` parameter wraps it identically.
                      upload: @Sendable (Data, String, String) async throws -> Void = { data, path, contentType in
                          try await uploadToStorage(data: data, path: path, contentType: contentType)
                      }) async -> Int {
        guard !isDraining else { return 0 }
        isDraining = true
        defer { isDraining = false }
        var sent = 0
        for var entry in pending() {
            // Recording durability (Task 4): a `.file` entry can carry `local_file_path` instead
            // of (as well as, briefly) `file_path` — the app's recorder (Task 6) writes audio
            // straight to local disk via `RecordingStore` and enqueues before any network call
            // ever happens, so (unlike every other attachment, which is already uploaded by the
            // time `CaptureViewModel.prepare` enqueues it — Task 3) the upload itself has to
            // happen here, inside drain.
            let localPath = entry.kind == .file ? entry.payload["local_file_path"] : nil

            if let localPath, !FileManager.default.fileExists(atPath: localPath) {
                // Permanent failure: the local recording is gone (e.g. the app was force-quit and
                // its on-disk state got cleared before this entry was ever drained). There are no
                // bytes left anywhere to upload, so — unlike every other failure below, which is
                // retried (attempts += 1, entry rewritten to disk) — this entry is dropped
                // outright. Retrying can never succeed; keeping it around would just retry forever
                // for nothing.
                print("Outbox: dropping entry \(entry.id) — its local recording file is missing, upload can never succeed")
                try? FileManager.default.removeItem(at: fileURL(for: entry.id))
                continue
            }

            do {
                if let localPath {
                    let data = try Data(contentsOf: URL(fileURLWithPath: localPath))
                    let path = makeUploadPath(userId: userId,
                                              fileExtension: URL(fileURLWithPath: localPath).pathExtension)
                    try await upload(data, path, entry.payload["mime_type"] ?? "application/octet-stream")
                    // Delete the local copy the instant its bytes are durably in storage. From
                    // here `entry.payload["file_path"]` (persisted below if `send` still fails) is
                    // enough to retry just the `addFile` registration — same as any other `.file`
                    // entry — without ever re-uploading.
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: localPath))
                    entry.payload["file_path"] = path
                    entry.payload.removeValue(forKey: "local_file_path")
                }
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
