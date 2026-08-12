import SwiftUI
import StashKit

/// The Settings tab (Task 7): account info, phone numbers, tags, and subscription status, each
/// a thin `Section`-returning subview (own network reads — "gate logic tested in Task 3; sections
/// are thin reads" per the brief, so none of these need new StashKit tests), plus Sign Out
/// (relocated here from the library toolbar's avatar menu) and a legal/version footer.
struct SettingsView: View {
    let userId: UUID

    @Environment(SessionStore.self) private var session
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                AccountSection(userId: userId)
                PhoneSection(userId: userId)
                TagsSection(userId: userId)
                SubscriptionSection()
                signOutSection
                footerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
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
                .font(.footnote)
                Text("Stash \(appVersionString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.footer.version")
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
