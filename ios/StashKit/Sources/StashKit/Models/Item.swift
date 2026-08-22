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
    public var fileSize: Int?
    /// The `items.attributes` jsonb column — loss-less; see `ItemAttributes` doc comment.
    /// Never partially-missing: a `nil`/absent column decodes to `ItemAttributes()` (`.isEmpty`),
    /// same as any other field this build doesn't need to special-case.
    public var attributes: ItemAttributes

    enum CodingKeys: String, CodingKey {
        case id, type, title, content, url, description, summary
        case filePath = "file_path"
        case pageBody = "page_body"
        case supplementalNote = "supplemental_note"
        case mimeType = "mime_type"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case fileSize = "file_size"
        case attributes
    }

    public init(id: UUID, type: ItemType, title: String?, content: String?, url: String?,
                filePath: String?, description: String?, summary: String?, pageBody: String?,
                supplementalNote: String?, mimeType: String?, isPublic: Bool, createdAt: Date,
                fileSize: Int? = nil, attributes: ItemAttributes = ItemAttributes()) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.url = url
        self.filePath = filePath
        self.description = description
        self.summary = summary
        self.pageBody = pageBody
        self.supplementalNote = supplementalNote
        self.mimeType = mimeType
        self.isPublic = isPublic
        self.createdAt = createdAt
        self.fileSize = fileSize
        self.attributes = attributes
    }

    /// Custom (not synthesized) so `attributes` can fall back to `ItemAttributes()` when the
    /// column is missing or `null`, instead of throwing like a plain `decode(ItemAttributes.self)`
    /// would. Every other field keeps the same decode shape the compiler would have synthesized;
    /// `encode(to:)` is still synthesized — it needs no equivalent special case.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ItemType.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        pageBody = try container.decodeIfPresent(String.self, forKey: .pageBody)
        supplementalNote = try container.decodeIfPresent(String.self, forKey: .supplementalNote)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fileSize = try container.decodeIfPresent(Int.self, forKey: .fileSize)
        attributes = try container.decodeIfPresent(ItemAttributes.self, forKey: .attributes) ?? ItemAttributes()
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
        "id,type,title,content,url,file_path,description,summary,created_at,mime_type,file_size,is_public,supplemental_note,attributes"
    public static let detailColumns = listColumns + ",page_body"
}
