import Foundation
import Supabase

public struct ItemShareState: Codable, Equatable, Sendable {
    public let token: String?
    public let sharedAt: String?
    enum CodingKeys: String, CodingKey { case token = "share_token", sharedAt = "shared_at" }
    public init(token: String? = nil, sharedAt: String? = nil) { self.token = token; self.sharedAt = sharedAt }
    public var url: URL? {
        guard let token, ItemShareToken.isValid(token) else { return nil }
        return URL(string: "https://www.gostash.it/s/\(token)")
    }
}

public struct ItemShareMutation: Encodable, Equatable, Sendable {
    public let token: String?
    public let sharedAt: String?
    public init(token: String?, sharedAt: String?) { self.token = token; self.sharedAt = sharedAt }
    enum CodingKeys: String, CodingKey { case token = "share_token", sharedAt = "shared_at" }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        // Explicit null revokes; encodeIfPresent would silently omit the requested deletion.
        try values.encode(token, forKey: .token)
        try values.encode(sharedAt, forKey: .sharedAt)
    }
}

public enum ItemShareError: Error, Equatable { case notFound, signedOut, changedElsewhere, tokenCollision }

public protocol ItemShareStoring: Sendable {
    func read(itemID: UUID, userID: UUID) async throws -> ItemShareState?
    func replace(itemID: UUID, userID: UUID, expectedToken: String?, with mutation: ItemShareMutation) async throws -> ItemShareState?
}

public enum ItemShareToken {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)
    public static func mint() -> String {
        var generator = SystemRandomNumberGenerator()
        var bytes: [UInt8] = []
        while bytes.count < 10 {
            let byte = UInt8.random(in: .min ... .max, using: &generator)
            // Same unbiased rejection sampling as the web's crypto.getRandomValues.
            guard byte < 248 else { continue }
            bytes.append(alphabet[Int(byte) % 62])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    public static func isValid(_ token: String) -> Bool {
        token.utf8.count == 10 && token.utf8.allSatisfy { alphabet.contains($0) }
    }
}

public struct ItemShareService: Sendable {
    private let store: any ItemShareStoring
    private let mintToken: @Sendable () -> String
    public init(store: any ItemShareStoring = SupabaseItemShareStore(),
                mintToken: @escaping @Sendable () -> String = { ItemShareToken.mint() }) {
        self.store = store; self.mintToken = mintToken
    }
    public func current(itemID: UUID, userID: UUID) async throws -> ItemShareState {
        guard let row = try await store.read(itemID: itemID, userID: userID) else { throw ItemShareError.notFound }
        return row
    }
    public func share(itemID: UUID, userID: UUID) async throws -> ItemShareState {
        for _ in 0..<3 {
            try Task.checkCancellation()
            let existing = try await current(itemID: itemID, userID: userID)
            if existing.url != nil { return existing }
            let token = mintToken()
            guard ItemShareToken.isValid(token) else { throw ItemShareError.tokenCollision }
            let change = ItemShareMutation(token: token, sharedAt: ISO8601DateFormatter().string(from: .now))
            do {
                if let saved = try await store.replace(itemID: itemID, userID: userID,
                                                       expectedToken: existing.token, with: change) { return saved }
                // Another client created a link after our read: fetch and use its winning token.
            } catch ItemShareError.tokenCollision { continue }
        }
        throw ItemShareError.changedElsewhere
    }
    public func revoke(itemID: UUID, userID: UUID, token: String) async throws -> ItemShareState {
        let change = ItemShareMutation(token: nil, sharedAt: nil)
        if let saved = try await store.replace(itemID: itemID, userID: userID, expectedToken: token, with: change) {
            return saved
        }
        let current = try await current(itemID: itemID, userID: userID)
        if current.token == nil { return current }
        throw ItemShareError.changedElsewhere
    }
}

/// The web's normal owner update, not shared_item(p_token), which is an anonymous read RPC.
/// Both owner and expected-token filters are checked by Postgres; a stale screen cannot
/// revoke a newer link or change a row belonging to the account that just replaced this one.
public struct SupabaseItemShareStore: ItemShareStoring {
    public init() {}
    private static let columns = "share_token,shared_at"

    private func authorize(_ userID: UUID) async throws {
        guard StashClient.shared.auth.currentSession?.user.id == userID else { throw ItemShareError.signedOut }
        let session = try await StashClient.shared.auth.session
        guard session.user.id == userID else { throw ItemShareError.signedOut }
    }

    public func read(itemID: UUID, userID: UUID) async throws -> ItemShareState? {
        try await authorize(userID)
        let data = try await StashClient.shared.from("items").select(Self.columns)
            .eq("id", value: itemID.uuidString).eq("user_id", value: userID.uuidString)
            .limit(1).execute().data
        return try JSONDecoder().decode([ItemShareState].self, from: data).first
    }

    public func replace(itemID: UUID, userID: UUID, expectedToken: String?, with mutation: ItemShareMutation) async throws -> ItemShareState? {
        try await authorize(userID)
        var query = try StashClient.shared.from("items").update(mutation)
            .eq("id", value: itemID.uuidString).eq("user_id", value: userID.uuidString)
        if let expectedToken { query = query.eq("share_token", value: expectedToken) }
        else { query = query.is("share_token", value: nil) }
        do {
            let data = try await query.select(Self.columns).execute().data
            return try JSONDecoder().decode([ItemShareState].self, from: data).first
        } catch let error as PostgrestError where error.code == "23505" {
            throw ItemShareError.tokenCollision
        }
    }
}
