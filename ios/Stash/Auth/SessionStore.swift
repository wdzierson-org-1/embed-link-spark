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

    func start() async {
        #if DEBUG
        // UI-test repeatability: the Keychain session survives app uninstall/reinstall
        // on the Simulator, so a UI test that signs in once would silently skip the
        // sign-in screen on every subsequent run. Let the UI test force a clean slate.
        if CommandLine.arguments.contains("--uitest-reset-auth") {
            try? await StashClient.shared.auth.signOut()
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

    func signOut() async {
        try? await StashClient.shared.auth.signOut()
        state = .signedOut
    }
}
