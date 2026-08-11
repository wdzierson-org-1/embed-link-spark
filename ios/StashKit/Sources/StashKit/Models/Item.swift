import Foundation

public enum ItemType: String, Codable, Sendable, CaseIterable {
    case text, link, image, audio, video, document, collection
    case unknown   // forward-compat: never crash on a type this build predates

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemType(rawValue: raw) ?? .unknown
    }
}

public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var type: ItemType
    public var title: String?
    public var content: String?
    public var url: String?
    public var filePath: String?
    public var description: String?
    public var summary: String?
    public var pageBody: String?
    public var supplementalNote: String?
    public var mimeType: String?
    public var isPublic: Bool
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, title, content, url, description, summary
        case filePath = "file_path"
        case pageBody = "page_body"
        case supplementalNote = "supplemental_note"
        case mimeType = "mime_type"
        case isPublic = "is_public"
        case createdAt = "created_at"
    }

    // Postgres timestamptz comes back as ISO8601 with variable fractional digits
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                debugDescription: "Unparseable date: \(s)"))
        }
        return d
    }()

    /// Columns the card grid selects — mirror of web ITEM_LIST_COLUMNS.
    public static let listColumns =
        "id,type,title,content,url,file_path,description,summary,created_at,mime_type,is_public,supplemental_note"
    public static let detailColumns = listColumns + ",page_body"
}
