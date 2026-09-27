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
    /// Every key on the server's `location` object this build doesn't model yet (e.g. a future
    /// `place_id`) — captured on decode, written back unchanged on encode via the same `AnyKey`
    /// technique `ItemAttributes` uses at the top level. `location` is itself whole-value-replaced
    /// on every edit (see `ItemAttributes`'s doc comment), so this is the only thing standing
    /// between a server-written key here and its silent deletion the next time this build saves a
    /// DIFFERENT top-level attribute (e.g. `media` or `link`), since every attributes PATCH
    /// re-encodes the whole blob, `location` included.
    public var extra: [String: JSONValue]

    public init(label: String, latitude: Double? = nil, longitude: Double? = nil,
                accuracyM: Double? = nil, city: String? = nil, region: String? = nil,
                country: String? = nil, source: String, capturedAt: String? = nil,
                extra: [String: JSONValue] = [:]) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyM = accuracyM
        self.city = city
        self.region = region
        self.country = country
        self.source = source
        self.capturedAt = capturedAt
        self.extra = extra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        label = try container.decode(String.self, forKey: AnyKey(stringValue: "label")!)
        latitude = try container.decodeIfPresent(Double.self, forKey: AnyKey(stringValue: "latitude")!)
        longitude = try container.decodeIfPresent(Double.self, forKey: AnyKey(stringValue: "longitude")!)
        accuracyM = try container.decodeIfPresent(Double.self, forKey: AnyKey(stringValue: "accuracy_m")!)
        city = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "city")!)
        region = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "region")!)
        country = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "country")!)
        source = try container.decode(String.self, forKey: AnyKey(stringValue: "source")!)
        capturedAt = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "captured_at")!)

        let known: Set<String> = [
            "label", "latitude", "longitude", "accuracy_m", "city", "region", "country",
            "source", "captured_at",
        ]
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        try container.encode(label, forKey: AnyKey(stringValue: "label")!)
        try container.encodeIfPresent(latitude, forKey: AnyKey(stringValue: "latitude")!)
        try container.encodeIfPresent(longitude, forKey: AnyKey(stringValue: "longitude")!)
        try container.encodeIfPresent(accuracyM, forKey: AnyKey(stringValue: "accuracy_m")!)
        try container.encodeIfPresent(city, forKey: AnyKey(stringValue: "city")!)
        try container.encodeIfPresent(region, forKey: AnyKey(stringValue: "region")!)
        try container.encodeIfPresent(country, forKey: AnyKey(stringValue: "country")!)
        try container.encode(source, forKey: AnyKey(stringValue: "source")!)
        try container.encodeIfPresent(capturedAt, forKey: AnyKey(stringValue: "captured_at")!)
        for (key, value) in extra {
            try container.encode(value, forKey: AnyKey(stringValue: key)!)
        }
    }
}

/// Link-flavored metadata (video/article/etc.) attached to a captured URL.
public struct LinkAttributes: Codable, Equatable, Hashable, Sendable {
    public var flavor: String?
    public var author: String?
    public var durationS: Double?
    public var stars: Int?
    public var readTimeMin: Int?
    /// Every key on the server's `link` object this build doesn't model yet — e.g. the flavor
    /// facts `add-url`/`extract-link-metadata` write per `flavor` (`site_name`, `video_id`, and
    /// similar). Captured on decode, written back unchanged on encode. Same reasoning as
    /// `CapturedLocation.extra`.
    public var extra: [String: JSONValue]

    public init(flavor: String? = nil, author: String? = nil, durationS: Double? = nil,
                stars: Int? = nil, readTimeMin: Int? = nil, extra: [String: JSONValue] = [:]) {
        self.flavor = flavor
        self.author = author
        self.durationS = durationS
        self.stars = stars
        self.readTimeMin = readTimeMin
        self.extra = extra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        flavor = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "flavor")!)
        author = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "author")!)
        durationS = try container.decodeIfPresent(Double.self, forKey: AnyKey(stringValue: "duration_s")!)
        stars = try container.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "stars")!)
        readTimeMin = try container.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "read_time_min")!)

        let known: Set<String> = ["flavor", "author", "duration_s", "stars", "read_time_min"]
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        try container.encodeIfPresent(flavor, forKey: AnyKey(stringValue: "flavor")!)
        try container.encodeIfPresent(author, forKey: AnyKey(stringValue: "author")!)
        try container.encodeIfPresent(durationS, forKey: AnyKey(stringValue: "duration_s")!)
        try container.encodeIfPresent(stars, forKey: AnyKey(stringValue: "stars")!)
        try container.encodeIfPresent(readTimeMin, forKey: AnyKey(stringValue: "read_time_min")!)
        for (key, value) in extra {
            try container.encode(value, forKey: AnyKey(stringValue: key)!)
        }
    }
}

