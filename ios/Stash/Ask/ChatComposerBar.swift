import SwiftUI

/// TextField + mic + send. Pure input collection — routing (`store.send`, chip/gate handling)
/// lives in `AskView`; this view only reports a tap.
struct ChatComposerBar: View {
    @Binding var text: String
    let isSending: Bool
    var dictation: DictationController
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask, or paste a link / 'remember:' to save", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("ask.input")

            if dictation.isSupported, dictation.authorizationState != .denied {
                micButton
            }

            sendButton
        }
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            Image(systemName: dictation.isListening ? "waveform" : "mic.fill")
                .imageScale(.medium)
                .foregroundStyle(dictation.isListening ? Color.white : Color.accentColor)
                .frame(width: 34, height: 34)
                .background(dictation.isListening ? Color.red : Color(.secondarySystemBackground),
                            in: Circle())
        }
        .accessibilityIdentifier("ask.mic")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .imageScale(.large)
                .frame(width: 34, height: 34)
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        .accessibilityIdentifier("ask.send")
    }

    private func handleMicTap() {
        Task {
            if dictation.authorizationState == .notDetermined {
                await dictation.requestAuthorization()
            }
            guard dictation.authorizationState == .authorized else { return }
            dictation.toggle()
        }
    }
}
