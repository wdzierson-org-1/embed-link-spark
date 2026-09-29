import AVFoundation
import Foundation
import Observation
import StashKit
import UIKit

/// Owns the record side of a voice note: an `AVAudioSession` record category, an
/// `AVAudioRecorder` writing straight into a fresh `RecordingStore` url (the file exists on disk
/// before there's ever a chance to talk to the network — the whole durability story
/// `RecordingStore`'s own doc comment describes), a 10Hz timer driving `elapsed`/`averagePower`
/// for the sheet's timer + level meter, and start/stop/cancel.
///
/// LONG RECORDINGS (plan 15 H3): a meeting or a lecture keeps recording when the phone is put
/// down. The app declares `UIBackgroundModes: audio` (project.yml), so an active `.record`
/// session keeps the app — and this recorder — running through a screen lock or an app switch;
/// and while recording, the screen is kept awake (`isIdleTimerDisabled`, restored on every way a
/// recording ends — Stop, Cancel, an interruption, the recorder dying, the sheet going away), so
/// the timer and Stop stay in view. Background eligibility comes from the category + the
/// background mode; the session's options (`.duckOthers`, as in Apple's speech-recognition
/// sample) don't affect it. Plan 15 final wave: the app being swiped away mid-recording finalizes
/// the file too (`UIApplication.willTerminateNotification`), so the launch sweep uploads a
/// playable recording.
///
/// AUDIO SESSION CARE (per Task 5's own review fix to the Ask tab's since-removed
/// `DictationController`, carried forward here deliberately, not reinvented): configures
/// `.record` on `start()` and deactivates with `.notifyOthersOnDeactivation` on every
/// stop/cancel; registers the same `AVAudioSession.interruptionNotification` teardown pattern.
/// One deliberate difference from that dictation controller: an interruption there just
/// discarded a live, never-sent transcript, so it tore down exactly like a user-initiated stop.
/// Here, an interruption (phone call, alarm, Siri, another app taking the mic) FINALIZES the audio
/// file (`AVAudioRecorder.stop()` closes and completes it) rather than discarding anything, so
/// whatever was captured so far is preserved via `RecordingStore`, and the sheet lands on its
/// preview state (Save / Re-record / Cancel) with "Recording was interrupted at m:ss" once the
/// user returns (`interruptedAt`). That matches the plan's own rule: "a recording is never
/// destroyed until the server confirms."
///
/// Cross-tab note: this recorder is the app's only microphone client. The Ask tab's read-aloud
/// (plan 15 6A) also uses the shared session — `.playback` while speaking — but never at the same
/// time: the recorder is a modal sheet on the Add tab, and read-aloud stops when the Ask tab goes
/// away. Read-aloud only hands the session back while it's still in its own `.playback` category,
/// so it can't deactivate a recording that took the session over.
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
    /// Where an interruption cut the recording (plan 15 H3) — set when a system interruption
    /// finalized it rather than the user's Stop, for the sheet's "Recording was interrupted at
    /// m:ss" notice. Cleared by the next `start()` and by `cancel()`.
    private(set) var interruptedAt: TimeInterval?

    private let recordingStore: RecordingStore
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// Registered for the duration of a recording only (`start()`…`stop()`/`cancel()`) — same
    /// rationale the former `DictationController` had for its identical property: `@ObservationIgnored` (never
    /// UI-relevant state) + `nonisolated(unsafe)` (plain `nonisolated` is only legal on an
    /// immutable `let`; this needs to stay a mutable `var`), safe because it's only ever mutated
    /// from `@MainActor`-isolated methods while the controller is live, except for one `deinit`
    /// read, which by definition can't race anything else touching `self`.
    @ObservationIgnored
    nonisolated(unsafe) private var interruptionObserver: NSObjectProtocol?

    /// `UIApplication.willTerminateNotification`, registered for the duration of a recording only —
    /// same lifetime and `nonisolated(unsafe)` reasoning as `interruptionObserver`. Plan 15 final
    /// wave: swiping the app away mid-recording (it keeps running in the background with the
    /// `audio` mode, so the system does deliver this) finalizes the file instead of leaving an
    /// unplayable, header-less .m4a for the launch sweep to upload.
    @ObservationIgnored
    nonisolated(unsafe) private var terminationObserver: NSObjectProtocol?

    /// What `UIApplication.isIdleTimerDisabled` was before the current recording started — non-nil
    /// exactly while this controller is keeping the screen awake. Same `nonisolated(unsafe)`
    /// reasoning as `interruptionObserver`: mutated on the main actor only, read once by `deinit`.
    @ObservationIgnored
    nonisolated(unsafe) private var idleTimerSettingBeforeRecording: Bool?

    init(recordingStore: RecordingStore) {
        self.recordingStore = recordingStore
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permissionState = .granted
        case .denied: permissionState = .denied
        default: permissionState = .notDetermined
        }
    }

    /// No-ops once a decision has already been made (never re-prompts) — the same "ask once"
    /// shape the former `DictationController.requestAuthorization()` used for this system
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
            // `.record` keeps recording in the background and through a screen lock, given the
            // app's `audio` background mode — see the type doc.
            try session.setCategory(.record, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let url = recordingStore.newRecordingURL()
        // Review fix (task-6 review, Finding 2): both of these early returns used to leave the
        // session active — `setActive(true)` above had already succeeded, but a failure past that
        // point (a bad recorder init, or `record()` itself refusing) meant no recording ever
        // started to later deactivate the session on `stop()`/`cancel()`. Roll the activation back
        // on both exits, matching the same `.notifyOthersOnDeactivation` teardown used everywhere
        // else in this controller.
        guard let newRecorder = try? AVAudioRecorder(url: url, settings: voiceRecordingSettings) else {
            deactivateSession()
            return
        }
        newRecorder.isMeteringEnabled = true
        guard newRecorder.record() else {
            deactivateSession()
            return
        }

        recorder = newRecorder
        recordingURL = url
        elapsed = 0
        averagePower = 0
        interruptedAt = nil
        isRecording = true
        keepScreenAwake()
        registerInterruptionObserver()
        registerTerminationObserver()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        #if DEBUG
        scheduleSimulatedInterruptionIfRequested()
        #endif
    }

    /// Finalizes the file — `recordingURL` stays set so the caller (the sheet) can move to its
    /// preview state and decide from there. Never deletes anything; that's `cancel()`'s job.
    func stop() {
        guard isRecording else { return }
        // The exact length, not the last 10 Hz tick's (it becomes `media.duration_s`). `max`
        // keeps the tick's value if an interruption already reset the recorder's clock.
        if let recorder { elapsed = max(elapsed, recorder.currentTime) }
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
        interruptedAt = nil
    }

    deinit {
        // Safety net for the (already unlikely — the sheet's owner calls `cancel()`/`stop()`
        // through the normal dismiss paths, and `stop()` again on disappear) case of deallocation
        // while still recording. Reads the stored values directly (not the `@MainActor`-isolated
        // helpers below) since `deinit` isn't guaranteed to run on the main actor.
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let previous = idleTimerSettingBeforeRecording {
            Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = previous }
        }
    }

    private func tick() {
        guard let recorder, isRecording else { return }
        // Plan 15 final wave: the recorder stopped without us — it died, or the media services
        // were reset (neither posts an interruption). Handled like an interruption, so the sheet
        // lands on its preview with what was captured, and the session and screen auto-lock are
        // handed back instead of the timer ticking over a dead recorder.
        guard recorder.isRecording else {
            finishAfterInterruption()
            return
        }
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
        unregisterTerminationObserver()
        deactivateSession()
        restoreScreenIdleTimer()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Keeps the screen from auto-locking for as long as this recording runs (plan 15 H3).
    private func keepScreenAwake() {
        guard idleTimerSettingBeforeRecording == nil else { return }
        idleTimerSettingBeforeRecording = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Puts the setting back the way it was before the recording — on every way a recording ends
    /// (`teardown()` runs for Stop, Cancel and an interruption; the sheet stops on disappear).
    private func restoreScreenIdleTimer() {
        guard let previous = idleTimerSettingBeforeRecording else { return }
        idleTimerSettingBeforeRecording = nil
        UIApplication.shared.isIdleTimerDisabled = previous
    }

    /// A begin-type interruption (phone call, alarm, Siri, another app taking the microphone)
    /// stops (finalizing, not discarding) exactly like `stop()` — see the header doc comment for
    /// why that's the right behavior here, unlike the former `DictationController`'s equivalent —
    /// and records where the recording was cut, for the sheet's notice.
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
            // compiler still sees a nonisolated closure, so hop explicitly.
            Task { @MainActor in self.finishAfterInterruption() }
        }
    }

    private func finishAfterInterruption() {
        guard isRecording else { return }
        stop()
        interruptedAt = elapsed
    }

    private func unregisterInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    /// The app is about to be terminated mid-recording (swiped away from the app switcher while
    /// recording in the background): `stop()` finalizes the file right here, synchronously — the
    /// process may exit as soon as this notification returns, so there is no hopping to another
    /// task. The finished recording stays in `RecordingStore`, where the next launch's sweep
    /// recovers it.
    private func registerTerminationObserver() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func unregisterTerminationObserver() {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
    }

    #if DEBUG
    /// `--uitest-voice-interrupt-after=<s>` (`CaptureTestHooks`): posts exactly what the system
    /// posts when a phone call or Siri takes the session, so `ComposerUITests` can drive the
    /// interruption path on a simulator.
    private func scheduleSimulatedInterruptionIfRequested() {
        guard let delay = CaptureTestHooks.voiceInterruptionDelay else { return }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            NotificationCenter.default.post(
                name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
            )
        }
    }
    #endif
}
