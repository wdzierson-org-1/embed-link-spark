import SwiftUI
import StashKit

/// Details drawer (DESIGN.md "Detail panel": "**Details drawer** (collapsed by default; summary
/// shows format · size · duration inline; expands to dotted key-value rows incl. original
/// filename and location)"). Port of the web's `EditItemDetailsDrawer.tsx`, with the row set this
/// task's brief specifies: Saved / Type / Size / Duration / Source / Location, each shown only
/// when the item actually carries that fact — never a blank "—" row.
///
/// **Location lives here, not at the top of the sheet** (Fix round 1, review finding #1): the web
/// mounts `EditItemLocationSection` exclusively inside `EditItemDetailsDrawer`'s own "Location"
/// `FactRow` (`EditItemDetailsDrawer.tsx:149-157`) — there is no second, always-visible location
/// affordance elsewhere on the sheet. `ItemDetailView` previously ALSO mounted `LocationRow`
/// unconditionally near the top, which rendered the fact twice (a static "Location" line in here
/// plus the real editable row up top) and disagreed with the web. Fixed by making the Location
/// row here the one and only mount — same `LocationRow` type, same `detail.location.*`
/// identifiers, just relocated — and deleting the top-of-sheet call.
///
/// The drawer's own open/closed state mirrors the web's exactly: `EditItemDetailsDrawer` always
/// initializes `useState(false)` (collapsed), regardless of whether the item already has a
/// location — it does not special-case "expand by default when there's something to show". This
/// view does the same (`isOpen` starts `false` unconditionally); `testLocationEditSmoke` was
/// updated in this fix round to tap `detail.details` before touching `detail.location.*`, which
/// is the same one extra step a real user now takes on both platforms.
///
/// Collapsed-row summary: a link item shows its domain (`domainOf(item.url)`); a file-backed item
/// shows `format · size · duration` built from the same chip formatters the card grid uses
/// (`CardMetadata.formatFileSizeChip`/`formatDurationChip`), so the two surfaces read identically
/// for the same fact.
struct DetailsDrawer: View {
    let item: Item
    /// Live binding into `ItemDetailView.item.attributes` — the exact same binding the
    /// top-of-sheet `LocationRow` used to receive (`ItemDetailView.attributesBinding`), just
    /// threaded one level deeper now that `LocationRow` itself lives inside this drawer.
    @Binding var attributes: ItemAttributes

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

    /// Plain-text fact rows always draw their own bottom divider — safe because the Location row
    /// below is unconditional (always rendered, per the web's own `{onSaveAttributes && (...)}`
    /// gate, which is always-true here) and always LAST, and it never draws a divider of its own.
    /// So a plain fact row is never actually the last row in the stack, and the location row —
    /// which is — never leaves a trailing dotted line dangling below the final fact (review minor
    /// (b): "no trailing dotted divider after the last fact row", matching the web's `divide-y`
    /// CSS, which only paints separators *between* children).
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
            locationRow
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

    /// Unlike `factRow`, this row gets NO wrapping `.accessibilityIdentifier`/`.accessibilityElement`
    /// at all — verified empirically (Fix round 1): applying an identifier to a plain `HStack`
    /// that never becomes its own accessibility element doesn't create a new row-level identifier
    /// the way it does when paired with `.accessibilityElement(children: .combine)` (as `factRow`
    /// does) — it CASCADES DOWN and overwrites every descendant accessibility element's own
    /// identifier with that same string instead. With a `detail.details.row.location` identifier
    /// here, `LocationRow`'s own `detail.location.label`/`.remove` identifiers were silently
    /// replaced by it, breaking `testLocationEditSmoke`. Leaving this row bare lets `LocationRow`'s
    /// identifiers (`detail.location.add/label/field/remove`) surface untouched, exactly as they
    /// did at its old top-of-sheet mount. No trailing divider — this is always the last row (see
    /// `rows`'s own doc comment).
    private var locationRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Location")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
            Spacer(minLength: 12)
            LocationRow(attributes: $attributes)
        }
        .padding(.vertical, 7.5)
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
