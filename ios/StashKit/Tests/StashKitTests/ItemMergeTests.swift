import XCTest
@testable import StashKit

/// `mergePreservingDetail` (finding #2, final review): `ItemDetailView.adopt(_:)` used to build
/// this merge inline and took `incoming.pageBody` unconditionally — but `store.refresh()` (the
/// realtime-triggered path) re-queries with `Item.listColumns`, which never selects `page_body`,
/// so every realtime refresh while a detail sheet was open nulled an already-loaded page_body and
/// flipped the Original Content/Transcript tab to its empty state until the sheet was reopened.
/// This file exercises the extracted pure function directly; `ItemDetailView.adopt(_:)` itself is
/// only a thin wrapper that computes the three `hasUnsaved*` flags from `item`/`snapshot` and
/// delegates here (no separate coverage needed for that wrapper — see task-8/9's `changedFields`
/// precedent for the same split between a StashKit pure function and its view-layer call site).
final class ItemMergeTests: XCTestCase {
    /// Mirrors `ItemRulesTests.fixture` but also varies `pageBody`, which that fixture always
    /// pins to `nil` (irrelevant to `ItemRulesTests`'s own cases, load-bearing for these).
    private func fixture(title: String? = "t", description: String? = "d", pageBody: String? = nil,
                          supplementalNote: String? = nil, attributes: ItemAttributes = ItemAttributes()) -> Item {
        Item(id: UUID(), type: .link, title: title, content: nil, url: "https://example.com",
             filePath: nil, description: description, summary: "s", pageBody: pageBody,
             supplementalNote: supplementalNote, mimeType: nil, isPublic: false, createdAt: .now,
             fileSize: nil, attributes: attributes)
    }

    func testListRowRefreshPreservesLocalPageBodyButStillTakesNewerFields() {
        let local = fixture(description: "old description", pageBody: "loaded body")
        // A list-row refresh: no page_body column selected, but every other field is fresher.
        let incoming = fixture(description: "newer description", pageBody: nil)

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false)

        XCTAssertEqual(merged.pageBody, "loaded body",
                       "a list row's nil page_body must never clobber an already-loaded one")
        XCTAssertEqual(merged.description, "newer description",
                       "fields with no unsaved edit still take the fresher incoming value")
    }

    func testUnsavedTitleDefersToLocalRegardlessOfPageBody() {
        let local = fixture(title: "draft title in progress", pageBody: "loaded body")
        let incoming = fixture(title: "server title", pageBody: nil)

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: true,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false)

        XCTAssertEqual(merged.title, "draft title in progress",
                       "an in-flight unsaved title edit must never be overwritten by a stale incoming row")
        XCTAssertEqual(merged.pageBody, "loaded body", "the page_body guard applies independently of the title guard")
    }

    func testIncomingPageBodyFromDetailFetchReplacesLocal() {
        let local = fixture(pageBody: "stale cached body")
        // A detail fetch or PATCH response (Item.detailColumns): a real, non-nil page_body.
        let incoming = fixture(pageBody: "fresh full body")

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false)

        XCTAssertEqual(merged.pageBody, "fresh full body",
                       "a non-nil incoming page_body is a real fetch and must always win")
    }

    // MARK: - hasUnsavedLocation (Task 8)
    //
    // Same shape as the title/description/supplementalNote flags above, but for `attributes` —
    // the detail sheet's `LocationRow` writes `item.attributes` optimistically the instant a
    // location edit commits (`ItemDetailView.attributesBinding`), before that edit's own PATCH
    // response has landed. Unlike `pageBody`, `attributes` IS part of `Item.listColumns`, so a
    // realtime list-row refresh racing in during that window carries a REAL (not omitted)
    // attributes value — one that predates this edit — and would clobber it without this guard.

    func testHasUnsavedLocationDefersAttributesToLocal() {
        let localAttrs = ItemAttributes(location: CapturedLocation(label: "Test City", source: "manual"))
        let staleIncomingAttrs = ItemAttributes(location: CapturedLocation(label: "Stale Town", source: "device-geolocation"))
        let local = fixture(attributes: localAttrs)
        let incoming = fixture(attributes: staleIncomingAttrs)

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: true)

        XCTAssertEqual(merged.attributes, localAttrs,
                       "an in-flight unsaved location edit must never be overwritten by a stale incoming row")
    }

    func testNoUnsavedLocationTakesIncomingAttributes() {
        let localAttrs = ItemAttributes(location: CapturedLocation(label: "Old", source: "manual"))
        let freshIncomingAttrs = ItemAttributes(location: CapturedLocation(label: "Fresh", source: "manual"))
        let local = fixture(attributes: localAttrs)
        let incoming = fixture(attributes: freshIncomingAttrs)

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false)

        XCTAssertEqual(merged.attributes, freshIncomingAttrs,
                       "with no unsaved location edit in flight, a fresher incoming attributes blob wins")
    }

    // MARK: - hasUnsavedContent (Plan 8, fix round 1, review finding #2)
    //
    // Same shape as the four flags above, for `content` — an unrelated incoming row (a realtime
    // broadcast, or a detail re-fetch) must never clobber a notes edit that's genuinely still in
    // flight locally.

    private func contentFixture(content: String?) -> Item {
        Item(id: UUID(), type: .link, title: "t", content: content, url: "https://example.com",
             filePath: nil, description: "d", summary: "s", pageBody: nil,
             supplementalNote: nil, mimeType: nil, isPublic: false, createdAt: .now,
             fileSize: nil, attributes: ItemAttributes())
    }

    func testHasUnsavedContentDefersToLocal() {
        let local = contentFixture(content: "draft note in progress")
        let incoming = contentFixture(content: "stale server content")

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false, hasUnsavedContent: true)

        XCTAssertEqual(merged.content, "draft note in progress",
                       "an in-flight unsaved content edit must never be overwritten by a stale incoming row")
    }

    func testNoUnsavedContentTakesIncoming() {
        let local = contentFixture(content: "old content")
        let incoming = contentFixture(content: "fresh content")

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false, hasUnsavedContent: false)

        XCTAssertEqual(merged.content, "fresh content",
                       "with no unsaved content edit in flight, a fresher incoming content wins")
    }

    func testHasUnsavedContentDefaultsToFalseForExistingCallSites() {
        // Every OTHER call in this file omits `hasUnsavedContent` entirely — the default (`false`)
        // must behave exactly like passing it explicitly, so those calls don't silently change
        // behavior just because this parameter exists now.
        let local = contentFixture(content: "old content")
        let incoming = contentFixture(content: "fresh content")

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false,
                                            hasUnsavedLocation: false)

        XCTAssertEqual(merged.content, "fresh content", "omitting hasUnsavedContent must default to false")
    }
}
