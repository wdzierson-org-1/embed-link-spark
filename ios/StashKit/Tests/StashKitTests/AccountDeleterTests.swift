import XCTest
@testable import StashKit

/// Stubbed transport for `AccountDeleterTests` — returns a canned `(data, statusCode)` pair (or
/// throws, for the transport-failure cases) without ever touching the network. Records the token
/// it was called with so tests can assert the caller's session token is the one actually sent.
private final class StubAccountDeletionTransport: AccountDeletionTransport, @unchecked Sendable {
    var response: (data: Data, statusCode: Int) = (Data("{}".utf8), 200)
    var errorToThrow: Error?
    private(set) var lastAccessToken: String?

    func post(accessToken: String) async throws -> (data: Data, statusCode: Int) {
        lastAccessToken = accessToken
        if let errorToThrow { throw errorToThrow }
        return response
    }
}

/// Stubbed `GET /auth/v1/user` for the existence check.
private final class StubExistenceProbe: AccountExistenceProbing, @unchecked Sendable {
    var response: (data: Data, statusCode: Int) = (Data("{}".utf8), 200)
    var errorToThrow: Error?
    private(set) var lastAccessToken: String?

    func fetchUser(accessToken: String) async throws -> (data: Data, statusCode: Int) {
        lastAccessToken = accessToken
        if let errorToThrow { throw errorToThrow }
        return response
    }
}

final class AccountDeleterTests: XCTestCase {
    private func deleteError(_ transport: StubAccountDeletionTransport, file: StaticString = #filePath,
                             line: UInt = #line) async -> AccountDeletionError? {
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch {
            return error as? AccountDeletionError
        }
    }

