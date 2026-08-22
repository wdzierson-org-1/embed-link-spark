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

        // A known key that's present but doesn't match its expected shape (e.g. the server sent
        // `"location"` as a bare string, not an object) must not fail this decode — same
        // precedent as `ItemType.unknown` (Item.swift): a value this build can't parse yet still
        // round-trips loss-lessly via `extra` instead of throwing the caller's entire `[Item]`
        // page decode away. Before this fallback existed, one malformed known key anywhere in a
        // user's history would set `ItemStore.loadError` for the whole library, permanently —
        // pull-to-retry re-runs the same decode and fails the same way every time.
        func decodeKnownOrPreserveRaw<T: Decodable>(_ type: T.Type, forKey key: AnyKey) -> T? {
            do {
                return try container.decodeIfPresent(type, forKey: key)
            } catch {
                extra[key.stringValue] = (try? container.decode(JSONValue.self, forKey: key)) ?? .null
                return nil
            }
        }

        for key in container.allKeys {
            switch key.stringValue {
            case "location":
                location = decodeKnownOrPreserveRaw(CapturedLocation.self, forKey: key)
            case "link":
                link = decodeKnownOrPreserveRaw(LinkAttributes.self, forKey: key)
            case "media":
                media = decodeKnownOrPreserveRaw(MediaAttributes.self, forKey: key)
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
    ///
    /// Returns `nil` if `self` can't be encoded (e.g. `extra` holds a non-finite `Double`, which
    /// JSON has no representation for) — deliberately NOT `[:]`. This is a whole-column
    /// PATCH-replace body: a caller that sent `[:]` on an encode failure would silently wipe every
    /// attribute the row already has, including ones this build doesn't understand yet. Callers
    /// MUST treat `nil` as "do not send" and skip the attributes write entirely rather than
    /// falling back to an empty object.
    public func jsonObject() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    /// `jsonObject()` filtered through the one gate every request-body call site needs (Task 5:
    /// `CaptureAPI`'s three `add-*` bodies, `CaptureViewModel`'s Outbox `attributes_json`
    /// payload): `nil` on an encode failure (`jsonObject()`'s own contract) and `nil` for a
    /// successfully-encoded-but-empty blob (nothing pinned, no media facts — `jsonObject()`
    /// returns `[:]`, not `nil`, for that case) collapse to the same single "don't send" signal,
    /// instead of every caller re-deriving `!object.isEmpty` for itself.
    var nonEmptyJSONObject: [String: Any]? {
        guard let object = jsonObject(), !object.isEmpty else { return nil }
        return object
    }
}
