import SwiftUI
import StashKit

/// Details drawer (DESIGN.md "Detail panel": "**Details drawer** (collapsed by default; summary
/// shows format · size · duration inline; expands to dotted key-value rows incl. original
/// filename and location)"). Port of the web's `EditItemDetailsDrawer.tsx`, with the row set this
/// task's brief specifies: Saved / Type / Size / Duration / Source / Location, each shown only
/// when the item actually carries that fact — never a blank "—" row.
///
/// Collapsed-row summary: a link item shows its domain (`domainOf(item.url)`); a file-backed item
/// shows `format · size · duration` built from the same chip formatters the card grid uses
/// (`CardMetadata.formatFileSizeChip`/`formatDurationChip`), so the two surfaces read identically
/// for the same fact.
struct DetailsDrawer: View {
    let item: Item

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                rows
            }
        }
    }

    // MARK: - Collapsed header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text("DETAILS")
                    .font(StashType.microLabel())
                    .stashTracking(0.11, size: 11)
                    .foregroundStyle(StashColor.faint)
                Spacer(minLength: 8)
                if !isOpen, !summary.isEmpty {
                    Text(summary)
                        .font(StashType.meta())
                        .foregroundStyle(StashColor.faint)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StashColor.faint)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(StashColor.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.isEmpty ? "Details" : "Details, \(summary)")
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("detail.details")
    }

    /// `links: domain`; `file-backed: format · size · duration` (only the parts that have data).
    private var summary: String {
        if item.type == .link {
            return domainOf(item.url)
        }
        return [typeLabel, sizeLabel, durationLabel].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Expanded rows

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: 0) {
            if let savedLabel {
                factRow(key: "saved", label: "Saved", value: savedLabel)
            }
            if let typeLabel {
                factRow(key: "type", label: "Type", value: typeLabel)
            }
            if let sizeLabel {
                factRow(key: "size", label: "Size", value: sizeLabel)
            }
            if let durationLabel {
                factRow(key: "duration", label: "Duration", value: durationLabel)
            }
            if let sourceLabel {
                factRow(key: "source", label: "Source", value: sourceLabel, mono: item.type == .link)
            }
            if let locationLabel {
                factRow(key: "location", label: "Location", value: locationLabel)
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func factRow(key: String, label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? StashType.mono(11.5) : StashType.bodyMedium(13))
                .foregroundStyle(StashColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7.5)
        .overlay(alignment: .bottom) { DottedDivider() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.details.row.\(key)")
    }

    // MARK: - Facts

    private var savedLabel: String? {
        "\(Self.dayFormatter.string(from: item.createdAt)) · \(Self.timeFormatter.string(from: item.createdAt))"
    }

    private var typeLabel: String? { mimeExtensionLabel(item.mimeType) }
    private var sizeLabel: String? { formatFileSizeChip(item.fileSize) }
    private var durationLabel: String? { formatDurationChip(item.attributes.media?.durationS) }

    /// Domain for links, else the original filename the capture pipeline recorded.
    private var sourceLabel: String? {
        if item.type == .link {
            let domain = domainOf(item.url)
            return domain.isEmpty ? nil : domain
        }
        return item.attributes.media?.fileName
    }

    private var locationLabel: String? {
        let label = item.attributes.location?.label
        return (label?.isEmpty ?? true) ? nil : label
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// A single dashed hairline — DESIGN.md's "dotted rule" (`rgba(0,0,0,.18)`), "facts-row
/// separators only". SwiftUI has no CSS `border-style: dotted` equivalent, so this draws one
/// explicitly via a dashed `Path` stroke.
private struct DottedDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(StashColor.dottedRule, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3]))
        }
        .frame(height: 1)
    }
}
