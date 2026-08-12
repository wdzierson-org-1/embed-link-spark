import Foundation
import Observation
import AVFoundation
import Speech

/// Live dictation for the Ask composer: `SFSpeechRecognizer` transcribes microphone audio
/// captured via `AVAudioEngine`, streaming interim results into `transcript` as the user speaks.
/// Mic + speech-recognition authorization are requested together on the first mic tap — both are
/// required before any audio can reach the recognizer, so there's no useful "half authorized"
/// state worth distinguishing for the caller.
///
/// DISCLOSED deviation from the web's `useVoiceInput` (auto-sends the final transcript the
/// instant recognition ends): mobile mis-dictation — background noise, a dropped word, the
/// recognizer cutting off early — is common enough that auto-sending on `stop()` risks firing off
/// a garbled question the user never meant to ask. `stop()` here just leaves the last transcript
/// wherever the caller last mirrored it (the composer's text field), for the user to read, edit,
/// and send explicitly.
@MainActor
@Observable
final class DictationController {
    enum AuthorizationState { case notDetermined, authorized, denied }

    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var authorizationState: AuthorizationState

    /// `en-US` matches the rest of the app's copy (no localization yet). `SFSpeechRecognizer`'s
    /// initializer is failable (no recognizer for this locale on this device) — `isSupported`
    /// reflects that, and the composer hides its mic button accordingly.
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Registered for the duration of a listening session only (`start()`…`stop()`) — an
    /// interruption (phone call, alarm, another app taking the mic) with no observer would leave
    /// `isListening`/the tap/the audio engine stale, since nothing would ever call `stop()`.
    /// `@ObservationIgnored` (not UI-relevant state — never read by any view) + `nonisolated(unsafe)`
    /// (plain `nonisolated` is only legal on an immutable `let`; this needs `(unsafe)` because it's
    /// a `var`): only ever mutated from `@MainActor`-isolated methods while the controller is live,
    /// except for a single read in `deinit`, which is never MainActor-isolated and by definition
    /// can't race any other access to `self` — there's nothing else left to access it.
    /// `@Observable`'s synthesized accessors also reject `nonisolated` outright on a tracked
    /// mutable property, hence opting this one out of observation tracking first.
    @ObservationIgnored
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    var isSupported: Bool { recognizer != nil }

    init() {
        authorizationState = Self.mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
    }

    /// No-ops once a decision has already been made (never re-prompts) — matches
    /// `SubscriptionStore`'s "ask once" shape for a similarly one-shot system permission dance.
    func requestAuthorization() async {
        guard authorizationState == .notDetermined else { return }
        async let speech = Self.requestSpeechAuthorization()
        async let mic = Self.requestMicAuthorization()
        let (speechStatus, micGranted) = await (speech, mic)
        authorizationState = (speechStatus == .authorized && micGranted) ? .authorized : .denied
    }

    func toggle() {
        if isListening { stop() } else { start() }
    }

    func start() {
        guard !isListening, authorizationState == .authorized, let recognizer, recognizer.isAvailable else { return }
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Matches the NSSpeechRecognitionUsageDescription copy ("transcribes your speech
        // on-device") whenever the locale/device combination actually supports it; falls back to
        // the standard (server-assisted) recognizer otherwise rather than failing outright.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.request = nil
            inputNode.removeTap(onBus: 0)
            return
        }

        isListening = true
        registerInterruptionObserver()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // The result handler isn't guaranteed to run on the main thread; hop explicitly
            // before touching any `@MainActor`-isolated state below.
            guard let self else { return }
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            Task { @MainActor in
                if let text { self.transcript = text }
                if error != nil || isFinal { self.stop() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        unregisterInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        // Safety net for the (already unlikely — `AskView.onDisappear` calls `stop()`) case of
        // deallocation while still listening: `stop()`'s own removal above covers the normal path.
        // Reads/uses the stored token directly (not the `@MainActor`-isolated helper method below)
        // since `deinit` isn't guaranteed to run on the main actor.
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    /// A begin-type interruption (phone call, alarm, Siri, another app taking the microphone)
    /// tears down exactly like a user-initiated `stop()` — no attempt to auto-resume once the
    /// interruption ends; the user re-taps the mic like any other stopped state.
    private func registerInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .began
            else { return }
            // `queue: .main` only promises the callback runs on the main thread at runtime; the
            // compiler still sees a nonisolated closure, so hop explicitly to call `stop()`.
            Task { @MainActor in self.stop() }
        }
    }

    private func unregisterInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    private static func requestMicAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }

    private static func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}
