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
                          supplementalNote: String? = nil) -> Item {
        Item(id: UUID(), type: .link, title: title, content: nil, url: "https://example.com",
             filePath: nil, description: description, summary: "s", pageBody: pageBody,
             supplementalNote: supplementalNote, mimeType: nil, isPublic: false, createdAt: .now)
    }

    func testListRowRefreshPreservesLocalPageBodyButStillTakesNewerFields() {
        let local = fixture(description: "old description", pageBody: "loaded body")
        // A list-row refresh: no page_body column selected, but every other field is fresher.
        let incoming = fixture(description: "newer description", pageBody: nil)

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false)

        XCTAssertEqual(merged.pageBody, "loaded body",
                       "a list row's nil page_body must never clobber an already-loaded one")
        XCTAssertEqual(merged.description, "newer description",
                       "fields with no unsaved edit still take the fresher incoming value")
    }

    func testUnsavedTitleDefersToLocalRegardlessOfPageBody() {
        let local = fixture(title: "draft title in progress", pageBody: "loaded body")
        let incoming = fixture(title: "server title", pageBody: nil)

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: true,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false)

        XCTAssertEqual(merged.title, "draft title in progress",
                       "an in-flight unsaved title edit must never be overwritten by a stale incoming row")
        XCTAssertEqual(merged.pageBody, "loaded body", "the page_body guard applies independently of the title guard")
    }

    func testIncomingPageBodyFromDetailFetchReplacesLocal() {
        let local = fixture(pageBody: "stale cached body")
        // A detail fetch or PATCH response (Item.detailColumns): a real, non-nil page_body.
        let incoming = fixture(pageBody: "fresh full body")

        let merged = mergePreservingDetail(local: local, incoming: incoming, hasUnsavedTitle: false,
                                            hasUnsavedDescription: false, hasUnsavedSupplementalNote: false)

        XCTAssertEqual(merged.pageBody, "fresh full body",
                       "a non-nil incoming page_body is a real fetch and must always win")
    }
}