/// Metadata for an uploaded audio/video/document file.
public struct MediaAttributes: Codable, Equatable, Hashable, Sendable {
    public var durationS: Double?
    public var fileName: String?
    /// Every key on the server's `media` object this build doesn't model yet — notably `kind`
    /// (the voice_note/recording/video subtype `add-file` computes once transcription finishes;
    /// web reads it via `CardBits.tsx`'s `audioSubtype`/`isScreenshotItem`) and `transcript`
    /// (status/model/chunk progress written by the chunked transcription job). `media` is never
    /// edited from iOS at all, yet every whole-blob attributes PATCH re-encodes it from this
    /// struct — before this field existed, saving e.g. a `location` edit would silently delete
    /// these the next time the row was saved, because `MediaAttributes` had nowhere to put them.
    /// Captured on decode, written back unchanged on encode.
    public var extra: [String: JSONValue]

    public init(durationS: Double? = nil, fileName: String? = nil, extra: [String: JSONValue] = [:]) {
        self.durationS = durationS
        self.fileName = fileName
        self.extra = extra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        durationS = try container.decodeIfPresent(Double.self, forKey: AnyKey(stringValue: "duration_s")!)
        fileName = try container.decodeIfPresent(String.self, forKey: AnyKey(stringValue: "file_name")!)

        let known: Set<String> = ["duration_s", "file_name"]
        var extra: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            extra[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.extra = extra
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        try container.encodeIfPresent(durationS, forKey: AnyKey(stringValue: "duration_s")!)
        try container.encodeIfPresent(fileName, forKey: AnyKey(stringValue: "file_name")!)
        for (key, value) in extra {
            try container.encode(value, forKey: AnyKey(stringValue: key)!)
        }
    }
}

/// A `CodingKey` that accepts any string, letting `ItemAttributes` — and, as of Task 5, its
/// `CapturedLocation`/`LinkAttributes`/`MediaAttributes` leaves — each walk every key actually
/// present in their own JSON object rather than a fixed, closed set.
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
/// Preservation does NOT stop at the top level — `location`, `link`, and `media` each carry their
/// own `extra: [String: JSONValue]` too (same `AnyKey` technique as this type), because nested
/// loss here isn't hypothetical: `media` is never edited from iOS at all, yet every whole-blob
/// attributes PATCH (any edit to `location`, `link`, title, description, …) re-encodes it from
/// this build's typed `MediaAttributes`. Before `MediaAttributes.extra` existed, that re-encode
/// silently dropped server-written keys this build didn't model — `media.kind` (the
/// voice_note/recording/video subtype `add-file` computes after transcription) and
/// `media.transcript` (status/model/chunk progress) chief among them — the very next time the row
/// was saved for an unrelated reason. `link` has the same exposure for flavor facts (e.g.
/// `site_name`, `video_id`) this build doesn't model. The whole-value-replace convention one level
/// down still holds (an edit that touches `location` always writes a complete new
/// `CapturedLocation`, never a partial patch of it), which is exactly why the ONLY way a nested
/// key like `media.kind` survives an edit to a *sibling* attribute is if `MediaAttributes` itself
/// round-trips keys it doesn't recognize — so each leaf struct now does, via its own `extra`.
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

public extension ItemAttributes {
    /// Pipeline-owned status; unknown attributes still round-trip untouched.
    func enrichmentStatus(at now: Date) -> String? {
        guard case let .object(value) = extra["enrichment"],
              case let .string(status) = value["status"] else { return nil }
        guard status == "pending" else { return status }
        guard case let .string(timestamp) = value["updated_at"] else { return "partial" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        guard let started = fractional ?? formatter.date(from: timestamp) else { return "partial" }
        return now.timeIntervalSince(started) < 600 ? "pending" : "partial"
    }
}
