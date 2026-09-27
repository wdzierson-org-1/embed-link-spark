import XCTest
@testable import StashKit

/// `ItemAttributes` is the loss-less model for the `items.attributes` jsonb column: the web app's
/// edit flows PATCH the whole column (never a per-key merge — see ItemEditor.swift's restBody
/// comment for the same whole-value-replace convention on other fields), so an iOS decode-then-
/// reencode round trip must never drop a key it doesn't recognize. `location`/`link`/`media` are
/// decoded typed for call sites that read them; everything else funnels into `extra` and is
/// written straight back on encode.
///
/// Task 5: that same guarantee now extends one level down. `CapturedLocation`/`LinkAttributes`/
/// `MediaAttributes` each keep their own `extra` too, so a nested server-written key this build
/// doesn't model (e.g. `media.kind`, `media.transcript`, `link.site_name`, `link.video_id`,
/// `location.place_id`) survives an edit to a *sibling* attribute instead of being silently
/// dropped on the next whole-blob save — see `ItemAttributes.swift`'s doc comment for why that was
/// a real, live bug (`media` is never edited from iOS at all) rather than a theoretical one.
final class ItemAttributesTests: XCTestCase {

    func testUnknownTopLevelKeysSurviveRoundTrip() throws {
        let raw = #"{"location":{"label":"L","source":"manual"},"weather":{"temp_c":21},"mood":"good"}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        XCTAssertEqual(attrs.location?.label, "L")
        XCTAssertEqual(attrs.extra["mood"], .string("good"))
        let reencoded = try JSONEncoder().encode(attrs)
        let obj = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        XCTAssertNotNil(obj["weather"]); XCTAssertNotNil(obj["mood"]); XCTAssertNotNil(obj["location"])
    }

    func testSnakeCaseLeafKeys() throws {
        let raw = #"{"link":{"flavor":"video","duration_s":58},"media":{"file_name":"a.png","duration_s":2.5}}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        XCTAssertEqual(attrs.link?.durationS, 58)
        XCTAssertEqual(attrs.media?.fileName, "a.png")
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
        let media = obj["media"] as! [String: Any]
        XCTAssertNotNil(media["file_name"])
    }

    /// Nested unknown keys (inside `location`/`link`/`media`) now round-trip too (Task 5): each
    /// leaf struct keeps its own `extra`, so a key this build doesn't model isn't silently
    /// dropped the next time some OTHER attribute is edited and the whole blob gets re-encoded.
    func testNestedUnknownKeysSurviveRoundTrip() throws {
        let raw = #"{"location":{"label":"L","source":"manual","weird_new_field":"x"}}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        XCTAssertEqual(attrs.location?.extra["weird_new_field"], .string("x"))
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
        let location = obj["location"] as! [String: Any]
        XCTAssertEqual(location["weird_new_field"] as? String, "x")
    }

    func testEmptyAttributesRoundTripsToEmptyObject() throws {
        let attrs = ItemAttributes()
        XCTAssertTrue(attrs.isEmpty)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
        XCTAssertTrue(obj.isEmpty)
    }

    func testJSONObjectIsSerializationReady() throws {
        let raw = #"{"link":{"flavor":"video"},"mood":"good"}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        let obj = try XCTUnwrap(attrs.jsonObject())
        // Must be usable directly as a request body without any further conversion.
        XCTAssertTrue(JSONSerialization.isValidJSONObject(obj))
        let link = obj["link"] as! [String: Any]
        XCTAssertEqual(link["flavor"] as? String, "video")
        XCTAssertEqual(obj["mood"] as? String, "good")
    }

    /// Review finding #2: a whole-blob-replace PATCH body must never silently substitute an empty
    /// object for one that failed to encode — that would wipe every attribute the row already
    /// has. `jsonObject()` returns `nil` (not `[:]`) when `self` can't be encoded (here: a
    /// `Double` JSON has no representation for), so callers can tell "empty on purpose" apart
    /// from "unencodable, do not send".
    func testJSONObjectReturnsNilForUnencodableValue() {
        let attrs = ItemAttributes(extra: ["bad": .number(Double.infinity)])
        XCTAssertNil(attrs.jsonObject())
    }

