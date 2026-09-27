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

    /// chat-with-all-content's optional tool-round frames (index.ts: `emit({ status, query? })`).
    func testStatusLines() {
        XCTAssertEqual(parseSSELine(#"data: {"status":"searching","query":"persimmons"}"#), .status(.searching))
        XCTAssertEqual(parseSSELine(#"data: {"status":"browsing"}"#), .status(.browsing))
        XCTAssertEqual(parseSSELine(#"data:{"status":"reading"}"#), .status(.reading))
        // Optional frames: an unknown status is ignored, never mis-labelled.
        XCTAssertNil(parseSSELine(#"data: {"status":"thinking"}"#))
        XCTAssertNil(parseSSELine(#"data: {"status":42}"#))
    }

    func testStatusLabels() {
        XCTAssertEqual(ChatStreamStatus.searching.label, "Searching your stash…")
        XCTAssertEqual(ChatStreamStatus.browsing.label, "Browsing your stash…")
        XCTAssertEqual(ChatStreamStatus.reading.label, "Reading…")
    }
}

final class StreamingTextCoalescerTests: XCTestCase {
    func testFirstDeltaPublishesImmediatelyThenAtMostOncePerInterval() {
        var coalescer = StreamingTextCoalescer(interval: 0.1)
        XCTAssertEqual(coalescer.append("A", at: 10.00), "A", "First token is never held")
        XCTAssertNil(coalescer.append("B", at: 10.03))
        XCTAssertNil(coalescer.append("C", at: 10.09))
        XCTAssertEqual(coalescer.append("D", at: 10.11), "ABCD", "Interval elapsed — publish everything so far")
        XCTAssertNil(coalescer.append("E", at: 10.15))
        XCTAssertEqual(coalescer.text, "ABCDE")
    }

    func testFlushPublishesHeldTextOnceTheIntervalElapses() {
        var coalescer = StreamingTextCoalescer(interval: 0.1)
        XCTAssertNil(coalescer.flush(at: 0), "Nothing received yet")
        XCTAssertEqual(coalescer.append("A", at: 1.00), "A")
        XCTAssertNil(coalescer.flush(at: 1.05), "Nothing held since the last publish")
        XCTAssertNil(coalescer.append("B", at: 1.06))
        XCTAssertNil(coalescer.flush(at: 1.08), "Still inside the interval — at most one publish per interval")
        XCTAssertEqual(coalescer.flush(at: 1.11), "AB")
        XCTAssertNil(coalescer.flush(at: 1.13), "Already published")
        // A flush restarts the interval like a publish does.
        XCTAssertNil(coalescer.append("C", at: 1.16))
        XCTAssertEqual(coalescer.append("D", at: 1.25), "ABCD")
    }

    func testZeroIntervalPublishesEveryDelta() {
        var coalescer = StreamingTextCoalescer(interval: 0)
        XCTAssertEqual(coalescer.append("A", at: 5), "A")
        XCTAssertEqual(coalescer.append("B", at: 5), "AB")
    }
}
