import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Stash").font(.largeTitle.bold())
            Text("Sign in with your gostash.it account")
                .foregroundStyle(.secondary)
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("signin.email")
            SecureField("Password", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("signin.password")
            if let error = session.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("signin.error")
            }
            Button {
                busy = true
                Task { await session.signIn(email: email, password: password); busy = false }
            } label: {
                if busy { ProgressView() } else { Text("Sign In").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || email.isEmpty || password.isEmpty)
            .accessibilityIdentifier("signin.submit")
            Text("New here? Create your account at gostash.it")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
    }
}
