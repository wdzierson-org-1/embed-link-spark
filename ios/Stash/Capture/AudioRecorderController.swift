import AVFoundation
import Foundation
import Observation
import StashKit

/// Owns the record side of a voice note: an `AVAudioSession` record category, an
/// `AVAudioRecorder` writing straight into a fresh `RecordingStore` url (the file exists on disk
/// before there's ever a chance to talk to the network — the whole durability story
/// `RecordingStore`'s own doc comment describes), a 10Hz timer driving `elapsed`/`averagePower`
/// for the sheet's timer + level meter, and start/stop/cancel.
///
/// AUDIO SESSION CARE (per Task 5's own review fix to `DictationController`, carried forward here
/// deliberately, not reinvented): configures `.record` on `start()` and deactivates with
/// `.notifyOthersOnDeactivation` on every stop/cancel; registers the same
/// `AVAudioSession.interruptionNotification` teardown pattern. One deliberate difference from
/// `DictationController`: an interruption there just discards a live, never-sent transcript, so it
/// tears down exactly like a user-initiated stop. Here, `stop()` FINALIZES the audio file
/// (`AVAudioRecorder.stop()` closes and completes it) rather than discarding anything — so an
/// interruption (phone call, alarm, Siri, another app taking the mic) preserves whatever was
/// captured so far via `RecordingStore`, and the sheet naturally lands on its preview state
/// (Save / Re-record / Cancel) once the user returns to the app. That matches the plan's own rule:
/// "a recording is never destroyed until the server confirms."
///
/// Cross-tab note: this controller and `DictationController` can never contend for the microphone
/// at the same time by construction, not by any explicit coordination — dictation lives on the Ask
/// tab, this recorder on the Add tab's composer sheet, and `AskView.onDisappear` already tears its
/// own session down (Task 5) the moment the user switches away from Ask, before the Add tab's mic
/// button is even reachable. No cross-tab plumbing (shared actor, notification, etc.) is needed to
/// keep the two from fighting over `AVAudioSession`.
@MainActor
@Observable
final class AudioRecorderController {
    enum PermissionState { case notDetermined, granted, denied }

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Linear 0...1 level derived from the recorder's own metering (silence reads ~0). The brief's
    /// own note applies here: a simulator's host-mic-silence recording reads near-zero throughout
    /// a run — expected, not a bug, and irrelevant to whether the recording itself is valid.
    private(set) var averagePower: Float = 0
    private(set) var permissionState: PermissionState
    /// Set the instant a recording starts, stays set through `stop()` (the sheet's preview state
    /// reads the file at this URL to preview/submit it), and is only ever cleared by `cancel()`.
    private(set) var recordingURL: URL?

    private let recordingStore: RecordingStore
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// Registered for the duration of a recording only (`start()`…`stop()`/`cancel()`) — same
    /// rationale as `DictationController`'s identical property: `@ObservationIgnored` (never
    /// UI-relevant state) + `nonisolated(unsafe)` (plain `nonisolated` is only legal on an
    /// immutable `let`; this needs to stay a mutable `var`), safe because it's only ever mutated
    /// from `@MainActor`-isolated methods while the controller is live, except for one `deinit`
    /// read, which by definition can't race anything else touching `self`.
    @ObservationIgnored
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    init(recordingStore: RecordingStore) {
        self.recordingStore = recordingStore
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permissionState = .granted
        case .denied: permissionState = .denied
        default: permissionState = .notDetermined
        }
    }

    /// No-ops once a decision has already been made (never re-prompts) — matches
    /// `DictationController.requestAuthorization()`'s "ask once" shape for the same system
    /// permission dance.
    func requestPermissionIfNeeded() async {
        guard permissionState == .notDetermined else { return }
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        permissionState = granted ? .granted : .denied
    }

    func start() {
        guard !isRecording, permissionState == .granted else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let url = recordingStore.newRecordingURL()
        guard let newRecorder = try? AVAudioRecorder(url: url, settings: voiceRecordingSettings) else { return }
        newRecorder.isMeteringEnabled = true
        guard newRecorder.record() else { return }

        recorder = newRecorder
        recordingURL = url
        elapsed = 0
        averagePower = 0
        isRecording = true
        registerInterruptionObserver()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Finalizes the file — `recordingURL` stays set so the caller (the sheet) can move to its
    /// preview state and decide from there. Never deletes anything; that's `cancel()`'s job.
    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        teardown()
    }

    /// Stops (if still recording) AND deletes the file — used when the user explicitly abandons a
    /// recording, from either state's Cancel, or Re-record replacing what's already captured.
    func cancel() {
        if isRecording {
            recorder?.stop()
            teardown()
        }
        if let recordingURL {
            recordingStore.discard(recordingURL)
        }
        recordingURL = nil
    }

    deinit {
        // Safety net for the (already unlikely — the sheet's owner calls `cancel()`/`stop()`
        // through the normal dismiss paths) case of deallocation while still recording. Reads the
        // stored token directly (not the `@MainActor`-isolated helper below) since `deinit` isn't
        // guaranteed to run on the main actor.
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    private func tick() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        let db = recorder.averagePower(forChannel: 0)
        // -60dB floor (not the theoretical -160dB): keeps a normal speaking level filling most of
        // the meter. Clamped both ends since a simulator's silent host mic can read below -60dB.
        averagePower = min(max((db + 60) / 60, 0), 1)
    }

    private func teardown() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        unregisterInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A begin-type interruption (phone call, alarm, Siri, another app taking the microphone)
    /// stops (finalizing, not discarding) exactly like `stop()` — see the header doc comment for
    /// why that's the right behavior here, unlike `DictationController`'s equivalent.
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
}
