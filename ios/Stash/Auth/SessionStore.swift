import Foundation
import Observation
import StashKit
import Supabase

enum SessionState: Equatable {
    case loading
    case signedOut
    case signedIn(userId: UUID)
}

/// The signed-in user's `user_profiles` row, as far as the app uses it (Settings' account rows, the
/// detail sheet's feed link). Web parity: `useProfile.ts` reads the same table by `id`.
struct UserProfile: Equatable, Sendable {
    let userId: UUID
    let username: String?
}

/// Where `SessionStore`'s per-session profile cache stands (plan 15, snappiness).
enum ProfileLoad: Equatable {
    case idle
    case loading
    case loaded(UserProfile)
    case failed
}

@MainActor @Observable
final class SessionStore {
    /// Only ever written through `setState(_:)`, which also drops the per-session profile cache
    /// whenever the signed-in user changes.
    private(set) var state: SessionState = .loading
    var errorMessage: String?
    /// Plan 14 T3: set when an account deletion is confirmed (`completeAccountDeletion`);
    /// `SignInView` shows the "Your account was deleted." banner (`auth.deletedBanner`) and clears
    /// it on its own disappearance, so a later, ORDINARY sign-out (which never touches this flag)
    /// can never resurface it.
    var accountDeletedBannerVisible = false

    /// Plan 15 (snappiness): the signed-in user's profile, fetched at most once per signed-in
    /// session instead of on every Settings visit and every public item's detail sheet. Owned
    /// here, in a task no view can cancel — so a quick tab switch mid-request never turns into an
    /// error (M6), and the answer is kept for the next appearance. Dropped with the session
    /// (`setState`). A failed load is retried by the next `loadProfileIfNeeded()`.
    private(set) var profileLoad: ProfileLoad = .idle
    @ObservationIgnored private var profileTask: Task<Void, Never>?

    func start() async {
        #if DEBUG
        var startSignedOut = false
        // UI-test repeatability: the Keychain session survives app uninstall/reinstall
        // on the Simulator, so a UI test that signs in once would silently skip the
        // sign-in screen on every subsequent run. Let the UI test force a clean slate.
        if CommandLine.arguments.contains("--uitest-reset-auth") {
            // Web parity (plan-4 Task 6b, commit 166b7c6: "local-scope sign-out"): sign out
            // locally without broadcast to other sessions — matches web's LogoutButton behavior.
            try? await StashClient.shared.auth.signOut(scope: .local)
            // The launch starts signed out no matter what the Keychain holds a moment later: an
            // expired stored session may already have been refreshing, and that refresh can store
            // a fresh session again after the sign-out (see `discardResurrectedSession()`).
            startSignedOut = true
        }
        // Plan 12 task 4: the "How to easily stash" panel's UserDefaults flag lives outside the
        // Keychain session entirely (see `OnboardingState`'s doc comment), so `--uitest-reset-auth`
        // above never touches it on its own. `--uitest-reset-onboarding` opts a run IN to seeing
        // the panel; every OTHER `--uitest-reset-auth` smoke in this suite predates the panel and
        // doesn't expect a full-screen cover to appear mid-sign-in, so it defaults to
        // already-seen instead of leaving the flag at its untouched (unseen) default.
        if CommandLine.arguments.contains("--uitest-reset-onboarding") {
            OnboardingState.resetHowToStashSeenForTests()
        } else if CommandLine.arguments.contains("--uitest-reset-auth") {
            OnboardingState.markHowToStashSeen()
        }
        // Plan 15 (H1, `SessionUITests`): relaunch as if the last token refresh were over an hour
        // ago. Paired with `--uitest-auth-unreachable` (`StashClient`) it is the offline/flaky
        // cold launch H1 is about. A simulation that didn't take would let that test pass for the
        // wrong reason, so it stops the app instead.
        if CommandLine.arguments.contains("--uitest-expire-session"), !StashClient.expireStoredSessionForUITest() {
            fatalError("--uitest-expire-session: no stored session could be marked expired — sign in first")
        }
        #endif
        // Plan 15 (H1): decide from the session STORED on this device, at once — never from a
        // network round trip. A stored session whose access token expired (the app was evicted
        // and relaunched more than an hour after its last refresh) still counts as signed in: the
        // SDK refreshes it in the background (`emitLocalSessionAsInitialSession`, `StashClient`)
        // and every request refreshes lazily. Offline or on a slow network the tab UI still comes
        // up immediately — captures queue in the Outbox, the View tab shows its cached page (and a
        // request that can't get a user token fails instead of running anonymously —
        // `SignedInAnonFallbackGuard`).
        //
        // Zombie-session protection is kept: "signed out" is exactly "no stored session", and the
        // SDK removes the stored session and emits `.signedOut` itself when a refresh is REFUSED
        // with a session-cleanup code (`refresh_token_not_found` — a deleted account or a revoked
        // session — `session_not_found`, …). Only a refresh that can't reach the server leaves it
        // in place, and that is exactly the offline case.
        #if DEBUG
        let stored = startSignedOut ? nil : StashClient.shared.auth.currentSession
        #else
        // Release has no UI-test reset, so no "start signed out" branch (a constant-false one
        // would be flagged "will never be executed").
        let stored = StashClient.shared.auth.currentSession
        #endif
        setState(stored.map { SessionState.signedIn(userId: $0.user.id) } ?? .signedOut)
        for await change in StashClient.shared.auth.authStateChanges {
            switch change.event {
            case .signedIn:
                // An explicit sign-in or sign-up: the only event that may change who is signed in.
                if let user = change.session?.user { setState(.signedIn(userId: user.id)) }
            case .initialSession, .tokenRefreshed, .userUpdated:
                guard let user = change.session?.user else {
                    // `.initialSession` with nothing stored (e.g. the SDK removed it before this
                    // listener attached).
                    if change.event == .initialSession { setState(.signedOut) }
                    break
                }
                if state == .signedIn(userId: user.id) { break }   // the same session, still here
                // A session appeared that no sign-in produced — this device is signed out, or
                // signed in as someone else. See `discardResurrectedSession()`.
                discardResurrectedSession()
            case .signedOut, .userDeleted:
                setState(.signedOut)
            default: break
            }
        }
    }

