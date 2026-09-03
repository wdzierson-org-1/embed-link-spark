import SwiftUI

/// TextField + mic + send, in the web's round-button convention (`StashDesign.swift`): white
/// circles with hairline borders, the send circle violet-filled while there's something to send.
/// Pure input collection — routing (`store.send`, chip/gate handling) lives in `AskView`; this
/// view only reports a tap.
struct ChatComposerBar: View {
    @Binding var text: String
    let isSending: Bool
    var dictation: DictationController
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask, or paste a link / 'remember:' to save", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(StashColor.hairline, lineWidth: 1))
                .accessibilityIdentifier("ask.input")

            if dictation.isSupported, dictation.authorizationState != .denied {
                micButton
            }

            sendButton
        }
    }

    private var micButton: some View {
        Button(action: handleMicTap) {
            // Live dictation keeps its red recording treatment — that's a state signal, not a
            // style; at rest it's the standard circle.
            if dictation.isListening {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.red, in: Circle())
            } else {
                CircleIcon(systemImage: "mic")
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ask.mic")
    }

    private var sendButton: some View {
        Button(action: onSend) {
            CircleSubmitIcon(size: 40, hot: canSend, busy: isSending)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
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
