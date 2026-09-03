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
/// `AskView.onDisappear` tears down dictation on the same TabView appear/disappear cycle) is all
/// that's needed; no extra Timer/cleanup plumbing.
struct SubscriptionSection: View {
    @Environment(SubscriptionStore.self) private var subscription

    var body: some View {
        Section("Subscription") {
            statusRow
            Link(destination: URL(string: "https://gostash.it/settings")!) {
                HStack {
                    Text("Manage on gostash.it")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(StashColor.muted)
                }
            }
            .accessibilityIdentifier("settings.subscription.manage")
        }
        .task {
            await subscription.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await subscription.refresh()
            }
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack {
            Text("Status").foregroundStyle(StashColor.muted)
            Spacer()
            if subscription.isLoading {
                ProgressView()
                    .accessibilityIdentifier("settings.subscription.loading")
            } else if let status = subscription.status {
                Text(statusLine(status))
                    .accessibilityIdentifier("settings.subscription.status")
            } else {
                Text(subscription.lastError ?? "Couldn't check your subscription status.")
                    .foregroundStyle(.red)
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