    private func setState(_ newState: SessionState) {
        guard newState != state else { return }
        resetProfile()
        state = newState
    }

    /// supabase-swift stores whatever a token refresh returns without checking that the session it
    /// refreshed is still there (`SessionManager.refreshSession` → `update`). So a refresh already
    /// in flight when this device signs out locally — at launch the SDK refreshes an expired
    /// stored session at once, and it refreshes again shortly before each expiry — stores a fresh
    /// session right AFTER the sign-out and announces it (`.tokenRefreshed`, or the next
    /// `.initialSession`): the app would bounce back into the account the user just left, or the
    /// Keychain would silently sign them in again at the next launch. Only an explicit sign-in may
    /// change who is signed in, so such a session is signed out again (local scope, which also
    /// revokes it server-side) and the state stays — or becomes — `.signedOut`.
    private func discardResurrectedSession() {
        setState(.signedOut)
        Task { try? await StashClient.shared.auth.signOut(scope: .local) }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await StashClient.shared.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = "Sign-in failed. Check your email and password."
        }
    }

    /// Web parity (`src/hooks/useAuth.tsx:42-58` `signUp`, called from `Auth.tsx`'s sign-up
    /// branch): `auth.signUp` carries `username`/`display_name` as user metadata — there is no
    /// client-side `user_profiles` insert here, because there isn't one on web either. The
    /// `handle_new_user` Postgres trigger (`supabase/migrations/20250819082612_...sql`) reads
    /// `raw_user_meta_data->>'username'` off the new `auth.users` row and creates the
    /// `user_profiles` row itself; inserting from the client too would race the trigger.
    /// `authStateChanges` (see `start()`) picks up the resulting sign-in the same way `signIn`
    /// does — supabase-swift's `signUp` updates the session and emits `.signedIn` internally.
    func signUp(email: String, password: String, username: String, phone: String?) async {
        errorMessage = nil
        do {
            let metadata: [String: AnyJSON] = [
                "username": .string(username),
                "display_name": .string(username),
            ]
            let response = try await StashClient.shared.auth.signUp(email: email, password: password, data: metadata)

            // Web parity (`Auth.tsx` `handleSignUp` → `usePhoneNumber.ts` `registerPhoneNumber`):
            // an optional phone is a best-effort follow-up — its own failure (upsert or the
            // welcome-message invoke) never fails the sign-up itself, exactly like web's nested
            // try/catch that only logs.
            //
            // Punch-list A8 ("phone storage bug") fix: web's OWN sign-up path passes the raw typed
            // string straight into a bare digit-strip with no leading-"1" normalization, so a
            // sign-up-created row and a Settings-created row for the SAME real number end up with
            // different digit counts (see `PhoneNumber.swift`'s doc comment for the full story).
            // Routing through `PhoneNumber.normalize` here — the same function `PhoneSection` now
            // uses — closes that gap rather than porting the bug: a 10-digit number gets "1"
            // prepended before it's ever written, exactly like `PhoneNumberSetup.tsx`'s
            // `formatPhoneNumber(...).cleanValue` already does on web's Settings side. An
            // unparseable phone (never validated at all in the sign-up form today) is silently
            // skipped, same "never fails sign-up" contract as an upsert/welcome-message failure.
            if let phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty,
               case .success(let cleanPhone) = PhoneNumber.normalize(phone) {
                let phoneBody: [String: AnyJSON] = [
                    "user_id": .string(response.user.id.uuidString),
                    "phone_number": .string(cleanPhone),
                    "verified": .bool(true),
                ]
                // Fire-and-forget, matching web's own nested try/catch (see doc comment above) —
                // `_ =` silences "result of 'try?' is unused" (`.execute()` returns a
                // non-Void `PostgrestResponse`); the response itself is intentionally discarded.
                _ = try? await StashClient.shared.from("user_phone_numbers")
                    .upsert(phoneBody, onConflict: "phone_number")
                    .execute()
                try? await StashClient.shared.functions.invoke(
                    "send-welcome-message",
                    options: FunctionInvokeOptions(body: ["phoneNumber": AnyJSON.string(cleanPhone)])
                )
            }
        } catch {
            // Web parity (`Auth.tsx handleSignUp`'s toast uses `error.message` verbatim):
            // surface the real Supabase message (e.g. "User already registered") when there is
            // one; the generic string is only a fallback for an empty/unlocalized error.
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "Sign-up failed. Check your details and try again." : message
        }
    }

    /// Web parity (`Auth.tsx` `checkUsernameUniqueness`): `true` if a `user_profiles` row
    /// already has this (lowercased) username. A query failure is treated as "not taken" —
    /// same fail-open the web's own `error.code !== 'PGRST116'` branch effectively is (it only
    /// logs), since a network hiccup here must never block typing or the submit button.
    func isUsernameTaken(_ username: String) async -> Bool {
        struct Row: Decodable { let username: String }
        do {
            let rows: [Row] = try await StashClient.shared.from("user_profiles")
                .select("username")
                .eq("username", value: username.lowercased())
                .limit(1)
                .execute().value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    /// Web parity (`Auth.tsx` `checkPhoneUniqueness`): `true` if a `user_phone_numbers` row
    /// already has this cleaned (digits-only) phone number. Same fail-open as
    /// `isUsernameTaken` on a query error.
    func isPhoneTaken(_ cleanPhone: String) async -> Bool {
        struct Row: Decodable { let phoneNumber: String
            enum CodingKeys: String, CodingKey { case phoneNumber = "phone_number" }
        }
        do {
            let rows: [Row] = try await StashClient.shared.from("user_phone_numbers")
                .select("phone_number")
                .eq("phone_number", value: cleanPhone)
                .limit(1)
                .execute().value
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    /// Sign-out keeps this user's own on-device queues — the Outbox, staged share files,
    /// recordings, and the detail sheet's pending edits (`PendingEdits`, plan 15): each lives in a
    /// per-user directory no other account ever reads, and each is delivered when this same user
    /// signs in again (the Outbox drains at sign-in, pending edits flush before the first library
    /// refresh). Dropping them here would silently lose captures and edits the user was told were
    /// saved. What goes: the session and the View tab's caches. Account deletion
    /// (`completeAccountDeletion`) is the one path that removes everything.
    func signOut() async {
        // Web parity (plan-4 Task 6b, commit 166b7c6: "local-scope sign-out"): sign out
        // locally without broadcast to other sessions — matches web's LogoutButton behavior.
        // Fixes zombie-session incident (see memory/supabase-log-forensics.md).
        try? await StashClient.shared.auth.signOut(scope: .local)
        // Plan 15: the View tab's cached first page + hero images go with the session (StashApp's
        // `.signedIn → .signedOut` handler also closes the store and purges again, which covers a
        // session the server revoked, too).
        LibraryCaches.purgeAll()
        setState(.signedOut)
    }

    // MARK: - Profile (plan 15, snappiness)

    /// `userId`'s profile load — `.idle` unless `userId` is the signed-in user.
    func profileLoad(for userId: UUID) -> ProfileLoad {
        guard state == .signedIn(userId: userId) else { return .idle }
        return profileLoad
    }

    /// The signed-in user's profile, once loaded.
    var profile: UserProfile? {
        if case .loaded(let profile) = profileLoad { return profile }
        return nil
    }

    /// Loads the signed-in user's profile unless it's loaded or already loading (a failed load is
    /// retried). Cheap to call from every `onAppear`/`.task`.
    func loadProfileIfNeeded() {
        guard case .signedIn(let userId) = state else { return }
        switch profileLoad {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        profileLoad = .loading
        profileTask = Task { [weak self] in
            let profile = await Self.fetchProfile(userId: userId)
            guard let self, !Task.isCancelled, self.state == .signedIn(userId: userId) else { return }
            self.profileLoad = profile.map(ProfileLoad.loaded) ?? .failed
        }
    }

    private func resetProfile() {
        profileTask?.cancel()
        profileTask = nil
        profileLoad = .idle
    }

    /// `useProfile.ts`'s query: `user_profiles` by `id`, one row. `nil` on any failure.
    private static func fetchProfile(userId: UUID) async -> UserProfile? {
        struct Row: Decodable { let username: String? }
        do {
            let data = try await StashClient.shared.from("user_profiles")
                .select("username")
                .eq("id", value: userId.uuidString)
                .single()
                .execute().data
            return UserProfile(userId: userId, username: try JSONDecoder().decode(Row.self, from: data).username)
        } catch {
            return nil
        }
    }

    // MARK: - Account deletion

    /// Settings → "Delete everything" (plan 14 T3; plan 15 L7). Owned here, not by the confirm
    /// sheet: the sheet can disappear mid-flow (a confirmed deletion signs the app out), this store
    /// can't.
    ///
    /// 1. A token that outlives the request (≤ `FunctionsAccountDeletionTransport.timeout`) plus
    ///    the follow-up check — refreshed first when it has less than 5 minutes left, since an
    ///    expired token would make that check inconclusive.
    /// 2. `delete-account`. Success → purge this device (`completeAccountDeletion`).
    /// 3. Anything else — a timeout above all, but also a 401 (a retry whose earlier run already
    ///    deleted the account), a 500 from a concurrent run, a gateway 5xx — is followed by
    ///    asking Auth whether the account still exists (`AccountDeleter.existence`, a direct
    ///    request that can't sign this device out behind the purge's back). Gone → the same purge
    ///    + "deleted" banner as a clean success; still there, or unknown → copy that says which
    ///    (`AccountDeleter.resolve`), and the user can try again safely.
    func deleteAccount(userId: UUID) async -> AccountDeletionResolution {
        let accessToken: String
        do {
            accessToken = try await freshAccessToken(outliving: 5 * 60)
        } catch {
            return .failed(message: error is URLError
                ? "Couldn't reach Stash. Check your connection and try again."
                : "Your session expired. Sign out and back in, then try again.")
        }
        let deleter = AccountDeleter()
        let resolution: AccountDeletionResolution
        do {
            _ = try await deleter.delete(using: FunctionsAccountDeletionTransport(), accessToken: accessToken)
            resolution = .deleted
        } catch {
            let failure = error as? AccountDeletionError ?? .outcomeUnknown(error.localizedDescription)
            let existence = await deleter.existence(using: AuthUserExistenceProbe(), accessToken: accessToken)
            resolution = AccountDeleter.resolve(failure, existence: existence)
        }
        if resolution == .deleted {
            await completeAccountDeletion(userId: userId)
        }
        return resolution
    }

    /// The current access token, swapped for a freshly refreshed one when it has less than
    /// `lifetime` left. If that refresh can't happen right now the current (still valid — the SDK
    /// never hands out one with under 30 s left) token is used.
    private func freshAccessToken(outliving lifetime: TimeInterval) async throws -> String {
        let session = try await StashClient.shared.auth.session
        guard Date(timeIntervalSince1970: session.expiresAt).timeIntervalSinceNow < lifetime else {
            return session.accessToken
        }
        return (try? await StashClient.shared.auth.refreshSession().accessToken) ?? session.accessToken
    }

    /// Runs once `deleteAccount` has established that the server-side account is gone. Removes
    /// every piece of THIS DEVICE's state that still names `userId` — nothing is left anywhere for
    /// any of it to ever be sent to or read back from — and hands off to the sign-in screen with
    /// the deleted banner armed:
    ///
    /// - **Per-user directories**, whole: the Outbox (entries + claims), recordings (an offline
    ///   voice note's audio), staged share/attachment files, and pending detail-sheet edits
    ///   (`PendingEdits`, plan 15). Every per-user `AppGroup.userScopedURL` store there is.
    /// - **App Group gate cache** (`SubscriptionStore.gateCacheKey`): removed, so a fresh sign-in on
    ///   this device never briefly inherits the deleted account's last answer.
    /// - **Library caches** (plan 15): the View tab's cached first page (`Caches/StashItemCache`)
    ///   and hero images (`Caches/StashImageCache`).
    /// - **Keychain session**, last: the same local-scope `signOut(scope: .local)` `signOut()` uses.
    ///
    /// Plan 15 final wave — the purge comes FIRST, in one synchronous pass: `signOut` drops the
    /// stored session and emits `.signedOut` at once, but then sends a logout request the SDK
    /// retries with backoff — offline, that can take minutes. The device must not keep the deleted
    /// account's files through that wait (a kill during it would leave them for good), and the
    /// sign-in screen is already up by then. Nothing can recreate them meanwhile: the account is
    /// gone server-side, so a send still in flight is refused, and a failed send only ever updates
    /// an entry that still exists on disk. For the same reason the final `.signedOut` is skipped
    /// when someone else has signed in on the sign-in screen while that request was still retrying
    /// — it would sign THEM out.
    ///
    /// Not here: request bodies of this account's background share transfers still in flight
    /// (`StashTransfers/`, not per-user) — the transfer daemon may still be reading them; their
    /// uploads now fail authentication, and `sweepStaleBodyFiles` removes them at a later launch.
    /// Deliberately does NOT touch `OnboardingState` (the "How to easily stash" seen-flag) — the
    /// plan's own contract is "onboarding flags untouched".
    private func completeAccountDeletion(userId: UUID) async {
        // Armed before the sign-out: that call emits `.signedOut` (and the sign-in screen can
        // appear) before its own network round trip returns.
        accountDeletedBannerVisible = true

        let fileManager = FileManager.default
        let userDirectories = [
            Outbox.defaultDirectory(userId: userId),
            RecordingStore(userId: userId).directory,
            StagedFileStore(userId: userId).directory,
            PendingEdits.defaultDirectory(for: userId),
        ]
        for directory in userDirectories {
            try? fileManager.removeItem(at: directory)
        }
        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: SubscriptionStore.gateCacheKey)
        LibraryCaches.purgeAll()

        try? await StashClient.shared.auth.signOut(scope: .local)

        if case .signedIn(let current) = state, current != userId { return }
        setState(.signedOut)
    }
}
