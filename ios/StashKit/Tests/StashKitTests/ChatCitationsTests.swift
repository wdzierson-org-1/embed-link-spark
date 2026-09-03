import XCTest
@testable import StashKit

/// Port of src/utils/chatCitations.test.ts's `bakeCitationLinks` suite, adapted to
/// `ChatCitations.link`'s combined bake+track interface (`linkedSourceIDs` derived by re-scanning
/// the result rather than re-extracted from the text via a separate call afterward — see
/// `ChatCitations.swift`'s doc comment for why that also covers already-baked/reloaded text).
final class ChatCitationsTests: XCTestCase {
    private let sourceOne = ChatSource(id: UUID(), title: "Feeding notes", type: "text", url: nil, n: 1)
    private let sourceThree = ChatSource(id: UUID(), title: "My Note", type: "text", url: nil, n: 3)

    /// `[Title](#3)` → `[Title](#item=<uuid>)` (web: bakeCitationLinks's "rewrites linked titles
    /// to item links") — using the web's own `#item=` convention (fix round 1: cross-platform
    /// persisted content must render identically on both sides).
    func testLinkedTitleForm() {
        let result = ChatCitations.link(answer: "See [My Note](#3) for details.", sources: [sourceThree])
        XCTAssertEqual(result.text, "See [My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) for details.")
        XCTAssertEqual(result.linkedSourceIDs, [sourceThree.id])
    }

    /// Bare `[1]` → `[[1]](#item=<uuid>)` (web: "wraps bare bracket markers as bracketed links").
    func testBareMarkerForm() {
        let result = ChatCitations.link(answer: "Feed at 8am [1].", sources: [sourceOne])
        XCTAssertEqual(result.text, "Feed at 8am [[1]](\(ChatCitations.itemLinkPrefix)\(sourceOne.id.uuidString)).")
        XCTAssertEqual(result.linkedSourceIDs, [sourceOne.id])
    }

    /// Running `link` again on already-baked text is a text no-op — the inner `[1]` of
    /// `[[1]](url)` is preceded by `[`, so the bare-marker pass skips it (web: "does not
    /// double-bake already-baked content") — AND still reports the same `linkedSourceIDs` both
    /// times, since those are derived by re-scanning the result, not by what got freshly baked
    /// this call (fix round 1: this is what makes a reloaded, already-baked message's chip
    /// fallback filter correctly without needing `sources` at all).
    func testAlreadyLinkedSkipped() {
        let baked = ChatCitations.link(answer: "Feed at 8am [1].", sources: [sourceOne])
        let rebaked = ChatCitations.link(answer: baked.text, sources: [sourceOne])
        XCTAssertEqual(rebaked.text, baked.text)
        XCTAssertEqual(rebaked.linkedSourceIDs, baked.linkedSourceIDs)
        XCTAssertEqual(baked.linkedSourceIDs, [sourceOne.id])
    }

    /// Fix round 1: a message that arrives ALREADY baked (e.g. reloaded from persisted history)
    /// still reports the linked id even with an empty `sources` array — the reload path has no
    /// `n` mapping to rebake with, but the link is already there in the text.
    func testAlreadyBakedTextDetectedWithoutSources() {
        let result = ChatCitations.link(answer: "See [My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) for details.", sources: [])
        XCTAssertEqual(result.linkedSourceIDs, [sourceThree.id])
    }

    /// The legacy `stash://item/` form (round 1's brief window before the prefix was corrected to
    /// match the web) is still recognized on read, so nothing baked that way goes dead.
    func testLegacyPrefixStillDetected() {
        let result = ChatCitations.link(answer: "See [My Note](\(ChatCitations.legacyItemLinkPrefix)\(sourceThree.id.uuidString)) for details.", sources: [])
        XCTAssertEqual(result.linkedSourceIDs, [sourceThree.id])
    }

    /// A citation number with no matching source is left untouched (web: "leaves unknown numbers
    /// alone").
    func testUnknownNumberUntouched() {
        let result = ChatCitations.link(answer: "See [7] for details.", sources: [sourceOne, sourceThree])
        XCTAssertEqual(result.text, "See [7] for details.")
        XCTAssertTrue(result.linkedSourceIDs.isEmpty)
    }

