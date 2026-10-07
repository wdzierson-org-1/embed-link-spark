import SwiftUI
import StashKit

/// Subscription status (Task 7): status-line copy ported from `SubscriptionSettings.tsx`'s
/// three-way split — `subscribed` -> "Active", `onTrial` -> "Trial — N days left", else
/// "Expired" (the edge function's `subscribed`/`onTrial` are mutually exclusive — check-subscription
/// /index.ts:92-93,123-126 derive both from one Stripe subscription `status` string, so exactly
/// one can be true at a time). A link out to gostash.it stands in for the web's in-app
/// checkout/customer-portal flow (Stripe Checkout/portal redirects aren't ported to iOS).
///
/// Polling (this section's own addition on top of Task 5's already-wired launch + foreground
/// refresh in `StashApp.swift` — see that file's header comment): refreshes once on appear, then
/// every 30s while this section stays on screen, mirroring the web's `setInterval`
/// (useSubscription.tsx:178-183) but scoped down to "while Settings is visible" rather than the
/// whole app session — `.task`'s built-in cancel-on-disappear (proven already in this codebase:
/// `AskView.onDisappear` lets go of an explicit session on the same TabView appear/disappear cycle) is all
/// that's needed; no extra Timer/cleanup plumbing.
///
/// Plan 15: both pass `force: true` — the app's own launch/foreground refreshes are throttled
/// (`SubscriptionStore.freshnessInterval`), but opening Settings (e.g. right after subscribing on
/// the web) should always show the server's current answer. A check already in flight is joined,
/// not duplicated.
struct SubscriptionSection: View {
    @Environment(SubscriptionStore.self) private var subscription

    var body: some View {
        Section {
            statusRow
            Link(destination: URL(string: "https://gostash.it/settings")!) {
                HStack {
                    Text("Manage on gostash.it")
                    Spacer()
                    // Plan 16: the external-link glyph at the meta role's size, scaling with the
                    // row (it used to be a raw `.caption`); the link's name says where it goes.
                    Image(systemName: "arrow.up.right")
                        .stashFont(.meta)
                        .foregroundStyle(StashColor.muted)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("settings.subscription.manage")
        } header: {
            settingsHeading("03 / Subscription")
        }
        .task {
            await subscription.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await subscription.refresh(force: true)
            }
        }
    }

    /// Plan 16: label above value once they don't fit side by side (`SettingsValueRow`).
    private var statusRow: some View {
        SettingsValueRow(label: "Status") {
            if subscription.isLoading {
                ProgressView()
                    .accessibilityIdentifier("settings.subscription.loading")
            } else if let status = subscription.status {
                Text(statusLine(status))
                    .accessibilityIdentifier("settings.subscription.status")
            } else {
                Text(subscription.lastError ?? "Couldn't check your subscription status.")
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("settings.subscription.status")
            }
        }
    }

    private func statusLine(_ status: SubscriptionStatus) -> String {
        if status.subscribed { return "Active" }
        if status.onTrial { return "Trial — \(status.daysLeft ?? 0) days left" }
        return "Expired"
    }
}
