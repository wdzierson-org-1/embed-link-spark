import SwiftUI
import StashKit
import UIKit

/// Plan 15 Task 4: the share extension hands its captures to a background `URLSession` shared with
/// the app (`BackgroundCaptureTransfers`) and quits. When a transfer finishes and no process is
/// connected to that session, the system launches or resumes the APP to deliver the events —
/// this is where they arrive. The app never connects to the session otherwise.
final class StashAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard BackgroundCaptureTransfers.shared.handleEvents(forBackgroundURLSession: identifier,
                                                             completionHandler: completionHandler) else {
            completionHandler()   // not a session this app uses
            return
        }
    }
}

@main
struct StashApp: App {
    @UIApplicationDelegateAdaptor(StashAppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    // Constructed once here and handed down via environment (Task 5's scope: the plumbing +
    // launch/foreground refresh). Settings' own 30s while-visible polling is Task 7's addition on
    // top of this same instance.
    @State private var subscriptionStore = SubscriptionStore(checker: SupabaseSubscriptionChecker())
    /// Plan 15 ("Instant library"): the signed-in user's `ItemStore` lives here, at app scope —
    /// created (and hydrated from the disk cache) once per signed-in user, not by `LibraryView`.
    @State private var libraryStores = LibraryStoreProvider()
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
                    case .signedIn(let userId):
                        MainTabView(userId: userId, store: libraryStores.store(for: userId))
                            // A different account never inherits the previous one's tab/search state.
                            .id(userId)
                    }
                }
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
                #if DEBUG
                if UITestHooks.outboxProbeEnabled, case .signedIn(let userId) = session.state {
                    OutboxProbe(userId: userId)
                }
                #endif
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
            .task {
                #if DEBUG
                UITestHooks.applyShareExtensionOverrides()
                #endif
                await session.start()
            }
            // "Launch refresh": fires once the session actually resolves to signed-in, whether
            // that's a cold launch restoring a Keychain session or a fresh sign-in from
            // SignInView — both are "the start of a signed-in session" for gate purposes.
            .onChange(of: session.state) { oldState, newState in
                if case .signedIn(let userId) = newState {
                    Task {
                        await subscriptionStore.refresh()
                        // Plan 14 fix wave B (#11): a park from a PRIOR session (e.g. the app was
                        // never reopened between the 403 and now) has no false→true transition for
                        // this launch to observe — check unconditionally after every refresh
                        // instead.
                        await unparkIfEligible(userId: userId)
                    }
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
                    // Plan 15: leaving a signed-in session — Settings sign-out, account deletion, or
                    // a session the server revoked — drops the library store and its cached first
                    // page + hero images, so nothing of that account stays on device. A launch
                    // whose session restore fails (`.loading → .signedOut`) had no store yet, and
                    // its per-user cache file is only ever read back for the same user.
                    if case .signedIn = oldState {
                        Task { await libraryStores.purge() }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, case .signedIn(let userId) = session.state else { return }
            Task {
                await subscriptionStore.refresh()
                await unparkIfEligible(userId: userId)
            }
            // Plan 15 Task 4: shares the extension left in the Outbox (no token in time, a
            // transfer that failed, one that went stale) go out as soon as the app is back —
            // not only once the Add tab's composer happens to appear.
            Task { await drainIfNeeded(userId: userId) }
        }
    }

    /// Plan 15 Task 4: drains only when something is actually sendable — a `.pending` entry, or
    /// a `.transferring` one whose background transfer went stale (`Outbox.staleTransferInterval`;
    /// the server dedupes by capture id if it did land). A fresh transfer is left to its task.
    private func drainIfNeeded(userId: UUID) async {
        let outbox = Outbox(directory: Outbox.defaultDirectory(userId: userId))
        #if DEBUG
        if let interval = UITestHooks.staleTransferInterval {
            await BackgroundCaptureTransfers.releaseStaleTransfers(in: outbox, olderThan: interval)
        }
        #endif
        let now = Date()
        let sendable = await outbox.pending().contains { entry in
            switch entry.status {
            case .pending: return true
            case .parked: return false
            case .transferring:
                guard let started = entry.transferStartedAt else { return true }
                return now.timeIntervalSince(started) > Outbox.staleTransferInterval
            }
        }
        guard sendable, let token = try? await StashClient.shared.auth.session.accessToken else { return }
        _ = await outbox.drain(api: CaptureAPI(), accessToken: token, userId: userId,
                               upload: { fileURL, path, contentType in
                                   try await uploadToStorageFromFile(fileURL: fileURL, path: path,
                                                                     contentType: contentType, accessToken: token)
                               })
    }

    /// Plan 14 fix wave B (#11): parked entries (Plan 14 T3 Outbox park-on-403) previously only
    /// ever unparked via `CaptureComposerView`'s own `.onChange(of: subscription.canAddContent)`
    /// — a user who resubscribes on the web and never opens the Add tab this session would sit
    /// parked forever. Mirrors that view's own unpark+drain shape, over the same App-Group-backed
    /// `Outbox` directory. Called after EVERY `subscriptionStore.refresh()` (launch AND
    /// foreground), not just on a detected false→true transition: `unparkAll()` is itself the
    /// idempotent guard against a loop — it returns 0 (no drain even attempted) whenever nothing
    /// is parked, which is exactly "parked count > 0 and canAddContent is true" as a standalone
    /// condition, with no separate transition-tracking state needed. A re-park on a still-lapsed
    /// account just waits quietly for the NEXT refresh — never retried in a tight loop from here.
    private func unparkIfEligible(userId: UUID) async {
        guard subscriptionStore.canAddContent else { return }
        let outbox = Outbox(directory: Outbox.defaultDirectory(userId: userId))
        let unparked = await outbox.unparkAll()
        guard unparked > 0, let token = try? await StashClient.shared.auth.session.accessToken else { return }
        _ = await outbox.drain(api: CaptureAPI(), accessToken: token, userId: userId,
                               upload: { fileURL, path, contentType in
                                   try await uploadToStorageFromFile(fileURL: fileURL, path: path,
                                                                     contentType: contentType, accessToken: token)
                               })
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
        // Plan 15 Task 4: request bodies a killed process left behind in the App Group
        // (`StashTransfers/`, older than any live background task could be). The drain below also
        // resends `.transferring` entries whose background transfer went stale — the app never
        // connects to the extension's background session just to find out.
        BackgroundCaptureTransfers.sweepStaleBodyFiles()
        #if DEBUG
        if let interval = UITestHooks.staleTransferInterval {
            await BackgroundCaptureTransfers.releaseStaleTransfers(in: outbox, olderThan: interval)
        }
        #endif

        guard let token = try? await StashClient.shared.auth.session.accessToken else { return }
        _ = await outbox.drain(api: CaptureAPI(), accessToken: token, userId: userId,
                               upload: { fileURL, path, contentType in
                                   try await uploadToStorageFromFile(fileURL: fileURL, path: path,
                                                                     contentType: contentType, accessToken: token)
                               })
    }
}

