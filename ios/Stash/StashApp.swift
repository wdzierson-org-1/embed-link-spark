import SwiftUI
import StashKit

@main
struct StashApp: App {
    @State private var session = SessionStore()

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
            .task { await session.start() }
        }
    }
}
