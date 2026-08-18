import Foundation

/// A loss-less representation of an arbitrary JSON value, used by `ItemAttributes.extra` to hold
/// every top-level key of `items.attributes` this build doesn't know about yet, so a decode →
/// re-encode round trip (the whole-column PATCH-replace the edit flows use) never drops data a
/// newer web build wrote.
///
/// Decode order is deliberate: `null` is checked first (a dedicated, non-throwing check), then
/// `Bool` before `Double`. Foundation's `JSONDecoder` has shipped versions where an `NSNumber`-
/// backed decode is lenient in one direction or the other at this boundary (a JSON `1`/`0` read
/// as `Bool`, or a JSON `true`/`false` read as a number) — probing `Bool` first and asserting the
/// literal shape pins the intended mapping so `{"n":1}` always stays `.number(1)`, never `.bool`.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }
}
