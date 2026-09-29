import Supabase
import XCTest
@testable import StashKit

/// Plan 15 (H1): `SignedInAnonFallbackGuard` — a user-scoped request that fell back to the anon
/// key while a session is stored must fail locally instead of reading as "zero rows".
final class StashClientTests: XCTestCase {
    private let host = "proj.supabase.co"
    private let anon = "anon-key"

    private func request(_ path: String, bearer: String?, host: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(host ?? self.host)\(path)")!)
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.setValue(anon, forHTTPHeaderField: "apikey")
        return request
    }

    private func blocks(_ request: URLRequest, signedIn: Bool = true) -> Bool {
        SignedInAnonFallbackGuard.blocks(request, projectHost: host, anonKey: anon, hasStoredSession: { signedIn })
    }

    func testAnAnonymousUserScopedRequestIsBlockedWhileSignedIn() {
        XCTAssertTrue(blocks(request("/rest/v1/items?select=id", bearer: anon)))
        XCTAssertTrue(blocks(request("/storage/v1/object/stash-media/u/x.jpg", bearer: anon)))
        XCTAssertTrue(blocks(request("/functions/v1/check-subscription", bearer: anon)))
    }

    func testAnonymousRequestsAreLeftAloneWhenSignedOut() {
        // Sign-up's username/phone availability probes are anonymous on purpose.
        XCTAssertFalse(blocks(request("/rest/v1/user_profiles?select=username", bearer: anon), signedIn: false))
    }

    func testRequestsCarryingAUserTokenLoadNormally() {
        XCTAssertFalse(blocks(request("/rest/v1/items", bearer: "user-jwt")))
        XCTAssertFalse(blocks(request("/functions/v1/check-subscription", bearer: "expired-user-jwt")))
    }

    func testAuthRealtimeAndOtherHostsAreNeverTouched() {
        XCTAssertFalse(blocks(request("/auth/v1/token?grant_type=refresh_token", bearer: anon)))
        XCTAssertFalse(blocks(request("/realtime/v1/api/broadcast", bearer: anon)))
        XCTAssertFalse(blocks(request("/rest/v1/items", bearer: anon, host: "example.com")))
        XCTAssertFalse(blocks(request("/rest/v1/items", bearer: nil)))
    }

    func testTheKeychainIsOnlyReadForACandidateRequest() {
        var reads = 0
        let userRequest = request("/rest/v1/items", bearer: "user-jwt")
        _ = SignedInAnonFallbackGuard.blocks(userRequest, projectHost: host, anonKey: anon,
                                             hasStoredSession: { reads += 1; return true })
        XCTAssertEqual(reads, 0)
        _ = SignedInAnonFallbackGuard.blocks(request("/rest/v1/items", bearer: anon), projectHost: host,
                                             anonKey: anon, hasStoredSession: { reads += 1; return true })
        XCTAssertEqual(reads, 1)
    }

    func testTheSupabaseSessionRunsEveryRequestPastTheGuard() {
        let protocols = StashClient.urlSession.configuration.protocolClasses ?? []
        XCTAssertTrue(protocols.contains { $0 == SignedInAnonFallbackGuard.self })
    }

    func testTheGuardMatchesTheRealProjectAndKey() {
        var real = URLRequest(url: StashConfig.supabaseURL.appending(path: "/rest/v1/items"))
        real.setValue("Bearer \(StashConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        XCTAssertTrue(SignedInAnonFallbackGuard.blocks(real, hasStoredSession: { true }))
        XCTAssertFalse(SignedInAnonFallbackGuard.blocks(real, hasStoredSession: { false }))
    }

    // MARK: - Plan 15 final wave: drains send with the Outbox owner's token only

    private func session(for userId: UUID, token: String) -> Session {
        Session(accessToken: token, tokenType: "bearer", expiresIn: 3600,
                expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970, refreshToken: "refresh",
                user: User(id: userId, appMetadata: [:], userMetadata: [:], aud: "authenticated",
                           createdAt: Date(), updatedAt: Date()))
    }

    func testTheOwnersSessionHandsOutItsToken() throws {
        let owner = UUID()
        XCTAssertEqual(try StashClient.ownerToken(of: session(for: owner, token: "owner-jwt"), for: owner), "owner-jwt")
    }

    /// A drain that started for one account and reaches the token after a sign-out/sign-in must
    /// skip — never send that account's queued captures with the account signed in now.
    func testAnotherAccountsSessionIsRefused() {
        let owner = UUID()
        XCTAssertThrowsError(try StashClient.ownerToken(of: session(for: UUID(), token: "other-jwt"), for: owner)) {
            XCTAssertEqual($0 as? SessionOwnerMismatch, SessionOwnerMismatch())
        }
    }
}
