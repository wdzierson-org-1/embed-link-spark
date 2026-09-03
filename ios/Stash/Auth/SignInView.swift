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

    // Web parity (Auth.tsx checkUsernameUniqueness/checkPhoneUniqueness): live availability
    // probes, debounced ~300ms (the web fires on every keystroke with no debounce — deliberately
    // tightened here to cut mobile network chatter, per plan-7 task-3 fix-round-1 review).
    @State private var usernameError: String?
    @State private var phoneError: String?
    @State private var usernameChecking = false
    @State private var phoneChecking = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var phoneCheckTask: Task<Void, Never>?

    enum AuthMode { case signIn, signUp }
    enum Field: Hashable { case email, password, username, phone }

    var body: some View {
        ZStack {
            StashColor.paper.ignoresSafeArea()
            GradientBackdrop(opacity: 0.3).ignoresSafeArea()

            // Vertically centers the card when it fits the screen (web: `flex min-h-screen
            // items-center justify-center`); only scrolls once the keyboard shrinks the
            // available height below the card's natural size.
            GeometryReader { geo in
                ScrollView {
                    card
                        .padding(.horizontal, 20)
                        .padding(.vertical, 48)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
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

    /// `PillTabs` — the shared component this view's own tab style established (see
    /// `PillTabs.swift`'s doc comment); switching `mode` here also clears any stale sign-in error.
    private var tabPicker: some View {
        PillTabs(
            items: [
                PillTabs<AuthMode>.Item(.signIn, label: "Sign in", identifier: "auth.tab.signIn"),
                PillTabs<AuthMode>.Item(.signUp, label: "Sign up", identifier: "auth.tab.signUp"),
            ],
            selection: Binding(
                get: { mode },
                set: { newValue in
                    mode = newValue
                    session.errorMessage = nil
                }
            )
        )
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
                        .modifier(QuietFieldStyle(focused: focusedField == .username, error: usernameError != nil, leadingPadding: 28))
                        .accessibilityIdentifier("auth.username")
                        .onChange(of: username) { _, newValue in scheduleUsernameCheck(newValue) }
                }
                usernameHelper
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Phone number (optional)", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
                    .modifier(QuietFieldStyle(focused: focusedField == .phone, error: phoneError != nil))
                    .accessibilityIdentifier("auth.phone")
                    .onChange(of: phone) { _, newValue in schedulePhoneCheck(newValue) }
                phoneHelper
            }
        }
    }

    /// Web parity (`Auth.tsx`): error text when taken, else — once `username.count >= 3` — the
    /// dynamic "You'll be @username…" confirmation (shown optimistically, same as web, without
    /// waiting for the debounced probe to resolve), else the generic helper copy.
    @ViewBuilder
    private var usernameHelper: some View {
        if let usernameError {
            Text(usernameError)
                .font(StashType.meta())
                .foregroundStyle(StashColor.destructive)
                .accessibilityIdentifier("auth.username.error")
        } else if username.count >= 3 {
            (
                Text("You'll be ").foregroundStyle(StashColor.muted)
                + Text("@\(username)").foregroundStyle(StashColor.ink).fontWeight(.medium)
                + Text(" on Stash — your public feed lives at gostash.it/feed/\(username)").foregroundStyle(StashColor.muted)
            )
            .font(StashType.meta())
        } else {
            Text("Your username becomes your @handle and your public feed address.")
                .font(StashType.meta())
                .foregroundStyle(StashColor.muted)
        }
    }

    @ViewBuilder
    private var phoneHelper: some View {
        if let phoneError {
            Text(phoneError)
                .font(StashType.meta())
                .foregroundStyle(StashColor.destructive)
                .accessibilityIdentifier("auth.phone.error")
        } else {
            Text("Add your phone number to use WhatsApp for sending notes, voice messages, and asking questions about your content.")
                .font(StashType.meta())
                .foregroundStyle(StashColor.muted)
        }
    }

    // MARK: - Availability probes

    /// Debounced ~300ms (see field-declaration doc comment); cancels any prior in-flight probe
    /// for this field so only the latest keystroke's value is ever checked.
    private func scheduleUsernameCheck(_ value: String) {
        usernameCheckTask?.cancel()
        guard value.count >= 3 else {
            usernameError = nil
            usernameChecking = false
            return
        }
        usernameChecking = true
        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let taken = await session.isUsernameTaken(value)
            guard !Task.isCancelled else { return }
            usernameError = taken ? "This username is already taken. Please choose another." : nil
            usernameChecking = false
        }
    }

    private func schedulePhoneCheck(_ value: String) {
        phoneCheckTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            phoneError = nil
            phoneChecking = false
            return
        }
        phoneChecking = true
        phoneCheckTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let cleanPhone = trimmed.filter(\.isNumber)
            guard !cleanPhone.isEmpty else {
                phoneChecking = false
                return
            }
            let taken = await session.isPhoneTaken(cleanPhone)
            guard !Task.isCancelled else { return }
            phoneError = taken ? "This phone number is already registered. Please use a different number." : nil
            phoneChecking = false
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
                && usernameError == nil && phoneError == nil
                && !usernameChecking && !phoneChecking
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
    var error: Bool = false
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
                    .strokeBorder(
                        error ? StashColor.destructive : (focused ? StashColor.violet300 : StashColor.hairline),
                        lineWidth: focused ? 2 : 1
                    )
            )
    }
}
