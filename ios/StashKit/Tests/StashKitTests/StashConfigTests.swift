import XCTest
@testable import StashKit

final class StashConfigTests: XCTestCase {
    func testPublicStorageURL() {
        let url = StashConfig.publicStorageURL(for: "abc/file.png")
        XCTAssertEqual(url.absoluteString,
            "https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/abc/file.png")
    }
}
