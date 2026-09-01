import SwiftUI

/// Launch splash: the wordmark centered over the same pink-hued animated gradient the web's
/// capture surface breathes behind (`StashDesign.AnimatedGradient`). Shown by `StashApp` for a
/// beat on every cold launch, then cross-faded out while session restore continues underneath.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            AnimatedGradient()
                .opacity(0.35)
                .ignoresSafeArea()
            Image("StashWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.primary)
                .accessibilityLabel("Stash")
        }
    }
}
