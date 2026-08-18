import XCTest
@testable import StashKit

/// `ItemAttributes` is the loss-less model for the `items.attributes` jsonb column: the web app's
/// edit flows PATCH the whole column (never a per-key merge — see ItemEditor.swift's restBody
/// comment for the same whole-value-replace convention on other fields), so an iOS decode-then-
/// reencode round trip must never drop a key it doesn't recognize. `location`/`link`/`media` are
/// decoded typed for call sites that read them; everything else funnels into `extra` and is
/// written straight back on encode.
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

    /// Nested unknown keys (inside `location`/`link`/`media`) do NOT round-trip — only the
    /// top-level blob is loss-less. The web replaces these sub-objects wholesale on every edit
    /// (same whole-value convention as the top-level column), so there's no scenario where an
    /// iOS-authored PATCH needs to preserve a leaf key it doesn't understand; keeping the leaf
    /// structs plain Codable avoids three more copies of the AnyKey machinery for no behavioral
    /// gain.
    func testNestedUnknownKeysAreDroppedNotPreserved() throws {
        let raw = #"{"location":{"label":"L","source":"manual","weird_new_field":"x"}}"#
        let attrs = try JSONDecoder().decode(ItemAttributes.self, from: Data(raw.utf8))
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(attrs)) as! [String: Any]
        let location = obj["location"] as! [String: Any]
        XCTAssertNil(location["weird_new_field"])
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
        let obj = attrs.jsonObject()
        // Must be usable directly as a request body without any further conversion.
        XCTAssertTrue(JSONSerialization.isValidJSONObject(obj))
        let link = obj["link"] as! [String: Any]
        XCTAssertEqual(link["flavor"] as? String, "video")
        XCTAssertEqual(obj["mood"] as? String, "good")
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
