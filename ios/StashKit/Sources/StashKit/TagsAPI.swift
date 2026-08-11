import Foundation

public struct StashTag: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let usageCount: Int
    enum CodingKeys: String, CodingKey { case id, name, usageCount = "usage_count" }
}

public func fetchTags(userId: UUID) async throws -> [StashTag] {
    let data = try await StashClient.shared.from("tags")
        .select("id,name,usage_count")
        .eq("user_id", value: userId.uuidString)
        .order("usage_count", ascending: false)
        .execute().data
    return try JSONDecoder().decode([StashTag].self, from: data)
}
