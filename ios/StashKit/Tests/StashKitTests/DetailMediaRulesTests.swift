import XCTest
@testable import StashKit

final class DetailMediaRulesTests: XCTestCase {
    func testYouTubeVariantsUsePrivacyEmbedAndShortsArePortrait() throws {
        for address in ["https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://youtu.be/dQw4w9WgXcQ?t=15",
                        "https://m.youtube.com/live/dQw4w9WgXcQ", "https://youtube.com/embed/dQw4w9WgXcQ"] {
            let embed = try XCTUnwrap(DetailMediaRules.embed(for: address))
            XCTAssertEqual(embed.provider, .youtube)
            XCTAssertEqual(embed.url.absoluteString, "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0&enablejsapi=1&playsinline=1")
            XCTAssertFalse(embed.portrait)
            XCTAssertFalse(embed.url.absoluteString.contains("autoplay=1"))
        }
        let short = try XCTUnwrap(DetailMediaRules.embed(for: "https://youtube.com/shorts/dQw4w9WgXcQ"))
        XCTAssertTrue(short.portrait)
        XCTAssertEqual(short.aspectRatio, 9.0 / 16)
    }

    func testOtherSupportedVideoProviders() throws {
        let cases: [(String, DetailVideoEmbed.Provider, String, Bool)] = [
            ("https://vimeo.com/123456789", .vimeo, "https://player.vimeo.com/video/123456789", false),
            ("https://player.vimeo.com/video/123456789", .vimeo, "https://player.vimeo.com/video/123456789", false),
            ("https://www.loom.com/share/abcdef1234567890abcdef1234567890", .loom, "https://www.loom.com/embed/abcdef1234567890abcdef1234567890", false),
            ("https://www.tiktok.com/@person/video/1234567890123456789", .tiktok, "https://www.tiktok.com/embed/v2/1234567890123456789", true),
            ("https://www.instagram.com/reels/ABC_def-123/", .instagram, "https://www.instagram.com/reel/ABC_def-123/embed/", true),
            ("https://instagram.com/p/ABC_def-123/", .instagram, "https://www.instagram.com/p/ABC_def-123/embed/", true)
        ]
        for (address, provider, expected, portrait) in cases {
            let embed = try XCTUnwrap(DetailMediaRules.embed(for: address), address)
            XCTAssertEqual(embed.provider, provider)
            XCTAssertEqual(embed.url.absoluteString, expected)
            XCTAssertEqual(embed.portrait, portrait)
        }
    }

    func testCanonicalPrecedenceAndSavedAddressIsPreservedForOpeningOriginal() throws {
        var item = fixture(type: .link, url: "https://vm.tiktok.com/short/")
        let longURL = "https://www.tiktok.com/@person/video/1234567890123456789"
        item.attributes.extra["enrichment"] = .object(["evidence": .object(["canonical_url": .string(longURL)])])
        guard case .embed(let evidence) = try XCTUnwrap(DetailMediaRules.source(for: item)) else { return XCTFail("Expected resolved TikTok embed") }
        XCTAssertEqual(evidence.provider, .tiktok)
        XCTAssertEqual(evidence.originalURL.absoluteString, item.url)
        item.attributes.link = LinkAttributes(extra: ["canonical_url": .string("https://vimeo.com/123456789")])
        guard case .embed(let link) = try XCTUnwrap(DetailMediaRules.source(for: item)) else { return XCTFail("Expected link canonical embed") }
        XCTAssertEqual(link.provider, .vimeo)
        item.attributes = ItemAttributes()
        XCTAssertNil(DetailMediaRules.source(for: item), "Unresolved short links retain the image/open-original fallback")
    }

    func testUntrustedAndUnsupportedAddressesCannotBecomeEmbeds() {
        for address in ["javascript:alert(1)", "file:///tmp/video", "https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ",
                        "https://notyoutube.com/watch?v=dQw4w9WgXcQ", "https://youtu.be.evil.test/dQw4w9WgXcQ",
                        "https://user:password@youtube.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/watch?v=short",
                        "https://vm.tiktok.com/short", "https://tiktok.com/t/short", "https://vimeo.com/123",
                        "https://instagram.com/reel/%22%3Escript", "https://example.com/movie.mp4",
                        "https://docs.google.com/presentation/d/abc/edit", "https://www.figma.com/design/abc"] {
            XCTAssertNil(DetailMediaRules.embed(for: address), address)
        }
    }

    func testUploadedMediaUsesFileAndNeverTheLinkThumbnail() throws {
        let video = fixture(type: .video, filePath: "account/clip.mp4")
        XCTAssertEqual(DetailMediaRules.source(for: video), .file(url: StashConfig.publicStorageURL(for: "account/clip.mp4"), kind: .video))
        let audio = fixture(type: .audio, filePath: "https://cdn.example.com/voice.m4a")
        XCTAssertEqual(DetailMediaRules.source(for: audio), .file(url: URL(string: "https://cdn.example.com/voice.m4a")!, kind: .audio))
        XCTAssertNil(DetailMediaRules.source(for: fixture(type: .video)))
        XCTAssertNil(DetailMediaRules.source(for: fixture(type: .video, filePath: "file:///tmp/private.mp4")))
        XCTAssertNil(DetailMediaRules.source(for: fixture(type: .link, url: "https://example.com", filePath: "account/cover.jpg")))
        XCTAssertNil(DetailMediaRules.source(for: fixture(type: .image, filePath: "account/cover.jpg")))
    }

    private func fixture(type: ItemType, url: String? = nil, filePath: String? = nil) -> Item {
        Item(id: UUID(), type: type, title: nil, content: nil, url: url, filePath: filePath,
             description: nil, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
             isPublic: false, createdAt: .now)
    }
}