#if DEBUG
/// UI-test launch arguments for the plan-15 share/background-transfer smokes (DEBUG builds only).
enum UITestHooks {
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// `--uitest-stale-transfer-seconds=<n>`: treat a background transfer as stale after `n`
    /// seconds instead of `Outbox.staleTransferInterval` (600 s), so a relaunch resends it now.
    static var staleTransferInterval: TimeInterval? {
        let prefix = "--uitest-stale-transfer-seconds="
        return arguments.first { $0.hasPrefix(prefix) }.flatMap { TimeInterval($0.dropFirst(prefix.count)) }
    }

    /// `--uitest-outbox-probe`: shows `OutboxProbe` (the signed-in user's Outbox as an
    /// accessibility label) so a UI test can assert what is still queued.
    static var outboxProbeEnabled: Bool { arguments.contains("--uitest-outbox-probe") }

    /// App Group keys the DEBUG share extension reads (`ShareComposeView`). Every DEBUG launch
    /// writes exactly what its arguments ask for and removes the rest, so no test inherits them:
    /// - `--uitest-share-gate-open` → `uitest.shareGateOpen`: lets Save through on the lapsed
    ///   test account. The server still enforces the subscription gate itself (URL and file
    ///   captures are open to lapsed accounts; notes answer 403 and park).
    /// - `--uitest-share-exit-after-handoff=<ms>` → `uitest.shareExitAfterHandoffMs`: the
    ///   extension exits that long after handing the share to the background session, so the
    ///   upload can only finish through the transfer daemon and the app.
    static func applyShareExtensionOverrides() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        if arguments.contains("--uitest-share-gate-open") {
            defaults?.set(true, forKey: "uitest.shareGateOpen")
        } else {
            defaults?.removeObject(forKey: "uitest.shareGateOpen")
        }
        let exitPrefix = "--uitest-share-exit-after-handoff="
        if let value = arguments.first(where: { $0.hasPrefix(exitPrefix) }).flatMap({ Int($0.dropFirst(exitPrefix.count)) }) {
            defaults?.set(value, forKey: "uitest.shareExitAfterHandoffMs")
        } else {
            defaults?.removeObject(forKey: "uitest.shareExitAfterHandoffMs")
        }
    }
}

/// `debug.outbox`: the signed-in user's Outbox, re-read every second, as
/// `count=<n>;<status>:<content, or the url when there's no note>;…` — a 1 pt, non-interactive
/// element for UI tests only.
private struct OutboxProbe: View {
    let userId: UUID
    @State private var summary = "count=?"

    var body: some View {
        Text(summary)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityIdentifier("debug.outbox")
            .accessibilityLabel(summary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .task(id: userId) {
                while !Task.isCancelled {
                    let entries = await Outbox(directory: Outbox.defaultDirectory(userId: userId)).pending()
                    summary = (["count=\(entries.count)"] + entries.map { entry in
                        let content = entry.payload["content"] ?? ""
                        return "\(entry.status.rawValue):\(content.isEmpty ? entry.payload["url"] ?? "" : content)"
                    }).joined(separator: ";")
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }
}
#endif
