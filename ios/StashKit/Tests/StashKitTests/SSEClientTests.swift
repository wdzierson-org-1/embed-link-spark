import XCTest
@testable import StashKit

final class SSEClientTests: XCTestCase {
    func testDeltaLine() {
        XCTAssertEqual(parseSSELine(#"data: {"delta":"hel"}"#), .delta("hel"))
        XCTAssertEqual(parseSSELine(#"data:{"delta":"lo"}"#), .delta("lo"))   // no space variant
    }
    func testDoneLineWithSources() {
        let line = #"data: {"done":true,"sources":[{"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b","title":"T","type":"document","url":null}]}"#
        guard case .done(let sources)? = parseSSELine(line) else { return XCTFail() }
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].title, "T")
    }
    func testDoneWithEmptySources() {
        XCTAssertEqual(parseSSELine(#"data: {"done":true,"sources":[]}"#), .done(sources: []))
    }
    func testErrorLine() {
        XCTAssertEqual(parseSSELine(#"data: {"error":"boom"}"#), .serverError("boom"))
    }
    func testIgnoredLines() {
        XCTAssertNil(parseSSELine(""))
        XCTAssertNil(parseSSELine(": keepalive"))
        XCTAssertNil(parseSSELine("event: message"))
        XCTAssertNil(parseSSELine("data: not-json"))
    }
}
