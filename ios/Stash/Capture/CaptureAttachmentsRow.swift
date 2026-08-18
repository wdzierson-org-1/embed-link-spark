import SwiftUI
import StashKit

/// Horizontal strip of staged attachments below the composer's text editor: a thumbnail for
/// photos (`UIImage(data:)`), a doc icon + extension label for files, and an X to remove either.
struct CaptureAttachmentsRow: View {
    @Binding var attachments: [CaptureAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    chip(for: attachment)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(for attachment: CaptureAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            thumbnail(for: attachment)
                .frame(width: 64, height: 64)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.system(size: 18))
            }
            .offset(x: 6, y: -6)
            .accessibilityIdentifier("capture.attachment.remove")
        }
    }

    @ViewBuilder
    private func thumbnail(for attachment: CaptureAttachment) -> some View {
        if attachment.kind == .photo, let uiImage = UIImage(data: attachment.data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                // Task 5: prefer the real filename captured at pick time; fall back to the bare
                // extension for a camera capture or anything a picker didn't supply a name for.
                Text(attachment.fileName ?? attachment.fileExtension.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
