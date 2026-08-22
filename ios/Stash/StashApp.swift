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
                if case .signedIn(let userId) = newState {
                    Task { await subscriptionStore.refresh() }
                    // Plan 5 Task 7: startup sweep + drain. `sweepOrphans` recovers any
                    // staged/recorded file that never got an Outbox entry — a crash between
                    // staging and enqueue, in EITHER process (this app, or the share extension,
                    // which never drains itself — memory budget). `drainOutbox` then flushes
                    // whatever's pending, including anything the extension queued while this app
                    // wasn't running at all. `CaptureComposerView`'s own `.task`/foreground drain
                    // still covers "the Add tab appears/returns to foreground" — this covers the
                    // gap before that view has ever appeared on a fresh launch.
                    Task { await sweepAndDrainOnLaunch(userId: userId) }
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

    /// Plan 5 Task 7: mirrors `CaptureViewModel.drainOutbox()`'s own token-fetch-then-file-based-
    /// upload-adapter shape (StashApp has no `CaptureViewModel` of its own to reuse — that's a
    /// per-composer-view instance) — reuses the exact same `Outbox`/`uploadToStorageFromFile`
    /// StashKit surface, just orchestrated once at launch instead of from a view's `.task`.
    /// `sweepOrphans` and `drain` both operate on the SAME per-user App-Group-backed `Outbox`
    /// directory the composer's own drain resolves to (`Outbox.defaultDirectory(userId:)`), so
    /// multiple call sites safely share one directory via the cross-process claim protocol
    /// (Task 3) — this is never a second, competing Outbox.
    private func sweepAndDrainOnLaunch(userId: UUID) async {
        let outbox = Outbox(directory: Outbox.defaultDirectory(userId: userId))
        let recordings = RecordingStore(userId: userId)
        let staging = StagedFileStore(userId: userId)
        _ = await sweepOrphans(userId: userId, outbox: outbox, recordings: recordings, staging: staging)

        guard let token = try? await StashClient.shared.auth.session.accessToken else { return }
        _ = await outbox.drain(api: CaptureAPI(), accessToken: token, userId: userId,
                               upload: { fileURL, path, contentType in
                                   try await uploadToStorageFromFile(fileURL: fileURL, path: path,
                                                                     contentType: contentType, accessToken: token)
                               })
    }
}
