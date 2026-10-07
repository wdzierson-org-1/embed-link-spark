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
            // Plan 16: the × takes a 44 pt target (`removeButton`), and a target only works inside
            // the scroll view's own bounds (UIKit doesn't hit-test a scroll view's subviews past
            // its edge, drawn or not) — so the × centre sits 22 pt inside the top edge (it was 13)
            // and the last chip's 22 pt inside the trailing end (it was 11; that end clips once
            // the row overflows and is scrolled to it). Measured by taps (fix round 1): a target
            // centred on the glyph takes taps up to 18 pt above the glyph's centre on iOS 17.5 —
            // the scroll view's top ~4 pt take none there — and at least 20 on iOS 26.5; with the
            // old 10 pt, about 9 and 12. That left the × about 40 pt tall on iOS 17, so `removeButton`
            // moves the target 6 pt toward the chip instead (below), and this padding stays 19.
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
                .background(StashColor.fill, in: RoundedRectangle(cornerRadius: StashRadius.object))
                .clipShape(RoundedRectangle(cornerRadius: StashRadius.object))

            removeButton(named: "Remove \(attachment.fileName ?? (attachment.kind == .photo ? "photo" : "attachment"))") {
                attachments.removeAll { $0.id == attachment.id }
            }
            .accessibilityIdentifier("capture.attachment.remove")
        }
    }

    /// Same footprint as a ready chip, so the row doesn't shift when the pick lands.
    private func pendingChip(_ placeholder: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            StashCursor(size: .machineLarge)
                .frame(width: Self.chipSize, height: Self.chipSize)
                .background(StashColor.fill, in: RoundedRectangle(cornerRadius: StashRadius.object))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Adding attachment")
                .accessibilityIdentifier("capture.attachment.pending")

            removeButton(named: "Cancel adding attachment") { cancelPending(placeholder) }
                .accessibilityIdentifier("capture.attachment.cancelPending")
        }
    }

    /// The chip's ×: an 18 pt glyph with a 44 × 44 pt target, named for VoiceOver and the Large
    /// Content Viewer. The glyph is icon chrome and keeps its size at every text size (DESIGN.md ›
    /// Controls (iOS)), like `CircleIcon`'s — a system font, so it follows Bold Text.
    ///
    /// The target is not centred on the glyph (`.stashPlain`'s is): it is moved `removeTargetShift`
    /// pt toward the chip, down and left. The glyph sits on the chip's top-trailing corner, 22 pt
    /// under the row's top edge, and on iOS 17 the scroll view takes no taps in its top ~4 pt — a
    /// centred target was only about 40 pt tall there (44 on iOS 26). Moved, its top edge is 6 pt
    /// inside the scroll view on both, and nothing else changes: the glyph doesn't move, and the
    /// chip's own picture has no tap action for the target to take taps from. The same move keeps
    /// the last chip's target off the end of an overflowing row. (A tap at the target's top edge
    /// and at its bottom-left corner: `A11yAppUITests`.)
    private func removeButton(named name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .background(StashColor.ink)
                .background {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .offset(x: -Self.removeTargetShift, y: Self.removeTargetShift)
                }
        }
        .buttonStyle(.plain)
        .stashIconControl(name, systemImage: "xmark")
        .offset(x: 6, y: -6)
    }

    /// How far the × target moves toward the chip, down and left (`removeButton`).
    private static let removeTargetShift: CGFloat = 6

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
                    .stashFont(.mono(.caption))
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
