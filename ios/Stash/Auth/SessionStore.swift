import Foundation
import Observation
import StashKit
import Supabase

enum SessionState: Equatable {
    case loading
    case signedOut
    case signedIn(userId: UUID)
}

@MainActor @Observable
final class SessionStore {
    private(set) var state: SessionState = .loading
    var errorMessage: String?
    /// Plan 14 T3: set the instant `completeAccountDeletion` finishes; `SignInView` reads it once
    /// to show the "Your account was deleted." banner (`auth.deletedBanner`) and clears it on its
    /// own disappearance so a later, ORDINARY sign-out (which never touches this flag) can never
    /// resurface it.
    var accountDeletedBannerVisible = false

    func start() async {
        #if DEBUG
        // UI-test repeatability: the Keychain session survives app uninstall/reinstall
        // on the Simulator, so a UI test that signs in once would silently skip the
        // sign-in screen on every subsequent run. Let the UI test force a clean slate.
        if CommandLine.arguments.contains("--uitest-reset-auth") {
            // Web parity (plan-4 Task 6b, commit 166b7c6: "local-scope sign-out"): sign out
            // locally without broadcast to other sessions — matches web's LogoutButton behavior.
            try? await StashClient.shared.auth.signOut(scope: .local)
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
        #endif
        // Zombie-session lesson: any failure here (incl. "Auth session missing")
        // means signed-out — show the sign-in screen, never an error loop.
        do {
            let session = try await StashClient.shared.auth.session
            state = .signedIn(userId: session.user.id)
        } catch {
            state = .signedOut
        }
        for await change in StashClient.shared.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed, .initialSession:
                if let user = change.session?.user { state = .signedIn(userId: user.id) }
            case .signedOut, .userDeleted:
                state = .signedOut
            default: break
            }
        }
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

    func signOut() async {
        // Web parity (plan-4 Task 6b, commit 166b7c6: "local-scope sign-out"): sign out
        // locally without broadcast to other sessions — matches web's LogoutButton behavior.
        // Fixes zombie-session incident (see memory/supabase-log-forensics.md).
        try? await StashClient.shared.auth.signOut(scope: .local)
        state = .signedOut
    }

    /// Plan 14 T3: called by `DeleteAccountSection` once `delete-account` has confirmed the
    /// server-side account is gone. Purges every piece of THIS DEVICE's local state that still
    /// names `userId` — there is nothing left anywhere for any of it to ever be sent to or read
    /// back from — then hands off to the sign-in screen with the deleted banner armed:
    ///
    /// - **Outbox**: `clearAll()` (not `drain()` — the account is gone, nothing should ever be
    ///   sent). Any entry queued offline before the deletion is discarded outright.
    /// - **Staged files**: every not-yet-uploaded share/attachment on disk for this user is
    ///   discarded via the store's existing `pendingStaged()`/`discard(_:)` pair.
    /// - **App Group cache**: `subscription.canAddContent` (`SubscriptionStore.gateCacheKey`) is
    ///   removed outright rather than left stale — a fresh sign-up/sign-in on this same device
    ///   must never briefly inherit a deleted account's last-cached gate value.
    /// - **Keychain session**: the SAME local-scope `auth.signOut(scope: .local)` `signOut()`
    ///   above already uses — the server-side account is already gone, so this only ever clears
    ///   this device's own session, never broadcasts anything.
    ///
    /// Deliberately does NOT touch `OnboardingState` (the "How to easily stash" seen-flag) — the
    /// plan's own contract is "onboarding flags untouched," so a fresh sign-up on this same
    /// device still sees them exactly as this device already left them.
    func completeAccountDeletion(userId: UUID) async {
        let outbox = Outbox(directory: Outbox.defaultDirectory(userId: userId))
        await outbox.clearAll()

        let staging = StagedFileStore(userId: userId)
        for url in staging.pendingStaged() { staging.discard(url) }

        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: SubscriptionStore.gateCacheKey)

        try? await StashClient.shared.auth.signOut(scope: .local)

        accountDeletedBannerVisible = true
        state = .signedOut
    }
}
