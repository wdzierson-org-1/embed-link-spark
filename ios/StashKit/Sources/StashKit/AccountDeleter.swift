import Foundation

/// Decoded success body of `delete-account` (contract: `docs/PLATFORM_API.md` "Account
/// deletion", `supabase/functions/delete-account/index.ts:135` —
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

/// Typed failures for `AccountDeleter.delete` — one case per shape the edge function's contract
/// documents (`index.ts:112,115,116,139`), plus the two failure modes that never reach the
/// server at all.
public enum AccountDeletionError: Error, Equatable, Sendable {
    /// 401 — no/invalid/expired access token (`{"error": "..."}`, message not surfaced to the
    /// user; "sign in again" covers every 401 shape).
    case unauthorized
    /// 403 — an agent (MCP) token tried to delete the account
    /// (`{"error": "Agent tokens cannot delete an account"}`); the server's own message is
    /// carried through since it's already end-user-safe copy.
    case forbidden(String)
    /// 500 `{deleted: false, error}`, or any other non-2xx/network-adjacent shape this client
    /// doesn't otherwise recognize — the account is intact either way.
    case serverError(String)
    /// A 2xx response whose body doesn't decode as the documented success shape at all
    /// (`deleted` missing or `false` with no `error` string, or the JSON itself is malformed).
    case malformedResponse
    /// The HTTP round trip itself failed (offline, DNS, TLS, timeout) — never reached the server,
    /// so the account is guaranteed intact.
    case transport(String)
}

/// Injection point for `AccountDeleter.delete(using:)` — the "stubbed transport" the plan calls
/// for, mirroring `CaptureAPI`'s `JSONPosting` shape but returning the raw status code alongside
/// the body (unlike `JSONPosting`, which only ever throws away a failure response's body):
/// `delete-account`'s 401/403/500 bodies all carry a JSON `{"error": "..."}"` this type needs to
/// read, not just a bare status code.
public protocol AccountDeletionTransport: Sendable {
    func post(accessToken: String) async throws -> (data: Data, statusCode: Int)
}

/// Real network transport: POSTs `<supabase>/functions/v1/delete-account` with the platform's two
/// auth headers plus the caller's own session token — same request shape `FunctionsPoster`
/// (`CaptureAPI.swift`) uses for every other edge function, just returning the status code
/// instead of throwing it away.
public struct FunctionsAccountDeletionTransport: AccountDeletionTransport {
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
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountDeletionError.malformedResponse }
        return (data, http.statusCode)
    }
}

/// Deletes the signed-in user's account server-side. Order of operations documented on the edge
/// function itself (`index.ts:6-19`): Stripe cancel → storage purge → `auth.admin.deleteUser`,
/// with the DB cascading everything else. This type only knows the CLIENT half of that contract —
/// decode the response into a typed result/error — never anything about local state; purging this
/// device's own Outbox/staged-files/session/App-Group cache after a confirmed success is
/// `SessionStore.completeAccountDeletion`'s job (`ios/Stash/Auth/SessionStore.swift`), not this
/// type's.
public struct AccountDeleter: Sendable {
    public init() {}

    /// - Parameters:
    ///   - client: injected transport (production: `FunctionsAccountDeletionTransport()`; tests:
    ///     a stub returning canned `(data, statusCode)` pairs — see `AccountDeleterTests`).
    ///   - accessToken: the CALLING USER's own session token (`StashClient.shared.auth.session
    ///     .accessToken`) — never an agent/MCP token, which the server itself refuses with 403.
    public func delete(using client: AccountDeletionTransport, accessToken: String) async throws -> AccountDeletionResult {
        let data: Data
        let statusCode: Int
        do {
            (data, statusCode) = try await client.post(accessToken: accessToken)
        } catch let error as AccountDeletionError {
            throw error
        } catch {
            throw AccountDeletionError.transport(error.localizedDescription)
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
        default:
            // Covers the documented 500 shape and anything else non-2xx the server might someday
            // return — the account is intact either way, so there's no separate "unknown status"
            // case for the caller to handle differently.
            throw AccountDeletionError.serverError(serverMessage ?? "Nothing was removed. Please try again.")
        }
    }
}
