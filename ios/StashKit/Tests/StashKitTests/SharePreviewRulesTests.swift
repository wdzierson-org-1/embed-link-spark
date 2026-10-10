import XCTest
@testable import StashKit

final class SharePreviewRulesTests: XCTestCase {
    func testSuppliedTitleWinsOverModelAndOCR() {
        XCTAssertEqual(SharePreviewRules.title(supplied: "  My copy of Walden  ", enriched: "A book cover", fallback: "Image"), "My copy of Walden")
        XCTAssertEqual(SharePreviewRules.title(supplied: "\n", enriched: "Walden", fallback: "Image"), "Walden")
    }

    func testOCRQuotesObservedWordsWithoutClaimingBookIdentification() {
        XCTAssertEqual(SharePreviewRules.recognizedText(["  WALDEN  ", "Henry David Thoreau"]),
                       SharePreviewText(title: "“WALDEN”", summary: "Text found in image"))
        XCTAssertEqual(SharePreviewRules.recognizedText(["Quarterly report"], document: true)?.summary, "Text found on first page")
        XCTAssertNil(SharePreviewRules.recognizedText(["", " ", "x"]))
    }

    func testTextIsNormalizedAndBoundedBeforeDisplaying() {
        XCTAssertEqual(SharePreviewRules.clean(" one\n\t two \u{0000} three ", limit: 11), "one two thr")
        XCTAssertNil(SharePreviewRules.clean(" \n\t "))
        XCTAssertEqual(SharePreviewRules.clean(String(repeating: "字", count: 1_000))?.count, 160)
    }

    func testOnlyOrdinaryPublicWebAddressesQualifyForRemotePreview() {
        XCTAssertEqual(SharePreviewRules.publicWebURL("https://www.gostash.it/article?q=a")?.host, "www.gostash.it")
        for address in ["file:///tmp/a", "ftp://gostash.it/a", "https://user:pass@gostash.it/", "http://localhost/", "http://printer.local/", "http://intranet/", "http://127.0.0.1/", "http://192.168.1.1/", "http://169.254.169.254/", "http://2130706433/", "http://0x7f000001/", "http://[::1]/", "http://[fe80::1]/", "https://gostash.it:444/"] {
            XCTAssertNil(SharePreviewRules.publicWebURL(address), address)
        }
    }

    func testDeadlineReturnsFallbackWithoutWaitingForNonCooperativeWork() async {
        let start = ContinuousClock.now
        let value = await withDeadline(.milliseconds(30), fallback: "local") {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { continuation.resume(returning: "late remote") }
            }
        }
        XCTAssertEqual(value, "local")
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
    }
}