    /// Review finding #1: a *known* key that's present but doesn't match its expected shape
    /// (server sent `"location"` as a bare string, not an object) must not fail the whole decode
    /// — same precedent as `ItemType.unknown` elsewhere in this model: preserve what this build
    /// can't parse instead of throwing the caller's entire page load away. The malformed value
    /// still round-trips loss-lessly through `extra`.
    func testMalformedKnownKeyFallsBackToExtraWithoutThrowing() throws {
        let raw = #"{"location":"not-an-object","link":{"flavor":"video"}}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        XCTAssertNil(attrs.location)
        XCTAssertEqual(attrs.link?.flavor, "video")
        XCTAssertEqual(attrs.extra["location"], .string("not-an-object"))

        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
        XCTAssertEqual(obj["location"] as? String, "not-an-object")
    }

    // MARK: - Task 5: nested (`location`/`link`/`media`) loss-less round trip

    /// The end-to-end regression this task exists to prevent: a realistic server row carrying
    /// `media.kind` + `media.transcript` (chunked-transcription status), `link.site_name` +
    /// `link.video_id` (flavor facts), and `location.place_id` — none of which this build models
    /// as a typed field — plus a top-level unknown key, must decode → re-encode to something
    /// JSON-equivalent to what it started as. Compared as PARSED dictionaries (`NSDictionary`
    /// deep equality), not raw bytes, since `JSONEncoder`/`JSONSerialization` don't guarantee
    /// identical text for equivalent values (key order, `3` vs `3.0`) — that's expected and fine;
    /// losing a key is not.
    func testFullFixtureRoundTripsToEquivalentJSON() throws {
        let raw = #"""
        {
          "media": {"duration_s": 12.5, "file_name": "voice.m4a", "kind": "voice_note",
                     "transcript": {"status": "done", "model": "x", "chunks": 3}},
          "link": {"flavor": "video", "site_name": "YouTube", "video_id": "abc"},
          "location": {"label": "Home", "latitude": 37.7749, "longitude": -122.4194,
                        "source": "device-geolocation", "place_id": "p1"},
          "mood": "good"
        }
        """#
        let original = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))

        // The fields this build actually models still decode typed.
        XCTAssertEqual(attrs.media?.fileName, "voice.m4a")
        XCTAssertEqual(attrs.link?.flavor, "video")
        XCTAssertEqual(attrs.location?.label, "Home")
        // Everything else survives via each leaf's own `extra`.
        XCTAssertEqual(attrs.media?.extra["kind"], .string("voice_note"))
        XCTAssertEqual(attrs.link?.extra["site_name"], .string("YouTube"))
        XCTAssertEqual(attrs.location?.extra["place_id"], .string("p1"))

        let reencoded = try JSONEncoder().encode(attrs)
        let roundTripped = try JSONSerialization.jsonObject(with: reencoded) as! [String: Any]
        XCTAssertEqual(original as NSDictionary, roundTripped as NSDictionary)
    }

    /// Simulates the detail sheet's location-row edit (Task 8): decode a row, replace `location`
    /// wholesale (the same whole-value-replace convention as every other attributes field —
    /// `media`/`link` are never touched by this edit at all), and encode. Before Task 5,
    /// `media.kind`/`media.transcript`/`link.site_name`/`link.video_id` would all have been
    /// silently dropped here, because saving `location` re-encodes the ENTIRE attributes blob.
    func testLocationEditPreservesMediaAndLinkKeysUnchanged() throws {
        let raw = #"""
        {
          "media": {"duration_s": 12.5, "file_name": "voice.m4a", "kind": "voice_note",
                     "transcript": {"status": "done", "model": "x", "chunks": 3}},
          "link": {"flavor": "video", "site_name": "YouTube", "video_id": "abc"},
          "location": {"label": "Old", "latitude": 1, "longitude": 2, "source": "manual"}
        }
        """#
        var attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        attrs.location = CapturedLocation(label: "New", latitude: 3, longitude: 4, source: "device-geolocation")

        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]

        let media = obj["media"] as! [String: Any]
        XCTAssertEqual(media["duration_s"] as? Double, 12.5)
        XCTAssertEqual(media["file_name"] as? String, "voice.m4a")
        XCTAssertEqual(media["kind"] as? String, "voice_note")
        let transcript = media["transcript"] as! [String: Any]
        XCTAssertEqual(transcript["status"] as? String, "done")
        XCTAssertEqual(transcript["model"] as? String, "x")
        XCTAssertEqual(transcript["chunks"] as? Double, 3)

        let link = obj["link"] as! [String: Any]
        XCTAssertEqual(link["flavor"] as? String, "video")
        XCTAssertEqual(link["site_name"] as? String, "YouTube")
        XCTAssertEqual(link["video_id"] as? String, "abc")

        let location = obj["location"] as! [String: Any]
        XCTAssertEqual(location["label"] as? String, "New")
    }

    /// Same fallback `testMalformedKnownKeyFallsBackToExtraWithoutThrowing` exercises for
    /// `location`, but for `media`: a keyed-container decode failure inside the leaf struct's own
    /// custom `init(from:)` (Task 5) must propagate the same way the old synthesized `Decodable`
    /// conformance did, so `ItemAttributes`'s `decodeKnownOrPreserveRaw` still catches it instead
    /// of failing the whole page decode.
    func testMalformedMediaValueFallsBackToExtraWithoutThrowing() throws {
        let raw = #"{"media":"oops","link":{"flavor":"video"}}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        XCTAssertNil(attrs.media)
        XCTAssertEqual(attrs.link?.flavor, "video")
        XCTAssertEqual(attrs.extra["media"], .string("oops"))

        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
        XCTAssertEqual(obj["media"] as? String, "oops")
    }

    // MARK: - JSONValue: bool/number decode-order gotcha (Foundation's NSNumber bridging can
    // make `1`/`0` decode successfully as Bool if you probe Bool before excluding numbers, or —
    // on some Foundation versions — make a JSON bool decode as a number. Pin both directions.

    func testNumberOneStaysNumberNotBool() throws {
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(#"{"n":1}"#.utf8))
        XCTAssertEqual(attrs.extra["n"], .number(1))
    }

    func testNumberZeroStaysNumberNotBool() throws {
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(#"{"n":0}"#.utf8))
        XCTAssertEqual(attrs.extra["n"], .number(0))
    }

    func testBoolTrueStaysBoolNotNumber() throws {
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(#"{"b":true}"#.utf8))
        XCTAssertEqual(attrs.extra["b"], .bool(true))
    }

    func testBoolFalseStaysBoolNotNumber() throws {
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(#"{"b":false}"#.utf8))
        XCTAssertEqual(attrs.extra["b"], .bool(false))
    }

    func testJSONValueFullRoundTripAllCases() throws {
        let raw = #"{"s":"str","n":1.5,"b":true,"z":null,"o":{"k":"v"},"a":[1,"two",false,null]}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        XCTAssertEqual(attrs.extra["s"], .string("str"))
        XCTAssertEqual(attrs.extra["n"], .number(1.5))
        XCTAssertEqual(attrs.extra["b"], .bool(true))
        XCTAssertEqual(attrs.extra["z"], .null)
        XCTAssertEqual(attrs.extra["o"], .object(["k": .string("v")]))
        XCTAssertEqual(attrs.extra["a"], .array([.number(1), .string("two"), .bool(false), .null]))

        // Round trip through encode must be byte-faithful in the JSONSerialization sense.
        let reencoded = try JSONEncoder().encode(attrs)
        let redecoded = try JSONDecoder().decode(ItemAttributes.self, from: reencoded)
        XCTAssertEqual(redecoded, attrs)
    }
}
