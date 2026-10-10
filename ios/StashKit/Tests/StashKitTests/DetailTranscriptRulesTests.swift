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

    func testVideoLinksHaveOnlySummaryAndTranscriptWhileWaitingForProvenTranscript() {
        for evidence in [nil, JSONValue.bool(false), .string("true")] {
            let item = item(evidence: evidence)
            XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .transcript])
            XCTAssertEqual(contentTabsConfig(for: item).defaultTab, .summary)
            XCTAssertNil(transcriptText(for: item), "Navigation/page text must never be labelled as a transcript")
        }
    }

    func testCapturedVideoTranscriptPopulatesTheExistingTranscriptTab() {
        let item = item(evidence: .bool(true))
        XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .transcript])
        XCTAssertEqual(transcriptText(for: item), "Captured source words")
    }

    func testKnownVideoURLsWithoutFlavorUseVideoTabsButStillRequireTranscriptEvidence() {
        let addresses = [
            "https://www.youtube.com/watch?v=M7lc1UVf-VE", "https://vimeo.com/123456789",
            "https://www.loom.com/share/abcdef1234567890abcdef1234567890",
            "https://www.tiktok.com/@person/video/1234567890123456789",
            "https://www.instagram.com/reel/ABC_def-123/", "https://www.instagram.com/tv/ABC_def-123/"
        ]
        for address in addresses {
            for evidence in [nil, JSONValue.bool(false), .string("true"), .bool(true)] {
                var item = item(flavor: nil, evidence: evidence)
                item.attributes.link = nil
                item.url = address
                XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .transcript], address)
                XCTAssertEqual(contentTabsConfig(for: item).defaultTab, .summary)
                XCTAssertEqual(transcriptText(for: item), evidence == .bool(true) ? item.pageBody : nil,
                               "A recognized video URL alone never proves its page body is a transcript")
            }
        }
    }

    func testEditedVideoURLKeepsVideoTabsAfterOldFlavorAndTranscriptEvidenceAreRemoved() {
        var old = item(evidence: .bool(true))
        old.url = "https://www.youtube.com/watch?v=M7lc1UVf-VE"
        old.attributes.link?.extra["canonical_url"] = .string(old.url!)
        let edited = LinkAddressEdit.applying("https://youtu.be/dQw4w9WgXcQ", to: old)
        XCTAssertNil(edited.attributes.link)
        XCTAssertEqual(contentTabsConfig(for: edited).tabs.map(\.key), [.summary, .transcript])
        XCTAssertEqual(edited.pageBody, old.pageBody, "Editing must retain captured text without relabelling it")
        XCTAssertNil(transcriptText(for: edited))
    }

    func testResolvedVideoCanonicalURLWithoutFlavorUsesVideoTabs() {
        var item = item(flavor: nil)
        item.url = "https://vm.tiktok.com/short/"
        item.attributes.extra["enrichment"] = .object(["evidence": .object([
            "canonical_url": .string("https://www.tiktok.com/@person/video/1234567890123456789")
        ])])
        XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .transcript])
        XCTAssertNil(transcriptText(for: item))
    }

    func testAmbiguousPostsAndNonVideoURLsKeepOriginalContentWithoutFlavor() {
        for address in ["https://www.instagram.com/p/ABC_def-123/", "https://example.com/article",
                        "https://youtube.com.evil.test/watch?v=M7lc1UVf-VE"] {
            var item = item(flavor: nil, evidence: .bool(true))
            item.url = address
            XCTAssertEqual(contentTabsConfig(for: item).tabs.map(\.key), [.summary, .original])
            XCTAssertNil(transcriptText(for: item))
        }
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
        assertNewTranscriptWaitsForItsBody(item(evidence: .bool(false)))
        var withoutFlavor = item(flavor: nil, evidence: .bool(false))
        withoutFlavor.url = "https://www.youtube.com/watch?v=M7lc1UVf-VE"
        assertNewTranscriptWaitsForItsBody(withoutFlavor)
    }

    private func assertNewTranscriptWaitsForItsBody(_ old: Item) {
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
