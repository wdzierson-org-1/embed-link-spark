import Foundation

/// A device-captured location, written by the capture flow and read back by the detail view's
/// location section. `source` is deliberately an open string (not an enum) — mirrors
/// `LinkAttributes.flavor` below — so a value this build doesn't recognize still round-trips
/// instead of getting coerced to `.unknown` and silently rewritten on the next save.
public struct CapturedLocation: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var latitude: Double?
    public var longitude: Double?
    public var accuracyM: Double?
    public var city: String?
    public var region: String?
    public var country: String?
    public var source: String
    public var capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case label, latitude, longitude, city, region, country, source
        case accuracyM = "accuracy_m"
        case capturedAt = "captured_at"
    }

    public init(label: String, latitude: Double? = nil, longitude: Double? = nil,
                accuracyM: Double? = nil, city: String? = nil, region: String? = nil,
                country: String? = nil, source: String, capturedAt: String? = nil) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyM = accuracyM
        self.city = city
        self.region = region
        self.country = country
        self.source = source
        self.capturedAt = capturedAt
    }
}

/// Link-flavored metadata (video/article/etc.) attached to a captured URL.
public struct LinkAttributes: Codable, Equatable, Hashable, Sendable {
    public var flavor: String?
    public var author: String?
    public var durationS: Double?
    public var stars: Int?
    public var readTimeMin: Int?

    enum CodingKeys: String, CodingKey {
        case flavor, author, stars
        case durationS = "duration_s"
        case readTimeMin = "read_time_min"
    }

    public init(flavor: String? = nil, author: String? = nil, durationS: Double? = nil,
                stars: Int? = nil, readTimeMin: Int? = nil) {
        self.flavor = flavor
        self.author = author
        self.durationS = durationS
        self.stars = stars
        self.readTimeMin = readTimeMin
    }
}

/// Metadata for an uploaded audio/video/document file.
public struct MediaAttributes: Codable, Equatable, Hashable, Sendable {
    public var durationS: Double?
    public var fileName: String?

    enum CodingKeys: String, CodingKey {
        case durationS = "duration_s"
        case fileName = "file_name"
    }

    public init(durationS: Double? = nil, fileName: String? = nil) {
        self.durationS = durationS
        self.fileName = fileName
    }
}

/// A `CodingKey` that accepts any string, letting `ItemAttributes` walk every key actually present
/// in the JSON object rather than a fixed, closed set.
private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Loss-less model of the `items.attributes` jsonb column.
///
/// The web edit flows PATCH this column as a whole value (never a per-key merge — same convention
/// as `ItemPatch.restBody`'s other fields), so an iOS build that only understands `location`/
/// `link`/`media` must still preserve any other top-level key it doesn't recognize yet across a
/// decode → mutate-one-known-field → encode round trip, or it would silently delete that key from
/// the server's row the next time it saves. `location`/`link`/`media` decode typed for call sites
/// that read them; every other top-level key is captured in `extra` and written back unchanged.
///
/// Preservation stops at the top level deliberately: `location`/`link`/`media` are themselves
/// plain `Codable` structs (an unrecognized key nested *inside* one of them is dropped, not kept).
/// The same whole-value-replace convention applies one level down — an edit that touches
/// `location` always writes a complete new `CapturedLocation`, never a partial patch of it — so
/// there's no code path that would author a sub-object containing a field this build can't parse
/// and then need to hand it back untouched. Tripling the `AnyKey` machinery for leaves that can
/// never actually lose data isn't worth the complexity.
public struct ItemAttributes: Codable, Equatable, Hashable, Sendable {
    public var location: CapturedLocation?
    public var link: LinkAttributes?
    public var media: MediaAttributes?
    public var extra: [String: JSONValue]

    public var isEmpty: Bool {
        location == nil && link == nil && media == nil && extra.isEmpty
    }

    public init(location: CapturedLocation? = nil, link: LinkAttributes? = nil,
                media: MediaAttributes? = nil, extra: [String: JSONValue] = [:]) {
        self.location = location
        self.link = link
        self.media = media
        self.extra = extra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var location: CapturedLocation?
        var link: LinkAttributes?
        var media: MediaAttributes?
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys {
            switch key.stringValue {
            case "location":
                location = try container.decodeIfPresent(CapturedLocation.self, forKey: key)
            case "link":
                link = try container.decodeIfPresent(LinkAttributes.self, forKey: key)
            case "media":
                media = try container.decodeIfPresent(MediaAttributes.self, forKey: key)
            default:
                extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
        }
        self.location = location
        self.link = link
        self.media = media
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        if let location {
            try container.encode(location, forKey: AnyKey(stringValue: "location")!)
        }
        if let link {
            try container.encode(link, forKey: AnyKey(stringValue: "link")!)
        }
        if let media {
            try container.encode(media, forKey: AnyKey(stringValue: "media")!)
        }
        for (key, value) in extra {
            try container.encode(value, forKey: AnyKey(stringValue: key)!)
        }
    }

    /// This attribute blob as a `JSONSerialization`-ready object, for building request bodies
    /// (`[String: Any]`, matching `JSONPosting.post(path:body:accessToken:)`) without a second,
    /// hand-written conversion that could drift from `encode(to:)`.
    public func jsonObject() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
