import SwiftUI
import StashKit

/// Horizontal strip of staged attachments below the composer's text editor: a thumbnail for
/// photos, a doc icon + filename for files, a spinner chip for a pick that is still loading, and
/// an X to remove (or abandon) any of them.
///
/// Plan 15 6D (M7): thumbnails arrive pre-decoded at the chip's pixel size
/// (`AttachmentThumbnail`, made once per pick off the main thread) — this row never decodes an
/// attachment's bytes itself, so re-rendering it while the user types costs nothing.
struct CaptureAttachmentsRow: View {
    /// Chip edge in points — also what the composer sizes thumbnails for.
    static let chipSize: CGFloat = 64

    @Binding var attachments: [CaptureAttachment]
    /// Keyed by `CaptureAttachment.id`. A photo without one (ImageIO couldn't read it) falls back
    /// to the file chip.
    var thumbnails: [UUID: UIImage] = [:]
    /// Picks still loading, shown after the ready chips in the order they were picked.
    var pending: [PendingAttachment] = []
    var cancelPending: (PendingAttachment) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    chip(for: attachment)
                }
                ForEach(pending) { placeholder in
                    pendingChip(placeholder)
                }
            }
            // The remove ×, offset (6, -6) off each chip's top-trailing corner, used to clip
            // against the row's own top edge — `.scrollClipDisabled()` below lets it draw past
            // the ScrollView's implicit content-bounds clip; this padding gives it the room to do
            // so without visually shifting the chips themselves.
            //
            // Plan 16: the × takes a 44 pt target (`.stashPlain`), and a target only works inside
            // the scroll view's own bounds (UIKit doesn't hit-test a scroll view's subviews past
            // its edge, drawn or not) — so the × centre sits 22 pt inside the top edge (it was 13)
            // and the last chip's 22 pt inside the trailing end (it was 11; that end clips once
            // the row overflows and is scrolled to it). Measured by taps (fix round 1): the target
            // takes taps up to 18 pt above the glyph's centre on iOS 17.5 — the scroll view's top
            // ~5 pt take none there — and at least 20 on iOS 26.5; with the old 10 pt, about 9 and
            // 12. `A11yAppUITests.assertAttachmentRemoveTargetTakesATapAtItsTopEdge` taps at 16.
            .padding(.top, 19)
            .padding(.trailing, 19)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(for attachment: CaptureAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            thumbnail(for: attachment)
                .frame(width: Self.chipSize, height: Self.chipSize)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            removeButton(named: "Remove \(attachment.fileName ?? (attachment.kind == .photo ? "photo" : "attachment"))") {
                attachments.removeAll { $0.id == attachment.id }
            }
            .accessibilityIdentifier("capture.attachment.remove")
        }
    }

    /// Same footprint as a ready chip, so the row doesn't shift when the pick lands.
    private func pendingChip(_ placeholder: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            ProgressView()
                .frame(width: Self.chipSize, height: Self.chipSize)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Adding attachment")
                .accessibilityIdentifier("capture.attachment.pending")

            removeButton(named: "Cancel adding attachment") { cancelPending(placeholder) }
                .accessibilityIdentifier("capture.attachment.cancelPending")
        }
    }

    /// The chip's ×: an 18 pt glyph with a 44 pt target (`.stashPlain`), named for VoiceOver and
    /// the Large Content Viewer. The glyph is icon chrome and keeps its size at every text size
    /// (DESIGN.md › Controls (iOS)), like `CircleIcon`'s — a system font, so it follows Bold Text.
    private func removeButton(named name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .font(.system(size: 18))
        }
        .buttonStyle(.stashPlain)
        .stashIconControl(name, systemImage: "xmark.circle.fill")
        .offset(x: 6, y: -6)
    }

    @ViewBuilder
    private func thumbnail(for attachment: CaptureAttachment) -> some View {
        if attachment.kind == .photo, let thumbnail = thumbnails[attachment.id] {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityLabel(attachment.fileName ?? "Photo")
                .accessibilityIdentifier("capture.attachment.thumbnail")
        } else {
            VStack(spacing: 4) {
                // Tile art at the tile's own fixed scale (the 64 pt chip never grows).
                Image(systemName: "doc.fill")
                    .font(StashType.decorative(.book, size: 20))
                    .foregroundStyle(StashColor.muted)
                    .accessibilityHidden(true)
                // Task 5: prefer the real filename captured at pick time; fall back to the bare
                // extension for a camera capture or anything a picker didn't supply a name for.
                // Plan 16: 12 pt Semibold (`.caption`), growing to xxxLarge and stopping there —
                // it sits inside the fixed 64 pt tile, where a larger line would show two letters;
                // VoiceOver reads the whole name. `ink`, not `muted`: the tile's fill stacked on the
                // composer card is #e9e9ed, where `muted` renders 4.44:1 (measured) — under AA.
                Text(attachment.fileName ?? attachment.fileExtension.uppercased())
                    .stashFont(.custom(.semibold, size: 12))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(StashColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("capture.attachment.file")
        }
    }
}
