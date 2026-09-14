import XCTest
@testable import StashKit

/// Stubbed transport for `AccountDeleterTests` — returns a canned `(data, statusCode)` pair (or
/// throws, for the transport-failure case) without ever touching the network. Records the token
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

final class AccountDeleterTests: XCTestCase {
    func testSuccessDecodesDeletedAndStorageObjects() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"deleted":true,"storageObjects":7,"stripe":{"customers":1,"canceled":1}}"#.utf8), 200)
        let result = try await AccountDeleter().delete(using: transport, accessToken: "jwt-123")
        XCTAssertEqual(result, AccountDeletionResult(deleted: true, storageObjects: 7))
        XCTAssertEqual(transport.lastAccessToken, "jwt-123")
    }

    func test401ThrowsUnauthorized() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"error":"Invalid or expired token"}"#.utf8), 401)
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .unauthorized)
        }
    }

    func test403ThrowsForbiddenWithServerMessage() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"error":"Agent tokens cannot delete an account"}"#.utf8), 403)
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected forbidden")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .forbidden("Agent tokens cannot delete an account"))
        }
    }

    func test500ThrowsServerErrorWithMessageAndAccountIntact() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"deleted":false,"error":"storage remove: boom"}"#.utf8), 500)
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected serverError")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .serverError("storage remove: boom"))
        }
    }

    func testMalformedTwoHundredBodyThrowsMalformedResponse() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data("not json".utf8), 200)
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected malformedResponse")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .malformedResponse)
        }
    }

    func testTwoHundredWithDeletedFalseThrowsMalformedResponse() async throws {
        let transport = StubAccountDeletionTransport()
        transport.response = (Data(#"{"deleted":false}"#.utf8), 200)
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected malformedResponse")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .malformedResponse)
        }
    }

    func testTransportFailureSurfacesAsTransportError() async throws {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "the network is down" } }
        let transport = StubAccountDeletionTransport()
        transport.errorToThrow = Boom()
        do {
            _ = try await AccountDeleter().delete(using: transport, accessToken: "jwt")
            XCTFail("expected transport error")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .transport("the network is down"))
        }
    }
}
