import SwiftUI
import StashKit

@main
struct StashApp: App {
    @State private var session = SessionStore()
    // Constructed once here and handed down via environment (Task 5's scope: the plumbing +
    // launch/foreground refresh). Settings' own 30s while-visible polling is Task 7's addition on
    // top of this same instance.
    @State private var subscriptionStore = SubscriptionStore(checker: SupabaseSubscriptionChecker())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.state {
                case .loading: ProgressView()
                case .signedOut: SignInView()
                case .signedIn(let userId): MainTabView(userId: userId)
                }
            }
            .environment(session)
            .environment(subscriptionStore)
            .task { await session.start() }
            // "Launch refresh": fires once the session actually resolves to signed-in, whether
            // that's a cold launch restoring a Keychain session or a fresh sign-in from
            // SignInView — both are "the start of a signed-in session" for gate purposes.
            .onChange(of: session.state) { _, newState in
                if case .signedIn = newState {
                    Task { await subscriptionStore.refresh() }
                } else if case .signedOut = newState {
                    // Cross-account gate-bleed fix (final review, plan 3): SubscriptionStore
                    // is app-lifetime (constructed once above), so without this, user A's
                    // status — and any gates A left open — would persist verbatim into user
                    // B's next session. See SubscriptionStore.reset()'s doc comment.
                    subscriptionStore.reset()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, case .signedIn = session.state else { return }
            Task { await subscriptionStore.refresh() }
        }
    }
}