    func testSuccessDecodesDeletedAndStorageObjects() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"deleted":true,"storageObjects":7,"stripe":{"customers":1,"canceled":1}}"#.utf8), 200)
        let result = try await AccountDeleter().delete(using: transport, accessToken: "jwt-123")
        XCTAssertEqual(result, AccountDeletionResult(deleted: true, storageObjects: 7))
        XCTAssertEqual(transport.lastAccessToken, "jwt-123")
    }

    func test401ThrowsUnauthorized() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"error":"Invalid or expired token"}"#.utf8), 401)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .unauthorized)
    }

    func test403ThrowsForbiddenWithServerMessage() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"error":"Agent tokens cannot delete an account"}"#.utf8), 403)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .forbidden("Agent tokens cannot delete an account"))
    }

    func testDocumented500ThrowsServerErrorWithMessage() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"deleted":false,"error":"storage remove: boom"}"#.utf8), 500)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .serverError("storage remove: boom"))
    }

    func testOther4xxThrowsServerError() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"error":"POST only"}"#.utf8), 405)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .serverError("POST only"))
    }

    func testMalformedTwoHundredBodyThrowsMalformedResponse() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data("not json".utf8), 200)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .malformedResponse)
    }

    func testTwoHundredWithDeletedFalseThrowsMalformedResponse() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"deleted":false}"#.utf8), 200)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .malformedResponse)
    }

    // MARK: - Plan 15 (L7): "never sent" vs "no answer"

    func testTimeoutIsOutcomeUnknownNotTransport() async {
        let transport = StubAccountDeletionTransport()
        let timedOut = URLError(.timedOut)
        transport.errorToThrow = timedOut
        let error = await deleteError(transport)
        XCTAssertEqual(error, .outcomeUnknown(timedOut.localizedDescription),
                       "a timeout may come after the server started deleting")
    }

    func testDroppedConnectionIsOutcomeUnknown() async {
        let transport = StubAccountDeletionTransport()
        let lost = URLError(.networkConnectionLost)
        transport.errorToThrow = lost
        let error = await deleteError(transport)
        XCTAssertEqual(error, .outcomeUnknown(lost.localizedDescription))
    }

    func testOfflineIsTransport() async {
        let transport = StubAccountDeletionTransport()
        let offline = URLError(.notConnectedToInternet)
        transport.errorToThrow = offline
        let error = await deleteError(transport)
        XCTAssertEqual(error, .transport(offline.localizedDescription))
    }

    func testEveryNeverSentCodeIsTransport() {
        for code in AccountDeleter.neverSentCodes {
            let error = URLError(code)
            XCTAssertEqual(AccountDeleter.classifyTransportFailure(error), .transport(error.localizedDescription),
                           "\(code.rawValue)")
        }
    }

    func testANonURLErrorIsOutcomeUnknown() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let transport = StubAccountDeletionTransport()
        transport.errorToThrow = Boom()
        let error = await deleteError(transport)
        XCTAssertEqual(error, .outcomeUnknown("boom"))
    }

    func testGatewayTimeoutIsOutcomeUnknown() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data("<html>504 Gateway Time-out</html>".utf8), 504)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .outcomeUnknown("HTTP 504"))
    }

    func testUndocumented500IsOutcomeUnknown() async {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"message":"worker died"}"#.utf8), 500)
        let error = await deleteError(transport)
        XCTAssertEqual(error, .outcomeUnknown("HTTP 500"))
    }

    func testTheLiveTransportWaitsTwoMinutes() {
        XCTAssertEqual(FunctionsAccountDeletionTransport.timeout, 120)
    }

    // MARK: - Existence check (production shapes verified 2026-09-29 with a throwaway account)

    func testExistenceIsGoneForUserNotFound() {
        let body = Data(#"{"code":"user_not_found","message":"User from sub claim in JWT does not exist"}"#.utf8)
        XCTAssertEqual(AccountDeleter.existence(statusCode: 403, body: body), .gone)
    }

    func testExistenceIsGoneForTheLegacyUserNotFoundShape() {
        let body = Data(#"{"code":403,"error_code":"user_not_found","msg":"User from sub claim in JWT does not exist"}"#.utf8)
        XCTAssertEqual(AccountDeleter.existence(statusCode: 403, body: body), .gone)
    }

    func testExistenceIsExistsForAUserObject() {
        let body = Data(#"{"id":"3f2a0000-0000-4000-8000-000000000000","email":"a@b.c"}"#.utf8)
        XCTAssertEqual(AccountDeleter.existence(statusCode: 200, body: body), .exists)
    }

    func testExistenceIsUnknownForATwoHundredThatIsNotAUser() {
        XCTAssertEqual(AccountDeleter.existence(statusCode: 200, body: Data("<html>Sign in to Wi-Fi</html>".utf8)), .unknown)
    }

    func testExistenceIsExistsWhenOnlyTheSessionIsGone() {
        let body = Data(#"{"code":"session_not_found","message":"Session from session_id claim in JWT does not exist"}"#.utf8)
        XCTAssertEqual(AccountDeleter.existence(statusCode: 403, body: body), .exists)
    }

    func testExistenceIsUnknownForAnExpiredToken() {
        let body = Data(#"{"code":"bad_jwt","message":"invalid JWT: token is expired"}"#.utf8)
        XCTAssertEqual(AccountDeleter.existence(statusCode: 401, body: body), .unknown)
    }

    func testExistenceIsUnknownForA5xx() {
        XCTAssertEqual(AccountDeleter.existence(statusCode: 503, body: Data()), .unknown)
    }

    func testExistenceSendsTheDeletionTokenAndIsUnknownWhenTheProbeFails() async {
        let probe = StubExistenceProbe()
        probe.errorToThrow = URLError(.notConnectedToInternet)
        let existence = await AccountDeleter().existence(using: probe, accessToken: "jwt-used-for-delete")
        XCTAssertEqual(existence, .unknown)
        XCTAssertEqual(probe.lastAccessToken, "jwt-used-for-delete")
    }

    func testExistenceRoundTripThroughTheProbe() async {
        let probe = StubExistenceProbe()
        probe.response = (Data(#"{"code":"user_not_found"}"#.utf8), 403)
        let existence = await AccountDeleter().existence(using: probe, accessToken: "jwt")
        XCTAssertEqual(existence, .gone)
    }

    // MARK: - Resolution

    func testAGoneAccountIsDeletedWhateverTheFirstAnswerWas() {
        let errors: [AccountDeletionError] = [
            .unauthorized, .forbidden("x"), .serverError("auth delete: User not found"), .malformedResponse,
            .transport("offline"), .outcomeUnknown("timed out"),
        ]
        for error in errors {
            XCTAssertEqual(AccountDeleter.resolve(error, existence: .gone), .deleted, "\(error)")
        }
    }

    func testATimeoutWhileTheAccountStillExistsSaysItIsNotFinished() {
        XCTAssertEqual(AccountDeleter.resolve(.outcomeUnknown("timed out"), existence: .exists),
                       .failed(message: "Deleting your account is taking longer than expected, and it isn't finished yet. Try again in a moment."))
    }

    func testATimeoutThatCouldNotBeCheckedSaysSo() {
        XCTAssertEqual(AccountDeleter.resolve(.outcomeUnknown("timed out"), existence: .unknown),
                       .failed(message: "Couldn't confirm whether your account was deleted. Check your connection, then try again."))
    }

    func testDefinitiveFailuresKeepTheirCopy() {
        for existence in [AccountExistence.exists, .unknown] {
            XCTAssertEqual(AccountDeleter.resolve(.unauthorized, existence: existence),
                           .failed(message: "Your session expired. Sign out and back in, then try again."))
            XCTAssertEqual(AccountDeleter.resolve(.serverError("storage remove: boom"), existence: existence),
                           .failed(message: "storage remove: boom"))
            XCTAssertEqual(AccountDeleter.resolve(.forbidden("Agent tokens cannot delete an account"), existence: existence),
                           .failed(message: "Agent tokens cannot delete an account"))
            XCTAssertEqual(AccountDeleter.resolve(.malformedResponse, existence: existence),
                           .failed(message: "Nothing was removed. Please try again."))
            XCTAssertEqual(AccountDeleter.resolve(.transport("offline"), existence: existence),
                           .failed(message: "Couldn't reach Stash. Check your connection and try again."))
        }
    }
}
