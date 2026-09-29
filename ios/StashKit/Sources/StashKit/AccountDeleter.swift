import Foundation

/// Decoded success body of `delete-account` (contract: `docs/PLATFORM_API.md` "Account
/// deletion", `supabase/functions/delete-account/index.ts` —
/// `{ deleted: true, storageObjects, stripe }`). Only `deleted`/`storageObjects` are modeled;
/// `stripe` (`{customers, canceled}`) isn't needed by any caller yet — Codable synthesis simply
/// ignores it.
public struct AccountDeletionResult: Equatable, Sendable {
    public let deleted: Bool
    public let storageObjects: Int?

    public init(deleted: Bool, storageObjects: Int?) {
        self.deleted = deleted
        self.storageObjects = storageObjects
    }
}

/// Typed failures for `AccountDeleter.delete`. Two different kinds of "no answer" are kept apart
/// (plan 15, L7): a request that never left the device (`.transport`) versus one that may have
/// reached the server and simply didn't answer in time (`.outcomeUnknown`) — `delete-account`
/// keeps running after the client stops waiting, so a timeout says nothing about the account.
public enum AccountDeletionError: Error, Equatable, Sendable {
    /// 401 — no/invalid/expired access token (`{"error": "..."}`). Also what an ALREADY-deleted
    /// account's still-unexpired token gets (the function can't load the user any more) — so the
    /// caller checks `AccountDeleter.existence` before saying "sign in again".
    case unauthorized
    /// 403 — an agent (MCP) token tried to delete the account
    /// (`{"error": "Agent tokens cannot delete an account"}`); the server's own message is
    /// carried through since it's already end-user-safe copy.
    case forbidden(String)
    /// The function's own documented failure — 500 `{deleted: false, error}` — or any other 4xx.
    /// The function returns that shape only for an error caught BEFORE its final
    /// `auth.admin.deleteUser` succeeded, so the account is intact.
    case serverError(String)
    /// A 2xx response whose body isn't the documented success shape (`deleted` missing or `false`,
    /// or not JSON at all — e.g. a captive portal's page). Not the function's answer, so nothing
    /// was deleted.
    case malformedResponse
    /// The request never left the device — offline, DNS, no route to the host, TLS — so the server
    /// never saw it and the account is intact.
    case transport(String)
    /// No usable answer, but the request may well have reached the server: the client timed out,
    /// the connection dropped mid-request, or the gateway answered for a function it had stopped
    /// waiting on (502/504, or any other undocumented 5xx). The deletion may have finished, may
    /// still be running, or may have failed — ask `AccountDeleter.existence` before telling the
    /// user anything.
    case outcomeUnknown(String)
}

/// Injection point for `AccountDeleter.delete(using:)` — the "stubbed transport" the plan calls
/// for, mirroring `CaptureAPI`'s transport shape but returning the raw status code alongside
/// the body: `delete-account`'s 401/403/500 bodies all carry a JSON `{"error": "..."}` this type
/// needs to read, not just a bare status code.
public protocol AccountDeletionTransport: Sendable {
    func post(accessToken: String) async throws -> (data: Data, statusCode: Int)
}

/// Real network transport: POSTs `<supabase>/functions/v1/delete-account` with the platform's two
/// auth headers plus the caller's own session token — the same request shape every other edge
/// function call uses, just returning the status code instead of throwing it away.
public struct FunctionsAccountDeletionTransport: AccountDeletionTransport {
    /// Plan 15 (L7): a heavy account (Stripe + thousands of storage objects + the cascade) can take
    /// a while; 30 s gave up on deletions that then completed on the server. 120 s covers the
    /// realistic range, and anything longer is resolved by `AccountDeleter.existence`, not by
    /// guessing.
    public static let timeout: TimeInterval = 120

    public init() {}

    public func post(accessToken: String) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        // The edge function reads only the Authorization header (no body expected) — an empty
        // JSON object keeps `Content-Type: application/json` honest without asserting anything
        // about a request shape the server never looks at.
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: String]())
        request.timeoutInterval = Self.timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountDeletionError.malformedResponse }
        return (data, http.statusCode)
    }
}

/// Whether the server still knows an account (plan 15, L7) — asked after a deletion attempt that
/// didn't clearly succeed.
public enum AccountExistence: Equatable, Sendable {
    /// Auth still has the user (possibly with this session revoked).
    case exists
    /// Auth answered `user_not_found`: the account has been deleted.
    case gone
    /// No clear answer (offline, an expired or invalid token, a 5xx).
    case unknown
}

/// Injection point for `AccountDeleter.existence(using:accessToken:)`.
public protocol AccountExistenceProbing: Sendable {
    func fetchUser(accessToken: String) async throws -> (data: Data, statusCode: Int)
}

/// Real probe: `GET <supabase>/auth/v1/user` with the token the deletion was attempted with —
/// sent directly, NOT through `StashClient.shared.auth`: that client's error path signs this
/// device out by itself on a session-cleanup answer, racing `SessionStore`'s purge + "deleted"
/// banner. Verified against production (plan 15, throwaway account): once the account is deleted,
/// its still-unexpired token gets `403 {"code":"user_not_found"}` here.
public struct AuthUserExistenceProbe: AccountExistenceProbing {
    public init() {}

    public func fetchUser(accessToken: String) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/auth/v1/user"))
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2024-01-01", forHTTPHeaderField: "X-Supabase-Api-Version")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }
}

/// How a deletion attempt ended, as far as the user is concerned.
public enum AccountDeletionResolution: Equatable, Sendable {
    /// The account is gone: purge this device and show the "Your account was deleted." banner.
    case deleted
    /// The account is still there, or that couldn't be confirmed — show `message` and let the
    /// user try again (every step before the function's final auth delete is safe to repeat).
    case failed(message: String)
}

