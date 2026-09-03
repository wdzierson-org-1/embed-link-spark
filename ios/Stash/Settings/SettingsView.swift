import SwiftUI
import StashKit

/// The Settings tab (Task 7): account info, phone numbers, and subscription status, each
/// a thin `Section`-returning subview (own network reads — "gate logic tested in Task 3; sections
/// are thin reads" per the brief, so none of these need new StashKit tests), plus Sign Out
/// (relocated here from the library toolbar's avatar menu) and a legal/version footer. Tags are
/// retired everywhere (final wave, item E — DESIGN.md: "No tag UI on cards or panel"); the
/// `TagsSection` row this tab used to render was removed, along with its now-orphaned file.
/// `TagsAPI`/the underlying data are untouched in StashKit.
struct SettingsView: View {
    let userId: UUID

    @Environment(SessionStore.self) private var session
    @State private var showSignOutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            StashHeader()
            List {
                AccountSection(userId: userId)
                PhoneSection(userId: userId)
                SubscriptionSection()
                signOutSection
                footerSection
            }
            .listStyle(.insetGrouped)
            .confirmationDialog("Sign out of Stash?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                    .accessibilityIdentifier("settings.signout.confirm")
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Text("Sign Out").frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("settings.signout")
        }
    }

    private var footerSection: some View {
        Section {
            VStack(spacing: 8) {
                HStack(spacing: 24) {
                    Link("Privacy Policy", destination: URL(string: "https://gostash.it/privacy")!)
                        .accessibilityIdentifier("settings.footer.privacy")
                    Link("Terms of Service", destination: URL(string: "https://gostash.it/terms")!)
                        .accessibilityIdentifier("settings.footer.terms")
                }
                .font(StashType.meta())
                Text("Stash \(appVersionString)")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.muted)
                    .accessibilityIdentifier("settings.footer.version")
                #if DEBUG
                // Plan 7 Task 2: proves PP Neue Montreal actually registered in the app target
                // (vs. silently degrading to the SF Pro fallback) — read by
                // `testDesignSystemFontsLoad`. DEBUG-only: never ships to TestFlight/App Store.
                Text(StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.faint)
                    .accessibilityIdentifier("design.fontStatus")
                    .accessibilityLabel(StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback")
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(shortVersion) (\(build))"
    }
}
