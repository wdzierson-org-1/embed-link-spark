import SwiftUI
import StashKit

/// Record → preview → save, all through `AudioRecorderController` + `CaptureViewModel.submitVoiceNote`.
/// Phase is derived entirely from the controller's own state (no separate local phase enum to let
/// drift from it): `.permissionDenied` when mic access was refused, `.recording` while
/// `controller.isRecording`, `.preview` once stopped with a file still on disk, `.idle` before the
/// first tap.
struct VoiceRecorderSheet: View {
    let viewModel: CaptureViewModel
    /// `nil` on cancel (no toast); the real outcome after a Save attempt (success or queued —
    /// `submitVoiceNote` never returns `.rejected`/`.nothingToSave`, see its own doc comment).
    var onFinished: (CaptureOutcome?) -> Void

    @State private var recorder: AudioRecorderController
    @State private var isSaving = false
    /// Review fix (task-6 review, Finding 1): stored so `save()` can check `Task.isCancelled`
    /// after its `await` resumes, before touching `onFinished`/`dismiss()` — the "suspenders" half
    /// of a belt-and-suspenders pair whose "belt" half is disabling Cancel/Re-record/Close for the
    /// duration (below). Nothing cancels this task today (the disabled buttons make that
    /// unreachable from the UI), but the check costs nothing and closes the door on a future
    /// caller wiring up cancellation without rediscovering this exact bug.
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    init(userId: UUID, viewModel: CaptureViewModel, onFinished: @escaping (CaptureOutcome?) -> Void) {
        self.viewModel = viewModel
        self.onFinished = onFinished
        _recorder = State(initialValue: AudioRecorderController(recordingStore: RecordingStore(userId: userId)))
    }

    private enum Phase { case permissionDenied, idle, recording, preview }

    private var phase: Phase {
        if recorder.permissionState == .denied { return .permissionDenied }
        if recorder.isRecording { return .recording }
        if recorder.recordingURL != nil { return .preview }
        return .idle
    }

