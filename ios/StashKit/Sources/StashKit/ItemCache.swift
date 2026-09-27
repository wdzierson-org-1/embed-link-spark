import Foundation

/// Per-user on-disk snapshot of the library's first page (plan 15, "Instant library"): what lets
/// the View tab draw real cards on the very first frame of a cold launch instead of a spinner.
///
/// - Lives in the app's own Caches directory (`Caches/StashItemCache/<uid>.json`), never the App
///   Group — the share extension never reads the library. The system may purge Caches at any
///   time; losing the file only costs the next launch one network round trip.
/// - One file per user id, wrapped in a small versioned envelope that also records the owner, so
///   a renamed/misplaced file, a format change, or a corrupt write can never surface another
///   user's cards or crash the decode — any of those just reads as "no cache" (and the bad file
///   is removed).
/// - Written atomically (`Data.write(options: .atomic)`), so a crash mid-write leaves the previous
///   snapshot intact rather than a truncated file.
/// - Deleted on sign-out and account deletion (`deleteAll()`), so nothing from a signed-out
///   account lingers on the device.
///
/// Dates round-trip through ISO-8601 with fractional seconds — the same shape `Item.decoder`
/// already parses from Postgres, so a cached row decodes exactly like a fresh one.
public struct ItemCache: Sendable {
    /// Bump when the envelope or `Item`'s cached shape changes incompatibly; older files are then
    /// ignored (and removed) instead of decoded.
    public static let formatVersion = 1

    public let directory: URL

    public init(directory: URL = ItemCache.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StashItemCache", isDirectory: true)
    }

    public func fileURL(for userId: UUID) -> URL {
        directory.appendingPathComponent("\(userId.uuidString.lowercased()).json", isDirectory: false)
    }

    /// The cached first page for `userId`, newest first — `[]` when there is no usable snapshot.
    public func load(userId: UUID) -> [Item] {
        let url = fileURL(for: userId)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let envelope = try? Item.decoder.decode(Envelope.self, from: data),
              envelope.version == Self.formatVersion,
              envelope.userId == userId
        else {
            try? FileManager.default.removeItem(at: url)
            return []
        }
        return envelope.items
    }

    /// Replaces `userId`'s snapshot with `items`. Returns `false` (leaving any previous snapshot in
    /// place) if the encode or the atomic write fails.
    @discardableResult
    public func save(_ items: [Item], userId: UUID, savedAt: Date = Date()) -> Bool {
        let envelope = Envelope(version: Self.formatVersion, userId: userId, savedAt: savedAt, items: items)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(envelope)
            try data.write(to: fileURL(for: userId), options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    public func delete(userId: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: userId))
    }

    /// Removes every user's snapshot (sign-out / account deletion).
    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// ISO-8601 with fractional seconds — the exact shape `Item.decoder` reads back.
    static let encoder: JSONEncoder = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()

    private struct Envelope: Codable {
        let version: Int
        let userId: UUID
        let savedAt: Date
        let items: [Item]
    }
}
