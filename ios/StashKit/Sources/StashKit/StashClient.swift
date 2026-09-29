import Foundation
import Supabase

/// Plan 5 Task 2: the ONE-TIME re-sign-in this task costs every existing dev install is expected
/// and documented (task-2-report.md) — on first launch after this change, `SharedKeychainStorage`
/// looks in a different keychain slot (its own `service` string, `"it.gostash.stash.session"`,
/// vs. supabase-swift's previous default `KeychainLocalStorage`'s `"supabase.gotrue.swift"`) than
/// wherever the old session was persisted, so the old session is invisible and `SessionStore`
/// lands signed-out until the next sign-in. Nothing is migrated — dev-stage, zero real users
/// (decision of record). `--uitest-reset-auth` (`SessionStore.start()`) already forces a
/// sign-out-first launch, so every UI-test suite is immune regardless.
public enum StashClient {
    public static let shared = SupabaseClient(
        supabaseURL: StashConfig.supabaseURL,
        supabaseKey: StashConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            auth: .init(
                storage: SharedKeychainStorage(accessGroup: sharedSessionAccessGroup),
                // Plan 15 (H1): `.initialSession` carries the STORED session at once — expired or
                // not — and the SDK refreshes an expired one in the background. The legacy default
                // refreshed first and emitted `nil` whenever that refresh failed (offline, a slow
                // network), which read as "signed out". `SessionStore` decides from the stored
                // session; a refresh the server REFUSES with a session-cleanup code
                // (`refresh_token_not_found`, `session_not_found`, …) still removes it and emits
                // `.signedOut`, so a revoked or deleted session never lingers.
                emitLocalSessionAsInitialSession: true
            ),
            global: .init(session: urlSession)
        )
    )

    /// `nil` when this process isn't entitled for the shared keychain access group — `swift
    /// test`'s macOS host, or any other un-entitled context — in which case
    /// `SharedKeychainStorage` falls back to this process's own default (non-shared) keychain.
    /// See `SharedKeychainStorage.resolvedAccessGroup` for exactly how/why this is determined.
    static let sharedSessionAccessGroup =
        SharedKeychainStorage.resolvedAccessGroup(suffix: "it.gostash.stash.shared",
                                                  service: "it.gostash.stash.session")

    /// Every request the Supabase client makes (Auth, PostgREST, Storage, Functions) goes through
    /// this session: `URLSessionConfiguration.default` — the same shared cache, cookies and
    /// timeouts as `URLSession.shared` — plus `SignedInAnonFallbackGuard` (and, in DEBUG UI-test
    /// runs only, `UITestAuthOutage`). Requests that neither protocol claims load normally.
    static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        var interceptors: [AnyClass] = [SignedInAnonFallbackGuard.self]
        #if DEBUG
        if UITestAuthOutage.isEnabled { interceptors.insert(UITestAuthOutage.self, at: 0) }
        #endif
        configuration.protocolClasses = interceptors + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }()

    #if DEBUG
    /// UI tests only (`--uitest-expire-session`, `SessionStore.start()`): marks the STORED session's
    /// access token as expired — what a relaunch more than an hour after the last refresh finds —
    /// without any network call, by rewriting the stored copy the way supabase-swift writes it
    /// (plain `JSONEncoder`, under its default storage key). Returns whether the stored session now
    /// reads as expired, so a UI test can never pass on a simulation that didn't take.
    @discardableResult
    public static func expireStoredSessionForUITest() -> Bool {
        guard var session = shared.auth.currentSession,
              let projectRef = StashConfig.supabaseURL.host()?.split(separator: ".").first
        else { return false }
        session.expiresAt = Date().addingTimeInterval(-15 * 60).timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(session) else { return false }
        // supabase-swift's default key when `AuthOptions.storageKey` is nil (as above):
        // `"sb-<project ref>-auth-token"` (`SupabaseClient.init`).
        let storage = SharedKeychainStorage(accessGroup: sharedSessionAccessGroup)
        guard (try? storage.store(key: "sb-\(projectRef)-auth-token", value: data)) != nil else { return false }
        return shared.auth.currentSession?.isExpired == true
    }
    #endif
}

/// Plan 15 (H1). supabase-swift 2.54.1 attaches the user's token to PostgREST, Storage and
/// Functions requests with `try? await auth.session.accessToken` (`SupabaseClient.adapt`): when the
/// token can't be refreshed right now — the refresh timed out, the network dropped, Auth answered
/// 5xx — the request still goes out, with the client's default `Authorization: Bearer <anon key>`.
/// For a signed-in user that is never what the caller meant: under RLS an anonymous read of the
/// user's own rows returns ZERO rows, which callers take for "the server has nothing" — an emptied
/// View tab whose disk cache then gets overwritten, an item that looks deleted. Now that a launch
/// with an expired token stays signed in (`SessionStore.start()`), that window is simply what an
/// offline or flaky launch looks like, so such a request fails HERE, before it is sent, with
/// `URLError(.userAuthenticationRequired)` — an ordinary transient failure every caller already
/// handles (the library keeps its cached page, a queued edit waits, a capture stays in the Outbox).
///
/// Only while a session is stored: signed out, anonymous requests are intended (sign-up's
/// username/phone availability probes). Auth (`/auth/v1/…`, which carries the anon key by design)
/// and Realtime are never touched, and a request carrying any other bearer loads normally.
final class SignedInAnonFallbackGuard: URLProtocol {
    /// Paths whose rows RLS scopes to the caller — where an anonymous request silently reads as
    /// "nothing there" instead of failing.
    static let userScopedPathPrefixes = ["/rest/v1/", "/storage/v1/", "/functions/v1/"]

    /// Whether `request` is a user-scoped Supabase request that fell back to the anon key while a
    /// session is stored. `hasStoredSession` is only asked once everything else matches (it reads
    /// the Keychain).
    static func blocks(_ request: URLRequest,
                       projectHost: String? = StashConfig.supabaseURL.host(),
                       anonKey: String = StashConfig.supabaseAnonKey,
                       hasStoredSession: () -> Bool) -> Bool {
        guard let url = request.url, let host = url.host(), host == projectHost,
              userScopedPathPrefixes.contains(where: { url.path().hasPrefix($0) }),
              request.value(forHTTPHeaderField: "Authorization") == "Bearer \(anonKey)"
        else { return false }
        return hasStoredSession()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        blocks(request, hasStoredSession: { StashClient.shared.auth.currentSession != nil })
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: "Your session couldn't be refreshed. Try again in a moment.",
        ]
        if let url = request.url { userInfo[NSURLErrorFailingURLErrorKey] = url }
        client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired, userInfo: userInfo))
    }

    override func stopLoading() {}
}

#if DEBUG
/// UI tests only (`--uitest-auth-unreachable`): every Supabase Auth request fails as if the device
/// were offline while the rest of the network keeps working — the "can't refresh the token" half of
/// H1's cold launch (`SessionUITests`). Never active in the share extension (it gets no launch
/// arguments) or in Release builds.
final class UITestAuthOutage: URLProtocol {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--uitest-auth-unreachable")

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let host = url.host() else { return false }
        return host == StashConfig.supabaseURL.host() && url.path().hasPrefix("/auth/v1/")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
