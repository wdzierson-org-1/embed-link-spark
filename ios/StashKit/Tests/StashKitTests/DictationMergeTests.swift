import XCTest
@testable import StashKit

final class DictationMergeTests: XCTestCase {
    func testEmptyPrefixReturnsInterimVerbatim() {
        XCTAssertEqual(mergeDictation(prefix: "", interim: "hello world"), "hello world")
    }

    func testTypedPrefixGetsASingleSeparatingSpace() {
        XCTAssertEqual(mergeDictation(prefix: "check this", interim: "out now"), "check this out now")
    }

    func testPrefixWithTrailingSpaceIsNotDoubleSpaced() {
        XCTAssertEqual(mergeDictation(prefix: "check this ", interim: "out now"), "check this out now")
    }
}
