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
            auth: .init(storage: SharedKeychainStorage(accessGroup: sharedSessionAccessGroup))
        )
    )

    /// `nil` when this process isn't entitled for the shared keychain access group — `swift
    /// test`'s macOS host, or any other un-entitled context — in which case
    /// `SharedKeychainStorage` falls back to this process's own default (non-shared) keychain.
    /// See `SharedKeychainStorage.resolvedAccessGroup` for exactly how/why this is determined.
    static let sharedSessionAccessGroup =
        SharedKeychainStorage.resolvedAccessGroup(suffix: "it.gostash.stash.shared",
                                                  service: "it.gostash.stash.session")
}
