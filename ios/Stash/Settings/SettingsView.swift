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
        // No wordmark/title above this (Will's call, plan 8 — View/Ask/Settings all drop it). The
        // extra `.padding(.top, 8)` this used to carry (meant to match `StashHeader`'s own top
        // inset) is gone (final wave, item E/11 — device review: it left a bare, contentless band
        // above the first section instead); `List`'s own default inset already puts the first
        // section at a normal starting position under the safe area with nothing above it.
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
                // `testDesignSystemFontsLoad`. Plan 9 Task 0 appended the "PP Editorial New" card
                // title face's own load status (`editorial:loaded|fallback`) to the same label
                // rather than adding a second identifier — one DEBUG-only probe point for both
                // bundled font families. DEBUG-only: never ships to TestFlight/App Store.
                Text(fontStatusText)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.faint)
                    .accessibilityIdentifier("design.fontStatus")
                    .accessibilityLabel(fontStatusText)
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    #if DEBUG
    /// "font:neue-montreal|sf-fallback editorial:loaded|fallback" — see the `design.fontStatus`
    /// call site above. Two independent probes concatenated into one label rather than two
    /// identifiers, since both TTF families' load status is the same kind of fact for the same
    /// audience (an agent/human confirming a font actually bundled after `xcodegen generate`).
    private var fontStatusText: String {
        let neue = StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback"
        let editorial = StashType.isEditorialAvailable ? "editorial:loaded" : "editorial:fallback"
        return "\(neue) \(editorial)"
    }
    #endif

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(shortVersion) (\(build))"
    }
}
