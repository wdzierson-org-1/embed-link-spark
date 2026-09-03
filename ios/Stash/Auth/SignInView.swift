import SwiftUI

/// Web parity: `src/pages/Auth.tsx` — wordmark, "Sign in or create your account.", pill
/// Sign in/Sign up tabs (shared email/password fields underneath, sign-up adds username +
/// optional phone), quiet lavender-tinted inputs, solid violet CTA, on the app's ambient
/// gradient wash. Only `StashColor`/`StashType`/`StashRadius`/`StashShadow` tokens — no literals.
///
/// Identifier note: `signin.email`/`signin.password`/`signin.submit`/`signin.error` are the
/// PRE-EXISTING identifiers many other UI tests hardcode directly (not just through a shared
/// helper) — renaming them would require touching those tests too, which plan-7's coexistence
/// rule for this worktree forbids (append-only edits to `StashUITests.swift`). They're kept
/// as-is here, applying to the always-visible email/password/submit/error elements regardless of
/// which tab is active. Only genuinely NEW elements (the tabs themselves, username, phone) get
/// the brief's `auth.*` namespace.
struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var phone = ""
    @State private var mode: AuthMode = .signIn
    @State private var busy = false
    @FocusState private var focusedField: Field?

    enum AuthMode { case signIn, signUp }
    enum Field: Hashable { case email, password, username, phone }

    var body: some View {
        ZStack {
            StashColor.paper.ignoresSafeArea()
            GradientBackdrop(opacity: 0.3).ignoresSafeArea()

            ScrollView {
                card
                    .padding(.horizontal, 20)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Image("StashWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .foregroundStyle(StashColor.ink)
                .accessibilityLabel("Stash")

            Text("Sign in or create your account.")
                .font(StashType.body())
                .foregroundStyle(StashColor.muted)
                .multilineTextAlignment(.center)

            tabPicker

            VStack(spacing: 12) {
                fields

                if let error = session.errorMessage {
                    Text(error)
                        .font(StashType.meta())
                        .foregroundStyle(StashColor.destructive)
                        .accessibilityIdentifier("signin.error")
                }

                submitButton
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: 400)
        .background(StashColor.paper, in: RoundedRectangle(cornerRadius: StashRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.sheet, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1)
        )
        .stashCardShadow()
    }

    // MARK: - Pill tabs

    private var tabPicker: some View {
        HStack(spacing: 4) {
            tabButton(title: "Sign in", value: .signIn, identifier: "auth.tab.signIn")
            tabButton(title: "Sign up", value: .signUp, identifier: "auth.tab.signUp")
        }
        .padding(4)
        .background(StashColor.wash, in: Capsule())
    }

    private func tabButton(title: String, value: AuthMode, identifier: String) -> some View {
        let selected = mode == value
        return Button {
            mode = value
            session.errorMessage = nil
        } label: {
            Text(title)
                .font(StashType.body())
                .fontWeight(.medium)
                .foregroundStyle(selected ? StashColor.ink : StashColor.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule()
                            .fill(StashColor.paper)
                            .overlay(Capsule().strokeBorder(StashColor.hairline, lineWidth: 1))
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Fields

    @ViewBuilder
    private var fields: some View {
        TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focusedField, equals: .email)
            .modifier(QuietFieldStyle(focused: focusedField == .email))
            .accessibilityIdentifier("signin.email")

        SecureField("Password", text: $password)
            .textContentType(.password)
            .focused($focusedField, equals: .password)
            .modifier(QuietFieldStyle(focused: focusedField == .password))
            .accessibilityIdentifier("signin.password")

        if mode == .signUp {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .leading) {
                    Text("@")
                        .font(StashType.body())
                        .foregroundStyle(StashColor.faint)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                    TextField("username", text: usernameBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .modifier(QuietFieldStyle(focused: focusedField == .username, leadingPadding: 28))
                        .accessibilityIdentifier("auth.username")
                }
                Text("Your username becomes your @handle and your public feed address.")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.muted)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Phone number (optional)", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
                    .modifier(QuietFieldStyle(focused: focusedField == .phone))
                    .accessibilityIdentifier("auth.phone")
                Text("Add your phone number to use WhatsApp for sending notes, voice messages, and asking questions about your content.")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.muted)
            }
        }
    }

    /// Sanitizes to the web's `[^a-z0-9]` strip (Auth.tsx's username `onChange`).
    private var usernameBinding: Binding<String> {
        Binding(
            get: { username },
            set: { newValue in
                username = newValue.lowercased().filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            }
        )
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Text(mode == .signIn ? "Sign in" : "Create account")
                        .font(StashType.body())
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .foregroundStyle(.white)
        .background(StashColor.violet600, in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .disabled(busy || !canSubmit)
        .accessibilityIdentifier("signin.submit")
    }

    private var canSubmit: Bool {
        switch mode {
        case .signIn:
            return !email.isEmpty && !password.isEmpty
        case .signUp:
            return !email.isEmpty && !password.isEmpty && username.count >= 3
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        switch mode {
        case .signIn:
            await session.signIn(email: email, password: password)
        case .signUp:
            let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
            await session.signUp(email: email, password: password, username: username,
                                  phone: trimmedPhone.isEmpty ? nil : trimmedPhone)
        }
    }
}

/// Quiet input chrome (DESIGN.md / Auth.tsx `quietInput`): hairline border, `StashRadius.input`,
/// a lavender `violet300` fill, and a 2pt `violet300` focus ring in place of the hairline.
private struct QuietFieldStyle: ViewModifier {
    var focused: Bool
    var leadingPadding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .font(StashType.body())
            .foregroundStyle(StashColor.ink)
            .padding(.leading, leadingPadding)
            .padding(.trailing, 14)
            .frame(height: 44)
            .background(StashColor.violet300.opacity(0.12), in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                    .strokeBorder(focused ? StashColor.violet300 : StashColor.hairline, lineWidth: focused ? 2 : 1)
            )
    }
}
