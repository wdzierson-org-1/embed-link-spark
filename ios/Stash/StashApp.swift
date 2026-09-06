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

    @State private var showSplash = true
    // Plan 12 task 4: "How to easily stash" panel — set on the `signedIn` transition below when
    // `OnboardingState.hasSeenHowToStash` is still false; `HowToStashView` clears this itself via
    // `\.dismiss` on either of its own buttons (see its doc comment).
    @State private var showHowToStash = false
    // Final wave (F4): the sign-in transition can land WHILE `SplashView` is still up (its own
    // fixed 1.6s timer, independent of how fast `session.start()` resolves) — presenting the
    // `.fullScreenCover` immediately in that case would cut the brand animation off mid-play,
    // covering it. `pendingHowToStash` holds the "yes, show it" decision until the splash's own
    // `.task` below flips `showSplash` false, at which point it's converted into the real
    // `showHowToStash` presentation.
    @State private var pendingHowToStash = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    switch session.state {
                    case .loading: ProgressView()
                    case .signedOut: SignInView()
                    case .signedIn(let userId): MainTabView(userId: userId)
                    }
                }
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .fullScreenCover(isPresented: $showHowToStash) {
                HowToStashView()
            }
            .environment(session)
            .environment(subscriptionStore)
            // DESIGN.md "Color scheme: light-only" (plan 9): Stash renders in the light
            // palette only, regardless of the device's system appearance — pinned here on the
            // root scene content rather than per-surface, so no future view can drift into a
            // dark trait variant by omission.
            .preferredColorScheme(.light)
            .task {
                // Long enough for the gradient's motion to register as intentional, short
                // enough to never feel like a gate — session restore continues underneath.
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
                // Final wave (F4): the sign-in transition below may have already decided to show
                // the panel while this splash was still up — convert that decision into the real
                // presentation now that the brand animation has actually finished.
                if pendingHowToStash {
                    pendingHowToStash = false
                    showHowToStash = true
                }
            }
            .task { await session.start() }
            // "Launch refresh": fires once the session actually resolves to signed-in, whether
            // that's a cold launch restoring a Keychain session or a fresh sign-in from
            // SignInView — both are "the start of a signed-in session" for gate purposes.
            .onChange(of: session.state) { oldState, newState in
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
                    // Final wave (F4): an EXPLICIT sign-in — `oldState` was `.signedOut`, not
                    // `.loading` (a cold-launch Keychain restore never passes through
                    // `.signedOut` first) — gives a previously-deferred panel a fresh chance to
                    // show again. See `OnboardingState`'s doc comment for why this distinction
                    // exists at all (a bare "next `.signedIn`" re-showed on every cold relaunch).
                    if case .signedOut = oldState {
                        OnboardingState.clearHowToStashDeferred()
                    }
                    // Plan 12 task 4: "shown ONCE after a successful sign-in/sign-up" — this fires
                    // on every ACTUAL transition into `.signedIn` (cold-launch restore counts as
                    // "the start of a signed-in session" too, same as the sweep/drain above), but
                    // `SessionState`'s `Equatable` conformance means `onChange` only re-fires when
                    // the case/associated value actually changes, so a same-user token refresh
                    // mid-session never re-triggers this.
                    if !OnboardingState.hasSeenHowToStash && !OnboardingState.isHowToStashDeferred {
                        // Splash still up (see `pendingHowToStash`'s own doc comment) → hold the
                        // decision until it finishes instead of covering the brand animation.
                        if showSplash {
                            pendingHowToStash = true
                        } else {
                            showHowToStash = true
                        }
                    }
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
