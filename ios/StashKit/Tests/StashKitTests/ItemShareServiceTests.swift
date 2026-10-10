import XCTest
@testable import StashKit

private actor ShareStore: ItemShareStoring {
    var state: ItemShareState?
    var writes: [ItemShareMutation] = []
    var competingToken: String?
    var failWrite = false
    init(_ state: ItemShareState?) { self.state = state }
    func compete(with token: String) { competingToken = token }
    func fail() { failWrite = true }
    func read(itemID: UUID, userID: UUID) async throws -> ItemShareState? { state }
    func replace(itemID: UUID, userID: UUID, expectedToken: String?, with mutation: ItemShareMutation) async throws -> ItemShareState? {
        writes.append(mutation)
        if failWrite { throw URLError(.notConnectedToInternet) }
        if let competingToken { state = .init(token: competingToken, sharedAt: "prior"); self.competingToken = nil }
        guard state?.token == expectedToken, state != nil else { return nil }
        state = .init(token: mutation.token, sharedAt: mutation.sharedAt)
        return state
    }
}

final class ItemShareServiceTests: XCTestCase {
    let itemID = UUID(), userID = UUID()
    let token = "AbCd012345"

    func testTokenMatchesWebShapeAndURLHasThePublicOrigin() {
        let tokens = (0..<128).map { _ in ItemShareToken.mint() }
        XCTAssertTrue(tokens.allSatisfy { $0.count == 10 && ItemShareToken.isValid($0) })
        XCTAssertEqual(Set(tokens).count, 128)
        XCTAssertEqual(ItemShareState(token: token).url?.absoluteString, "https://www.gostash.it/s/AbCd012345")
        for value in ["", "short", "../foo?bar", "abcdefghijk", "AbCd01234é"] {
            XCTAssertNil(ItemShareState(token: value).url)
        }
    }

    func testMutationWritesOnlyShareColumnsAndRevokesBothWithExplicitNull() throws {
        let data = try JSONEncoder().encode(ItemShareMutation(token: nil, sharedAt: nil))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["share_token", "shared_at"])
        XCTAssertTrue(body["share_token"] is NSNull)
        XCTAssertTrue(body["shared_at"] is NSNull)
    }

    func testOpeningExistingLinkKeepsItsTokenAndTimestampWithoutWrite() async throws {
        let existing = ItemShareState(token: token, sharedAt: "2026-10-09T15:00:00Z")
        let store = ShareStore(existing)
        let value = try await ItemShareService(store: store).share(itemID: itemID, userID: userID)
        XCTAssertEqual(value, existing)
        let writes = await store.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testNewSharePublishesOnlyAfterTheOwnerWriteSucceeds() async throws {
        let store = ShareStore(.init())
        let value = try await ItemShareService(store: store, mintToken: { "AbCd012345" }).share(itemID: itemID, userID: userID)
        XCTAssertEqual(value.token, token)
        XCTAssertNotNil(value.sharedAt)
        let writes = await store.writes
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.token, token)
    }

    func testFailedWriteDoesNotReturnAWorkingLink() async {
        let store = ShareStore(.init())
        await store.fail()
        do { _ = try await ItemShareService(store: store).share(itemID: itemID, userID: userID); XCTFail("Must not claim a link exists") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let state = await store.state
        XCTAssertNil(state?.token)
    }

    func testConcurrentShareUsesWinnerWithoutRotatingTheirLink() async throws {
        let store = ShareStore(.init())
        await store.compete(with: "ZyXw987654")
        let value = try await ItemShareService(store: store).share(itemID: itemID, userID: userID)
        XCTAssertEqual(value.token, "ZyXw987654")
    }

    func testRevokeClearsLinkAndStaleRevokeCannotKillANewerLink() async throws {
        let store = ShareStore(.init(token: token, sharedAt: "prior"))
        let service = ItemShareService(store: store)
        let cleared = try await service.revoke(itemID: itemID, userID: userID, token: token)
        XCTAssertNil(cleared.token)
        XCTAssertNil(cleared.sharedAt)
        let changed = ShareStore(.init(token: "ZyXw987654", sharedAt: "new"))
        do { _ = try await ItemShareService(store: changed).revoke(itemID: itemID, userID: userID, token: token); XCTFail("Must not revoke another link") }
        catch { XCTAssertEqual(error as? ItemShareError, .changedElsewhere) }
        let state = await changed.state
        XCTAssertEqual(state?.token, "ZyXw987654")
    }
}
