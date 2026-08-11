import SwiftUI
import StashKit
import PhotosUI
import UniformTypeIdentifiers

/// The Add tab (plan 2's launch tab): a resident capture composer — text, detected URLs,
/// photos, camera, and files, all routed through `CaptureViewModel` with an offline Outbox
/// fallback. No navigation destination of its own on success; per the brief's "Correction for
/// implementability", a successful save only switches to the View tab if the user taps the
/// success toast (default: stay in Add and keep capturing).
struct CaptureComposerView: View {
    let userId: UUID
    var switchToView: () -> Void = {}

    @State private var viewModel: CaptureViewModel
    @State private var isSubmitting = false
    @State private var toast: CaptureToast?
    @State private var toastToken = UUID()

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var showFileImporter = false
    @FocusState private var editorFocused: Bool

    @Environment(\.scenePhase) private var scenePhase

    init(userId: UUID, switchToView: @escaping () -> Void = {}) {
        self.userId = userId
        self.switchToView = switchToView
        // Same custom-init/State(initialValue:) shape LibraryView uses to build its ItemStore —
        // the app is the one place allowed to import UIKit, so it supplies the real
        // UIImage-based `downscale`; StashKit's own default is the identity closure.
        _viewModel = State(initialValue: CaptureViewModel(userId: userId, downscale: downscaleImageData))
    }

    private var canSubmit: Bool {
        !viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachments.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                editor
                if let url = detectFirstURL(in: viewModel.text) {
                    urlChip(url)
                }
                if !viewModel.attachments.isEmpty {
                    CaptureAttachmentsRow(attachments: $viewModel.attachments)
                }
                Spacer(minLength: 0)
                bottomBar
            }
            .padding()
            .navigationTitle("Add")
            .toolbar {
                if viewModel.pendingOutboxCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(viewModel.pendingOutboxCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange, in: Capsule())
                            .accessibilityIdentifier("capture.outboxBadge")
                    }
                }
                // Standard keyboard-accessory dismiss: the composer has no reliable "empty"
                // area to tap once the keyboard pushes the attachments row/bottom bar up
                // against it, so a Done button (always present whenever the keyboard is up,
                // regardless of how little free space remains) is the robust choice here.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                        .accessibilityIdentifier("capture.dismissKeyboard")
                }
            }
        }
        .overlay(alignment: .bottom) { toastView }
        .task { await viewModel.drainOutbox() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await viewModel.drainOutbox() } }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .plainText, .movie, .audio, .image],
                      allowsMultipleSelection: true) { result in
            handleFileImport(result)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    viewModel.attachments.append(
                        CaptureAttachment(data: data, fileExtension: "jpg", mimeType: "image/jpeg", kind: .photo))
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Editor + URL chip

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.text.isEmpty {
                Text("Save a thought, a link, anything…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.text)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("capture.editor")
        }
        // A bounded range, not just `minHeight`: TextEditor has no strong intrinsic content
        // size and will otherwise greedily fill all space the Spacer below would take instead,
        // shoving the URL chip / attachments row down against the bottom bar.
        .frame(minHeight: 160, maxHeight: 220)
    }

    private func urlChip(_ url: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
            Text(url)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityIdentifier("capture.urlchip")
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .imageScale(.large)
            }
            .accessibilityIdentifier("capture.photosPicker")

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCameraPicker = true
                } label: {
                    Image(systemName: "camera")
                        .imageScale(.large)
                }
                .accessibilityIdentifier("capture.cameraButton")
            }

            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "doc.badge.plus")
                    .imageScale(.large)
            }
            .accessibilityIdentifier("capture.fileButton")

            Spacer()

            Toggle(isOn: $viewModel.isPublic) {
                Image(systemName: viewModel.isPublic ? "globe" : "lock")
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("capture.toggle.public")

            saveButton
        }
        .buttonStyle(.bordered)
    }

    private var saveButton: some View {
        Button {
            editorFocused = false
            Task { await submit() }
        } label: {
            if isSubmitting {
                ProgressView()
            } else {
                Text("Save")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting || !canSubmit)
        .accessibilityIdentifier("capture.save")
    }

    // MARK: - Actions

    private func submit() async {
        isSubmitting = true
        let outcome = await viewModel.submit()
        isSubmitting = false
        switch outcome {
        case .saved(let count, let dropped) where dropped == 0:
            show(.saved(message: count > 1 ? "Saved \(count) items" : "Saved", hadDrops: false))
        case .saved(let count, let dropped):
            show(.saved(message: "Saved \(count) — \(dropped) couldn't be saved (too large or failed)",
                        hadDrops: true))
        case .queued(_, let dropped):
            var message = "Offline — will sync (\(viewModel.pendingOutboxCount) pending)"
            if dropped > 0 { message += " — \(dropped) couldn't be saved" }
            show(.queued(message: message))
        case .rejected:
            show(.rejected(message: "Couldn't save — file too large or upload failed"))
        case .nothingToSave:
            break
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let mime = type?.preferredMIMEType ?? "image/jpeg"
            viewModel.attachments.append(CaptureAttachment(data: data, fileExtension: ext, mimeType: mime, kind: .photo))
        }
        selectedPhotoItems = []
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
            let type = UTType(filenameExtension: ext)
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            let kind: CaptureAttachment.Kind = (type?.conforms(to: .image) ?? false) ? .photo : .file
            viewModel.attachments.append(CaptureAttachment(data: data, fileExtension: ext, mimeType: mime, kind: kind))
        }
    }

    // MARK: - Toast

    private func show(_ toast: CaptureToast) {
        let token = UUID()
        toastToken = token
        withAnimation { self.toast = toast }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastToken == token { withAnimation { self.toast = nil } }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(toast.color, in: Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 20)
                .accessibilityIdentifier("capture.toast")
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    if case .saved = toast { switchToView() }
                    withAnimation { self.toast = nil }
                }
        }
    }
}

private enum CaptureToast: Equatable {
    case saved(message: String, hadDrops: Bool)
    case queued(message: String)
    case rejected(message: String)

    var message: String {
        switch self {
        case .saved(let message, _), .queued(let message), .rejected(let message): message
        }
    }

    // Amber whenever something didn't make it (dropped attachments, offline queueing, or an
    // outright rejection) — green is reserved for a fully clean save (fix round: a partially
    // dropped save must not read as an unqualified success).
    var color: Color {
        switch self {
        case .saved(_, let hadDrops): hadDrops ? .orange : .green
        case .queued, .rejected: .orange
        }
    }
}

/// Re-encodes oversized photo attachments as JPEG, capped at 4096px on the long side (mirrors
/// the web's upload limits, MediaUploadTypes.ts:26-28). Passed to `CaptureViewModel` as its
/// `downscale` hook so StashKit itself never has to import UIKit. Always re-encodes at the
/// target quality (not just when the long side is over budget) so the hook's contract — "bring
/// this under the size limit" — holds even when the size problem was format (e.g. a lossless
/// PNG) rather than dimensions.
@Sendable private func downscaleImageData(_ data: Data) -> Data {
    guard let image = UIImage(data: data) else { return data }
    let maxDimension: CGFloat = 4096
    let longSide = max(image.size.width, image.size.height)
    let scale = longSide > maxDimension ? maxDimension / longSide : 1
    let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    return resized.jpegData(compressionQuality: 0.85) ?? data
}