    var body: some View {
        NavigationStack {
            // Plan 16: centred while it fits, scrolling once the text sizes outgrow the sheet
            // (the same shape as `SignInView`), so nothing is ever cut off at accessibility sizes.
            GeometryReader { geo in
                ScrollView {
                    Group {
                        switch phase {
                        case .permissionDenied: permissionDeniedView
                        case .idle: idleView
                        case .recording: recordingView
                        case .preview: previewView
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { cancelAndDismiss() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("capture.voice.close")
                }
            }
        }
        .task { await recorder.requestPermissionIfNeeded() }
        // Forces an explicit Save/Cancel/Re-record decision once anything has been captured,
        // rather than letting a swipe-to-dismiss silently orphan a local recording file with no
        // Outbox entry pointing at it (that entry is only created on Save — see
        // `submitVoiceNote`'s doc comment). A full app force-quit mid-recording is beyond any view
        // modifier; since plan 15's final wave the recorder finalizes the file on
        // `willTerminateNotification` and the launch sweep recovers it (see
        // `AudioRecorderController`).
        .interactiveDismissDisabled(recorder.recordingURL != nil)
        // Plan 15 H3: with the `audio` background mode a recording would otherwise outlive a
        // sheet that went away some unforeseen way (Close/Cancel/Save all end it first, so this is
        // normally a no-op) — finalize it instead, which also hands back the audio session and the
        // screen's auto-lock. The file stays in `RecordingStore`, where the launch sweep recovers it.
        .onDisappear { recorder.stop() }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            if CaptureTestHooks.showsVoiceProbe { IdleTimerProbe() }
        }
        #endif
    }

    // MARK: - Phases

    private var idleView: some View {
        VStack(spacing: 20) {
            Text("Tap to start recording")
                .stashFont(.readingSemibold)
                .foregroundStyle(StashColor.muted)
                .multilineTextAlignment(.center)
            Button {
                recorder.start()
            } label: {
                Circle()
                    .fill(Color.red)
                    .frame(width: 84, height: 84)
                    .overlay {
                        // Icon chrome (DESIGN.md › Controls (iOS)): the 84 pt button and its
                        // glyph keep their size at every text size; the Large Content Viewer
                        // (`stashIconControl`) shows it large. A system font, so Bold Text applies.
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
            }
            .disabled(recorder.permissionState != .granted)
            .stashIconControl("Record", systemImage: "mic.fill")
            .accessibilityIdentifier("capture.voice.record")
        }
    }

    private var recordingView: some View {
        VStack(spacing: 24) {
            // Tabular monospaced digits for a running timer — DESIGN.md's sanctioned
            // system-monospace exception (`StashType.mono`, "ui-monospace" chip variant), not a
            // Neue Montreal migration candidate. Plan 16: 34 pt (`.largeTitle`), scaling.
            Text(formattedElapsed)
                .stashFont(.mono(.largeTitle))
                .accessibilityIdentifier("capture.voice.timer")
            levelMeter
            actionRow {
                Button("Cancel", role: .destructive) { cancelAndDismiss() }
                    .buttonStyle(.bordered)
                    .tint(StashColor.violet700)
                    .accessibilityIdentifier("capture.voice.cancel")
                Button("Stop") { recorder.stop() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("capture.voice.stop")
            }
        }
    }

    private var previewView: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(StashType.decorative(.book, size: 40))
                .foregroundStyle(StashColor.muted)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                // Same monospace exception as the recording timer above (28 pt, `.title`).
                Text(formattedElapsed)
                    .stashFont(.mono(.title))
                    .accessibilityIdentifier("capture.voice.duration")
                // Plan 15 H3: a phone call, Siri, or another app taking the microphone finalized
                // the take — say where it was cut before the user decides to Save or Re-record.
                if let interruptedAt = recorder.interruptedAt {
                    Text("Recording was interrupted at \(Self.minutesAndSeconds(interruptedAt))")
                        .stashFont(.secondary)
                        .foregroundStyle(StashColor.muted)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("capture.voice.interrupted")
                }
            }
            actionRow {
                Button("Re-record") { reRecord() }
                    .buttonStyle(.bordered)
                    .tint(StashColor.violet700)
                    .disabled(isSaving)
                    .accessibilityIdentifier("capture.voice.rerecord")
                Button("Cancel", role: .destructive) { cancelAndDismiss() }
                    .buttonStyle(.bordered)
                    .tint(StashColor.violet700)
                    .disabled(isSaving)
                    .accessibilityIdentifier("capture.voice.cancel")
                saveButton
            }
        }
    }

    /// The sheet's buttons side by side while they fit, stacked once the text is too big for one
    /// row (xxxLarge and the accessibility sizes) — never squeezed or wrapped mid-word. System
    /// buttons at the large control size: 50 pt tall, 17 pt text that scales (HIG's 44 pt minimum).
    /// The tinted (`.bordered`) ones are violet-700 — violet TEXT on a violet tint (DESIGN.md);
    /// violet-600 there measured "nearly passed" in Xcode's contrast audit (~4.2:1). The filled
    /// ones keep violet-600 (white on it is 5.18:1).
    private func actionRow<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { buttons() }
            VStack(spacing: 12) { buttons() }
        }
        .controlSize(.large)
    }

    private var saveButton: some View {
        Button {
            saveTask = Task { await save() }
        } label: {
            if isSaving {
                ProgressView()
            } else {
                Text("Save")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSaving)
        .accessibilityIdentifier("capture.voice.save")
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(StashType.decorative(.book, size: 40))
                .foregroundStyle(StashColor.muted)
                .accessibilityHidden(true)
            Text("Microphone access needed")
                .stashFont(.readingSemibold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Stash needs microphone access to record voice notes. You can enable it in Settings.")
                .stashFont(.secondary)
                .foregroundStyle(StashColor.muted)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("capture.voice.openSettings")
        }
    }

    // MARK: - Level meter

    private var levelMeter: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.tertiarySystemFill))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red)
                        .frame(width: geo.size.width * CGFloat(recorder.averagePower))
                }
        }
        .frame(height: 8)
        .frame(maxWidth: 220)
        .accessibilityIdentifier("capture.voice.level")
    }

    private var formattedElapsed: String {
        let total = Int(recorder.elapsed.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// "m:ss" — e.g. 0:42, 12:05.
    private static func minutesAndSeconds(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Actions

    private func save() async {
        guard let url = recorder.recordingURL else { return }
        isSaving = true
        // Recorder-elapsed seconds (Task 5) — the same "how long is this" fact a picked
        // audio/video file gets from its `AVAsset` probe, threaded into `attributes.media.duration_s`.
        let outcome = await viewModel.submitVoiceNote(fileURL: url, durationS: recorder.elapsed)
        isSaving = false
        // Suspenders (see `saveTask`'s doc comment): skip firing a late outcome/dismiss if this
        // task was ever cancelled out from under itself.
        guard !Task.isCancelled else { return }
        onFinished(outcome)
        dismiss()
    }

    /// Belt (see `saveTask`'s doc comment): Cancel is disabled for the duration of a save, so this
    /// guard is a redundant safety assert, not the primary defense — kept because disabling a
    /// button doesn't guarantee no action can ever reach its handler (e.g. an in-flight gesture
    /// synthesized just before the disabled state commits). Without it, tapping Cancel mid-save
    /// would delete the file a still-in-flight upload is reading and fire a second, late
    /// `onFinished`/`dismiss()` once that upload's `await` eventually resumes.
    private func cancelAndDismiss() {
        guard !isSaving else { return }
        recorder.cancel()
        onFinished(nil)
        dismiss()
    }

    /// Same belt as `cancelAndDismiss()`: without this guard, Re-record mid-save would replace
    /// `recorder.recordingURL` with a brand-new in-progress recording while the OLD save's `await`
    /// is still in flight — and when that resumes, its `dismiss()` would close the sheet out from
    /// under the new, unsaved take.
    private func reRecord() {
        guard !isSaving else { return }
        recorder.cancel()
        recorder.start()
    }
}

#if DEBUG
/// `debug.idleTimer` (`--uitest-voice-probe`, UI tests only): "disabled" while the screen is being
/// kept awake (`UIApplication.isIdleTimerDisabled`), else "enabled" — re-read 4× a second. A 1 pt,
/// non-interactive element, the same shape as `StashApp`'s `OutboxProbe`.
private struct IdleTimerProbe: View {
    @State private var state = "unknown"

    var body: some View {
        Text(state)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityIdentifier("debug.idleTimer")
            .accessibilityLabel(state)
            .task {
                while !Task.isCancelled {
                    state = UIApplication.shared.isIdleTimerDisabled ? "disabled" : "enabled"
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
    }
}
#endif
