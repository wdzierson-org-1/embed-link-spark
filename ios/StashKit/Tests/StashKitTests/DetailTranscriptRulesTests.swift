import XCTest
@testable import StashKit

final class DetailTranscriptRulesTests: XCTestCase {
    private func item(_ type: ItemType = .link, flavor: String? = "video", evidence: JSONValue? = nil) -> Item {
        var item = Item(id: UUID(), type: type, title: nil, content: nil, url: nil,
                        filePath: nil, description: nil, summary: nil, pageBody: nil,
                        supplementalNote: nil, mimeType: nil, isPublic: false, createdAt: .now)
        item.pageBody = "Captured source words"
        item.attributes.link = LinkAttributes(flavor: flavor)
        if let evidence { item.attributes.extra["enrichment"] = .object(["evidence": .object(["transcript": evidence])]) }
        return item
    }

    func testVideoLinksKeepPageTextUnderOriginalUntilTranscriptIsProven() {
        for evidence in [nil, JSONValue.bool(false), .string("true")] {
            let item = item(evidence: evidence)
            XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .original, .transcript])
            XCTAssertEqual(contentTabsConfig(for: item).defaultTab, .summary)
            XCTAssertNil(transcriptText(for: item), "Navigation/page text must never be labelled as a transcript")
        }
    }

    func testCapturedVideoTranscriptReplacesOriginalTab() {
        let item = item(evidence: .bool(true))
        XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .transcript])
        XCTAssertEqual(transcriptText(for: item), "Captured source words")
    }

    func testRecordingsKeepTranscriptFirstAndGainSummaryBesideIt() {
        for type in [ItemType.audio, .video] {
            let item = item(type, flavor: nil)
            XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .transcript])
            XCTAssertEqual(contentTabsConfig(for: item).defaultTab, .transcript)
            XCTAssertEqual(transcriptText(for: item), item.pageBody)
        }
    }

    func testOrdinarySourcesDoNotBecomeTranscriptsFromStrayEvidence() {
        for item in [item(flavor: "article", evidence: .bool(true)), item(.document, flavor: nil, evidence: .bool(true))] {
            XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .original])
            XCTAssertNil(transcriptText(for: item))
        }
    }

    func testNewTranscriptEvidenceDoesNotRelabelAnOlderLoadedPageAsTranscript() {
        let old = item(evidence: .bool(false))
        var incoming = old
        incoming.pageBody = nil // Realtime list rows omit this field.
        incoming.attributes.extra["enrichment"] = .object(["evidence": .object(["transcript": .bool(true)])])
        let merged = mergePreservingDetail(local: old, incoming: incoming, hasUnsavedTitle: false,
                                           hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                           hasUnsavedLocation: false)
        XCTAssertNil(transcriptText(for: merged), "Wait for the new source read instead of reusing navigation text")
        incoming.pageBody = "Real transcript"
        let fetched = mergePreservingDetail(local: old, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false)
        XCTAssertEqual(transcriptText(for: fetched), "Real transcript")
    }
}