    /// Both forms together in one answer, unknown numbers untouched among them (web: "handles
    /// both forms together and leaves unknown numbers alone").
    func testMultipleMarkers() {
        let input = "[My Note](#3) says X [1], and [7] is unknown."
        let result = ChatCitations.link(answer: input, sources: [sourceOne, sourceThree])
        XCTAssertEqual(result.text,
            "[My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) says X [[1]](\(ChatCitations.itemLinkPrefix)\(sourceOne.id.uuidString)), and [7] is unknown.")
        XCTAssertEqual(result.linkedSourceIDs, [sourceOne.id, sourceThree.id])
    }

    /// No sources (or sources without a citation number at all) → unchanged text, empty set (web:
    /// "is a no-op without citation numbers"). This is the raw-marker-with-empty-sources case a
    /// reloaded pre-fix-round-1 history row hits: `link` itself leaves it exactly as stored —
    /// `stripUnresolvedMarkers` (tested separately below), not `link`, is what keeps a leftover
    /// `[Title](#N)` from rendering as a dead link.
    func testNoSourcesUnchanged() {
        let unnumbered = ChatSource(id: UUID(), title: "x", type: nil, url: nil)
        let result = ChatCitations.link(answer: "Plain [1] text.", sources: [unnumbered])
        XCTAssertEqual(result.text, "Plain [1] text.")
        XCTAssertTrue(result.linkedSourceIDs.isEmpty)

        let empty = ChatCitations.link(answer: "Plain [1] text.", sources: [])
        XCTAssertEqual(empty.text, "Plain [1] text.")
        XCTAssertTrue(empty.linkedSourceIDs.isEmpty)
    }

    /// A non-numeric bracket (`[abc]`) is never a citation marker — untouched.
    func testMalformedBracketUntouched() {
        let result = ChatCitations.link(answer: "See [abc] for details.", sources: [sourceOne, sourceThree])
        XCTAssertEqual(result.text, "See [abc] for details.")
        XCTAssertTrue(result.linkedSourceIDs.isEmpty)
    }

    // MARK: - stripUnresolvedMarkers

    /// The dead-link case fix round 1 exists for: a leftover `[Title](#N)` (no matching source —
    /// reloaded history with no `n` mapping, or a genuinely unknown citation number) strips down
    /// to plain, non-tappable `Title` text instead of staying a live-looking violet link to
    /// nowhere.
    func testStripUnresolvedMarkerDropsDeadLink() {
        XCTAssertEqual(ChatCitations.stripUnresolvedMarkers("See [My Note](#3) for details."),
                       "See My Note for details.")
    }

    /// A marker that DID resolve (`#item=`/legacy `stash://item/`) is a different, unaffected
    /// pattern — left fully intact.
    func testStripUnresolvedMarkerLeavesResolvedLinksIntact() {
        let resolved = "See [My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) for details."
        XCTAssertEqual(ChatCitations.stripUnresolvedMarkers(resolved), resolved)
        let legacy = "See [My Note](\(ChatCitations.legacyItemLinkPrefix)\(sourceThree.id.uuidString)) for details."
        XCTAssertEqual(ChatCitations.stripUnresolvedMarkers(legacy), legacy)
    }

    /// A bare unresolved marker (`[7]`) was never link syntax to begin with — nothing to strip.
    func testStripUnresolvedMarkerLeavesBareMarkersAlone() {
        XCTAssertEqual(ChatCitations.stripUnresolvedMarkers("See [7] for details."), "See [7] for details.")
    }

    /// Resolved and unresolved together: only the dead one gets stripped.
    func testStripUnresolvedMarkerMixed() {
        let input = "[My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) and [Other](#9)."
        XCTAssertEqual(ChatCitations.stripUnresolvedMarkers(input),
                       "[My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) and Other.")
    }

    // MARK: - itemID(from:)

    func testItemIDFromFragmentForm() {
        let id = UUID()
        let url = URL(string: "\(ChatCitations.itemLinkPrefix)\(id.uuidString)")!
        XCTAssertEqual(ChatCitations.itemID(from: url), id)
    }

    func testItemIDFromLegacySchemeForm() {
        let id = UUID()
        let url = URL(string: "\(ChatCitations.legacyItemLinkPrefix)\(id.uuidString)")!
        XCTAssertEqual(ChatCitations.itemID(from: url), id)
    }

    func testItemIDNilForUnrelatedURLs() {
        XCTAssertNil(ChatCitations.itemID(from: URL(string: "#3")!))
        XCTAssertNil(ChatCitations.itemID(from: URL(string: "https://example.com")!))
    }
}
