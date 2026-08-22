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
            VStack {
                Spacer()
                switch phase {
                case .permissionDenied: permissionDeniedView
                case .idle: idleView
                case .recording: recordingView
                case .preview: previewView
                }
                Spacer()
            }
            .padding(24)
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
        // `submitVoiceNote`'s doc comment). Doesn't (and can't) cover a full app force-quit
        // mid-recording; that's a disclosed, pre-existing gap, not something a view modifier can
        // close — see task-6-report.md.
        .interactiveDismissDisabled(recorder.recordingURL != nil)
    }

    // MARK: - Phases

    private var idleView: some View {
        VStack(spacing: 20) {
            Text("Tap to start recording")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                recorder.start()
            } label: {
                Circle()
                    .fill(Color.red)
                    .frame(width: 84, height: 84)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
            }
            .disabled(recorder.permissionState != .granted)
            .accessibilityIdentifier("capture.voice.record")
        }
    }

    private var recordingView: some View {
        VStack(spacing: 24) {
            Text(formattedElapsed)
                .font(.system(.largeTitle, design: .monospaced))
                .accessibilityIdentifier("capture.voice.timer")
            levelMeter
            HStack(spacing: 16) {
                Button("Cancel", role: .destructive) { cancelAndDismiss() }
                    .buttonStyle(.bordered)
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
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(formattedElapsed)
                .font(.system(.title, design: .monospaced))
                .accessibilityIdentifier("capture.voice.duration")
            HStack(spacing: 16) {
                Button("Re-record") { reRecord() }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                    .accessibilityIdentifier("capture.voice.rerecord")
                Button("Cancel", role: .destructive) { cancelAndDismiss() }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                    .accessibilityIdentifier("capture.voice.cancel")
                saveButton
            }
        }
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
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Microphone access needed")
                .font(.headline)
            Text("Stash needs microphone access to record voice notes. You can enable it in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
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
