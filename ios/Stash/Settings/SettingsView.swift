import SwiftUI
import StashKit

/// The Settings tab (Task 7): account info, phone numbers, and subscription status, each
/// a thin `Section`-returning subview (own network reads — "gate logic tested in Task 3; sections
/// are thin reads" per the brief, so none of these need new StashKit tests), plus Sign Out
/// (relocated here from the library toolbar's avatar menu), account deletion (plan 14 T3 —
/// `DeleteAccountSection`, App Store 5.1.1(v)), and a legal/version footer. Tags are
/// retired everywhere (final wave, item E — DESIGN.md: "No tag UI on cards or panel"); the
/// `TagsSection` row this tab used to render was removed, along with its now-orphaned file.
/// `TagsAPI`/the underlying data are untouched in StashKit.
struct SettingsView: View {
    let userId: UUID

    @Environment(SessionStore.self) private var session
    @State private var showSignOutConfirm = false
    // Plan 12 task 4: re-entry point for the post-sign-in "How to easily stash" panel — same
    // `HowToStashView` the sign-in completion hook in `StashApp.swift` presents once per install;
    // here it's reachable any time regardless of `OnboardingState.hasSeenHowToStash`.
    @State private var showHowToStash = false
    // Plan 14 fix wave B (finding #7 — delete-sheet presentation race): owned at the List/root
    // level, not inside `DeleteAccountSection`'s own row — see that type's doc comment for the bug
    // this fixes. `DeleteAccountSection` only flips this via the binding it's handed; the actual
    // `.sheet` lives here, alongside the pre-existing sign-out `.confirmationDialog` and
    // How-to-Stash `.fullScreenCover` — both ROOT-anchored presentations that never exhibited the
    // bug a ROW-anchored one did.
    @State private var showDeleteAccountSheet = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Native numbered list on flat paper; account actions retain their existing routes.
        List {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings").stashFont(.panelTitle)
                    .foregroundStyle(StashColor.ink).accessibilityAddTraits(.isHeader)
                Text("your stash, your rules.").stashFont(.machine).foregroundStyle(StashColor.muted)
            }
            .padding(.vertical, 12)
            .listRowBackground(StashColor.paper)
            AccountSection(userId: userId)
            PhoneSection(userId: userId)
            SubscriptionSection()
            howToStashSection
            signOutSection
            DeleteAccountSection(showSheet: $showDeleteAccountSheet)
            footerSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(StashColor.paper)
        .stashFont(.reading)
        .tint(StashColor.ink)
        .confirmationDialog("Sign out of Stash?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                .accessibilityIdentifier("settings.signout.confirm")
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showHowToStash) {
            HowToStashView()
        }
        .sheet(isPresented: $showDeleteAccountSheet) {
            DeleteAccountConfirmSheet(userId: userId)
                // Plan 16: at the accessibility text sizes the confirmation (copy, field,
                // buttons) no longer fits half a screen — the sheet opens full height there (its
                // content also scrolls).
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
                // Plan 16 (contrast): opaque paper, as on iOS 17. iOS 26 draws a half-height
                // sheet in translucent glass, and the Settings list behind it (the red Sign Out,
                // the legal links) showed through blurred under this sheet's own copy and buttons.
                .presentationBackground(StashColor.paper)
        }
    }

    private var howToStashSection: some View {
        Section {
            Button {
                showHowToStash = true
            } label: {
                HStack {
                    Text("How to stash")
                        .foregroundStyle(StashColor.ink)
                    Spacer()
                    // Plan 16: the row's disclosure glyph is `muted` (an enabled control's glyph;
                    // `faint` is decorative-only) at the meta role's size, scaling with the text.
                    Image(systemName: "chevron.right")
                        .stashFont(.meta)
                        .foregroundStyle(StashColor.muted)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("settings.howToStash")
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                // Plan 16: DESIGN.md's `destructive` (5.06:1 on white) — the system red a
                // destructive List button draws is 3.55:1.
                Text("Sign Out")
                    .foregroundStyle(StashColor.destructive)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("settings.signout")
        }
    }

    private var footerSection: some View {
        Section {
            VStack(spacing: 8) {
                // Side by side while they fit; stacked at the larger text sizes rather than
                // squeezing either name onto two lines.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        privacyLink
                        termsLink
                    }
                    // Stacked, each link gets a real 44 pt row: overhanging targets this close
                    // would overlap, and the lower link would win taps meant for the upper one.
                    VStack(spacing: 0) {
                        privacyLink.frame(minHeight: 44)
                        termsLink.frame(minHeight: 44)
                    }
                }
                // Text actions: the `inlineButton` role (Medium 15 — inline actions are never
                // smaller than 15 pt; they were 12, then meta 13).
                .stashFont(.inlineButton)
                .buttonStyle(.stashPlain)
                Text("Stash \(appVersionString)")
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("settings.footer.version")
                #if DEBUG
                // Plan 7 Task 2: proves PP Neue Montreal actually registered in the app target
                // (vs. silently degrading to the SF Pro fallback) — read by
                // `testDesignSystemFontsLoad`. Plan 9 Task 0 appended the "PP Editorial New" card
                // title face's own load status (`editorial:loaded|fallback`) to the same label
                // rather than adding a second identifier — one DEBUG-only probe point for both
                // bundled font families. DEBUG-only: never ships to TestFlight/App Store.
                Text(fontStatusText)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.muted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("design.fontStatus")
                    .accessibilityLabel(fontStatusText)
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    // The legal links: violet-600 on the grouped background (4.64:1), each a 44 pt target
    // (`.stashPlain`, which also keeps a tap in this row to the link it hits), set in
    // `inlineButton` by the footer.
    private var privacyLink: some View {
        Link(destination: URL(string: "https://gostash.it/privacy")!) {
            Text("Privacy Policy").foregroundStyle(StashColor.violet600)
        }
        .accessibilityIdentifier("settings.footer.privacy")
    }

    private var termsLink: some View {
        Link(destination: URL(string: "https://gostash.it/terms")!) {
            Text("Terms of Service").foregroundStyle(StashColor.violet600)
        }
        .accessibilityIdentifier("settings.footer.terms")
    }

    #if DEBUG
    /// "font:neue-montreal|sf-fallback editorial:loaded|fallback" — see the `design.fontStatus`
    /// call site above. Two independent probes concatenated into one label rather than two
    /// identifiers, since both TTF families' load status is the same kind of fact for the same
    /// audience (an agent/human confirming a font actually bundled after `xcodegen generate`).
    private var fontStatusText: String {
        let neue = StashType.isNeueMontrealAvailable ? "font:neue-montreal" : "font:sf-fallback"
        let editorial = "departure:\(StashType.isDepartureMonoAvailable ? "loaded" : "fallback") jetbrains:\(StashType.isJetBrainsMonoAvailable ? "loaded" : "fallback")"
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

/// A Settings row with a label and its value (plan 16): side by side while the whole value fits
/// on the row's one line; otherwise — a long email at xxxLarge, anything at the accessibility
/// sizes — the value goes under its label and wraps, instead of being truncated to a fragment.
/// The label is `muted` (4.82:1 or better on the grouped list), the value the row's own style.
struct SettingsValueRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).foregroundStyle(StashColor.muted)
                Spacer(minLength: 12)
                value.lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).foregroundStyle(StashColor.muted)
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A Settings section header or footer in `muted` (4.82:1 on the grouped background): the
/// system's secondary label colour is 60 % grey, about 3.3:1 there — under AA for text this size.
/// A plain `Text`, so the List still lays it out as its own header/footer text.
func settingsCaption(_ text: String) -> Text {
    Text(text).font(StashType.Role.secondary.font(nil)).foregroundStyle(StashColor.muted)
}

func settingsHeading(_ text: String) -> Text {
    Text(text.lowercased()).font(StashType.Role.machine.font(nil)).foregroundStyle(StashColor.ink)
}
