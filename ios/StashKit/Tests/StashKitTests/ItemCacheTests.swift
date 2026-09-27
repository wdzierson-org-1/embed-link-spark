import XCTest
@testable import StashKit

final class ItemCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Millisecond-precision date — the precision `Item.decoder` keeps from Postgres timestamps.
    private func date(_ offsetMs: Int) -> Date {
        Date(timeIntervalSince1970: (1_790_000_000_000 + Double(offsetMs)) / 1000)
    }

    private func richItem() -> Item {
        let attributes = ItemAttributes(
            location: CapturedLocation(label: "Saratoga Springs", latitude: 43.08, longitude: -73.78,
                                       source: "device-geolocation", extra: ["place_id": .string("abc")]),
            link: LinkAttributes(flavor: "video", extra: ["video_id": .string("dQw4w9WgXcQ")]),
            media: MediaAttributes(durationS: 42.5, fileName: "memo.m4a",
                                   extra: ["kind": .string("voice_note"),
                                           "transcript": .object(["status": .string("done")])]),
            extra: ["enrichment": .object(["status": .string("done")]), "remind_at": .null])
        return Item(id: UUID(), type: .audio, title: "Memo", content: "{\"type\":\"doc\"}",
                    url: nil, filePath: "u/memo.m4a", description: "desc", summary: "sum",
                    pageBody: nil, supplementalNote: "note", mimeType: "audio/mp4", isPublic: true,
                    createdAt: date(123), fileSize: 2048, attributes: attributes)
    }

    func testRoundTripPreservesEveryListField() {
        let cache = ItemCache(directory: directory)
        let userId = UUID()
        let items = [richItem(),
                     Item(id: UUID(), type: .link, title: nil, content: nil, url: "https://example.com",
                          filePath: nil, description: nil, summary: nil, pageBody: nil, supplementalNote: nil,
                          mimeType: nil, isPublic: false, createdAt: date(-5_000))]
        XCTAssertTrue(cache.save(items, userId: userId))
        XCTAssertEqual(cache.load(userId: userId), items)
    }

    func testFileIsPerUserAndLowercased() {
        let cache = ItemCache(directory: directory)
        let userId = UUID(uuidString: "EDD5DA6E-EF3D-4F6A-BB56-C0AA8EA7E800")!
        XCTAssertEqual(cache.fileURL(for: userId).lastPathComponent, "edd5da6e-ef3d-4f6a-bb56-c0aa8ea7e800.json")
        cache.save([richItem()], userId: userId)
        XCTAssertEqual(cache.load(userId: UUID()), [], "another user's id must never read this snapshot")
    }

    func testMissingCorruptOrForeignFilesReadAsEmptyAndAreRemoved() throws {
        let cache = ItemCache(directory: directory)
        let userId = UUID()
        XCTAssertEqual(cache.load(userId: userId), [])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.fileURL(for: userId))
        XCTAssertEqual(cache.load(userId: userId), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(for: userId).path))

        // A file written for user A but found under user B's name is ignored.
        let other = UUID()
        cache.save([richItem()], userId: other)
        try FileManager.default.moveItem(at: cache.fileURL(for: other), to: cache.fileURL(for: userId))
        XCTAssertEqual(cache.load(userId: userId), [])
    }

    func testDeleteAndDeleteAll() {
        let cache = ItemCache(directory: directory)
        let a = UUID(), b = UUID()
        cache.save([richItem()], userId: a)
        cache.save([richItem()], userId: b)
        cache.delete(userId: a)
        XCTAssertEqual(cache.load(userId: a), [])
        XCTAssertEqual(cache.load(userId: b).count, 1)
        cache.deleteAll()
        XCTAssertEqual(cache.load(userId: b), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSaveOverwritesAtomically() {
        let cache = ItemCache(directory: directory)
        let userId = UUID()
        cache.save([richItem(), richItem()], userId: userId)
        let replacement = [richItem()]
        cache.save(replacement, userId: userId)
        XCTAssertEqual(cache.load(userId: userId), replacement)
    }
}