/// Deletes the signed-in user's account server-side. Order of operations documented on the edge
/// function itself: Stripe cancel → storage purge → `auth.admin.deleteUser`, with the DB
/// cascading everything else. This type only knows the CLIENT half of that contract — the request,
/// the typed result/error, the follow-up existence check and what to tell the user — never
/// anything about local state: purging this device's Outbox, staged files, pending edits, caches
/// and session after a confirmed deletion is `SessionStore.completeAccountDeletion`'s job
/// (`ios/Stash/Auth/SessionStore.swift`), orchestrated by `SessionStore.deleteAccount`.
public struct AccountDeleter: Sendable {
    public init() {}

    /// - Parameters:
    ///   - client: injected transport (production: `FunctionsAccountDeletionTransport()`; tests:
    ///     a stub returning canned `(data, statusCode)` pairs — see `AccountDeleterTests`).
    ///   - accessToken: the CALLING USER's own session token — never an agent/MCP token, which
    ///     the server itself refuses with 403.
    public func delete(using client: AccountDeletionTransport, accessToken: String) async throws -> AccountDeletionResult {
        let data: Data
        let statusCode: Int
        do {
            (data, statusCode) = try await client.post(accessToken: accessToken)
        } catch let error as AccountDeletionError {
            throw error
        } catch {
            throw Self.classifyTransportFailure(error)
        }

        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let serverMessage = object?["error"] as? String

        switch statusCode {
        case 200..<300:
            guard object?["deleted"] as? Bool == true else {
                throw AccountDeletionError.malformedResponse
            }
            return AccountDeletionResult(deleted: true, storageObjects: object?["storageObjects"] as? Int)
        case 401:
            throw AccountDeletionError.unauthorized
        case 403:
            throw AccountDeletionError.forbidden(serverMessage ?? "Agent tokens cannot delete an account.")
        case 400..<500:
            throw AccountDeletionError.serverError(serverMessage ?? "Nothing was removed. Please try again.")
        default:
            // Only the function's own caught-error answer (`{deleted: false, error}`) proves the
            // account is intact; a gateway 502/504, a 546, an HTML error page — any other 5xx —
            // may have come while the function was still (or already done) deleting.
            if statusCode == 500, object?["deleted"] as? Bool == false, let serverMessage {
                throw AccountDeletionError.serverError(serverMessage)
            }
            throw AccountDeletionError.outcomeUnknown("HTTP \(statusCode)")
        }
    }

    /// URL errors that mean the request never left the device, so the server can't have acted on
    /// it. Everything else — `.timedOut`, `.networkConnectionLost`, `.cancelled`, a non-URL error —
    /// may have happened after the server started.
    static let neverSentCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
        .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
        .clientCertificateRejected, .clientCertificateRequired,
        .appTransportSecurityRequiresSecureConnection, .badURL, .unsupportedURL,
    ]

    static func classifyTransportFailure(_ error: Error) -> AccountDeletionError {
        if let urlError = error as? URLError, neverSentCodes.contains(urlError.code) {
            return .transport(urlError.localizedDescription)
        }
        return .outcomeUnknown(error.localizedDescription)
    }

    /// Plan 15 (L7): does the account still exist? Asked with the SAME token the deletion used (a
    /// deleted account's token stays cryptographically valid until it expires, and Auth then
    /// answers `user_not_found` for it).
    public func existence(using probe: AccountExistenceProbing, accessToken: String) async -> AccountExistence {
        guard let (data, statusCode) = try? await probe.fetchUser(accessToken: accessToken) else { return .unknown }
        return Self.existence(statusCode: statusCode, body: data)
    }

    /// `GET /auth/v1/user`'s answer → `AccountExistence`. Accepts both error shapes Auth emits:
    /// `{"code": "user_not_found", …}` (API version 2024-01-01, which the probe requests) and the
    /// legacy `{"code": 403, "error_code": "user_not_found", …}`.
    static func existence(statusCode: Int, body: Data) -> AccountExistence {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        if (200..<300).contains(statusCode) {
            // Only a real user object counts — not, say, a captive portal's 200 page.
            return object?["id"] is String ? .exists : .unknown
        }
        switch (object?["code"] as? String) ?? (object?["error_code"] as? String) {
        case "user_not_found":
            return .gone
        case "session_not_found":
            return .exists   // the user is there; only this session was revoked
        default:
            return .unknown
        }
    }

    /// Plan 15 (L7): the outcome of a deletion attempt that threw `error`, given what `existence`
    /// found afterwards. An account that turned out to be gone was deleted, whatever the first
    /// answer said (a timeout, a retry's 401 after the first run finished, a concurrent run's
    /// 500); otherwise the user gets copy that matches what is actually known.
    public static func resolve(_ error: AccountDeletionError, existence: AccountExistence) -> AccountDeletionResolution {
        if existence == .gone { return .deleted }
        switch error {
        case .unauthorized:
            return .failed(message: "Your session expired. Sign out and back in, then try again.")
        case .forbidden(let message), .serverError(let message):
            return .failed(message: message)
        case .malformedResponse:
            return .failed(message: "Nothing was removed. Please try again.")
        case .transport:
            return .failed(message: "Couldn't reach Stash. Check your connection and try again.")
        case .outcomeUnknown:
            return .failed(message: existence == .exists
                ? "Deleting your account is taking longer than expected, and it isn't finished yet. Try again in a moment."
                : "Couldn't confirm whether your account was deleted. Check your connection, then try again.")
        }
    }
}
