#if DEBUG
import SwiftUI
import UIKit

/// `--uitest-type-specimen` (DEBUG builds only — `StashApp` lays this over the window and never
/// starts the session): every `StashType` role, the shared controls, the contrast cases and the
/// text-size / Bold Text state on one screen, no network. Plan 16's `A11yFoundationUITests`
/// measure it — role sizes from rendered widths, hit areas from taps just past each control's
/// edge, Xcode's hit-region / Dynamic Type / contrast audits — and it doubles as the type scale's
/// reference sheet at every size.
///
/// Every sample is the same string so widths compare: a role's point size is 20 × its width ÷ the
/// width of the same string in the same face at a fixed 20 pt (`specimen.ref.<face>`). The
/// references are pinned to regular legibility weight so Bold Text can't move them.
struct TypeSpecimenView: View {
    static let sample = "Stash 0123"

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var taps: [String: Int] = [:]
    @State private var tab = 1
    @State private var systemPlaceholderField = ""
    @State private var mutedPlaceholderField = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(stateLine)
                    .font(.caption2)
                    .foregroundStyle(StashColor.muted)
                    .accessibilityIdentifier("specimen.state")
                Text(metricsLine)
                    .font(.caption2)
                    .foregroundStyle(StashColor.muted)
                    .accessibilityIdentifier("specimen.metrics")
                // On screen at Large, where Xcode's contrast audit can see them.
                washStrip
                placeholders
                HStack(spacing: 12) {
                    Text("muted").stashFont(.meta).foregroundStyle(StashColor.muted)
                    Text("violet-600").stashFont(.meta).foregroundStyle(StashColor.violet600)
                    Text("violet-700").stashFont(.meta).foregroundStyle(StashColor.violet700)
                    Text("faint").stashFont(.meta).foregroundStyle(StashColor.faint)
                        .accessibilityIdentifier("specimen.contrast.faint")
                }
                controls
                Divider()
                ForEach(Self.roles, id: \.name) { role in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Self.sample)
                            .stashFont(role.role)
                            .fixedSize()
                            .accessibilityIdentifier("specimen.role.\(role.name)")
                        Text(role.name)
                            .font(.caption2)
                            .foregroundStyle(StashColor.muted)
                            .accessibilityHidden(true)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Self.sample)
                        .font(StashType.decorative(.book, size: 9))
                        .fixedSize()
                        .accessibilityIdentifier("specimen.role.decorative.book.9")
                    Image(systemName: "mic")
                        .font(StashType.decorative(.medium, size: 28))
                        .accessibilityHidden(true)
                    Image(systemName: "mic")
                        .font(.system(size: 28, weight: .medium))
                        .accessibilityHidden(true)
                    Text("decorative (fixed)")
                        .font(.caption2)
                        .foregroundStyle(StashColor.muted)
                        .accessibilityHidden(true)
                }
                Text("Section label").stashMicroLabel()
                Text("Kicker").stashKicker()
                Divider()
                references
                Divider()
                boldLab
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(StashColor.paper)
    }

    private var stateLine: String {
        let weight = switch legibilityWeight {
        case .bold?: "bold"
        case .regular?: "regular"
        default: "nil"
        }
        return "dts=\(dynamicTypeSize);csc=\(UIApplication.shared.preferredContentSizeCategory.rawValue);"
            + "lw=\(weight);boldText=\(UIAccessibility.isBoldTextEnabled);montreal=\(StashType.isNeueMontrealAvailable)"
    }

    /// What UIKit says for this text size: `UIFontMetrics` scaling of each role's default size by
    /// its style, and the system text style's own point size — to compare with what the roles
    /// render at.
    private var metricsLine: String {
        let traits = UITraitCollection(preferredContentSizeCategory: UIApplication.shared.preferredContentSizeCategory)
        let pairs: [(String, UIFont.TextStyle, CGFloat)] = [
            ("body", .body, 17), ("subheadline", .subheadline, 15), ("footnote", .footnote, 13),
            ("caption1", .caption1, 12), ("title3", .title3, 20), ("title2", .title2, 22),
            ("title1", .title1, 28), ("largeTitle", .largeTitle, 32),
        ]
        return pairs.map { name, style, size in
            let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
            let system = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
            return "\(name):\(String(format: "%.2f", scaled))/\(String(format: "%.1f", system))"
        }.joined(separator: " ")
    }

    // MARK: - Placeholders and the wash

    /// The system placeholder colour (~1.7:1) next to a `prompt:` styled `muted` (5.38:1) — the
    /// placeholder recipe DESIGN.md gives the surfaces.
    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("System placeholder", text: $systemPlaceholderField)
                .stashFont(.reading)
                .accessibilityIdentifier("specimen.placeholder.system")
            TextField("", text: $mutedPlaceholderField,
                      prompt: Text("Muted placeholder").foregroundStyle(StashColor.muted))
                .stashFont(.reading)
                .accessibilityIdentifier("specimen.placeholder.muted")
        }
    }

    /// `StashCancelButton(onWash: true)` over the gradient wash as it is at the top of the View tab
    /// (the animated gradient at 30 % over paper, before `GradientBackdrop`'s fade), beside ink and
    /// violet-600 set straight on it.
    private var washStrip: some View {
        HStack(spacing: 16) {
            Text("ink").stashFont(.textButton).foregroundStyle(StashColor.ink)
                .accessibilityIdentifier("specimen.wash.ink")
            Text("violet-600").stashFont(.textButton).foregroundStyle(StashColor.violet600)
                .accessibilityIdentifier("specimen.wash.violet600")
            Spacer()
            StashCancelButton(identifier: "specimen.cancel.wash", onWash: true) {}
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background {
            AnimatedGradient()
                .opacity(0.3)
                .background(StashColor.paper)
                .clipShape(RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        }
    }

    // MARK: - Shared controls (hit areas)

    /// The controls sit on a tappable surface (like a small button on a card or a row). SwiftUI
    /// hit-tests a touch with a radius — a tap up to ~16 pt past a lone control still reaches it
    /// (measured, plan 16) — but a tap that lands exactly on a surface beneath goes to the surface.
    /// So a tap just past a control's edge reaches the control only when the control's own hit
    /// shape covers that point: the hit area under test.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            surface
            Text(tapsLine)
                .font(.caption2)
                .accessibilityIdentifier("specimen.taps")
        }
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 48) {
                Button { bump("circle36") } label: { CircleIcon(systemImage: "clock", size: 36) }
                    .buttonStyle(.plain)
                    .stashIconControl("Specimen 36 pt circle", systemImage: "clock")
                    .accessibilityIdentifier("specimen.circle36")
                Button { bump("circle40") } label: { CircleIcon(systemImage: "camera") }
                    .buttonStyle(.plain)
                    .stashIconControl("Specimen 40 pt circle", systemImage: "camera")
                    .accessibilityIdentifier("specimen.circle40")
                Button { bump("submit40") } label: { CircleSubmitIcon(size: 40, hot: true) }
                    .buttonStyle(.plain)
                    .stashIconControl("Specimen send circle", systemImage: "paperplane.fill")
                    .accessibilityIdentifier("specimen.submit40")
            }
            PillTabs(items: [PillTabs<Int>.Item(1, label: "Summary", identifier: "specimen.tab.one"),
                             PillTabs<Int>.Item(2, label: "Notes", identifier: "specimen.tab.two")],
                     selection: $tab)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Button { bump("surface") } label: {
                RoundedRectangle(cornerRadius: StashRadius.card, style: .continuous)
                    .fill(StashColor.paper)
                    .overlay(RoundedRectangle(cornerRadius: StashRadius.card, style: .continuous)
                        .strokeBorder(StashColor.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Specimen surface")
            .accessibilityIdentifier("specimen.surface")
        }
    }

    private var tapsLine: String {
        "circle36=\(taps["circle36", default: 0]) circle40=\(taps["circle40", default: 0]) "
            + "submit40=\(taps["submit40", default: 0]) surface=\(taps["surface", default: 0]) "
            + "tab=\(tab == 1 ? "one" : "two")"
    }

    private func bump(_ key: String) { taps[key, default: 0] += 1 }

    // MARK: - Roles

    private struct Row {
        let name: String
        let role: StashType.Role
    }

    /// Every role by the name `A11yFoundationUITests`' contract table uses.
    private static let roles: [Row] = [
        Row(name: "display", role: .display),
        Row(name: "panelTitle", role: .panelTitle),
        Row(name: "screenTitle", role: .screenTitle),
        Row(name: "cardTitle", role: .cardTitle),
        Row(name: "reading", role: .reading),
        Row(name: "readingMedium", role: .readingMedium),
        Row(name: "readingSemibold", role: .readingSemibold),
        Row(name: "readingItalic", role: .readingItalic),
        Row(name: "secondary", role: .secondary),
        Row(name: "secondaryMedium", role: .secondaryMedium),
        Row(name: "secondaryItalic", role: .secondaryItalic),
        Row(name: "meta", role: .meta),
        Row(name: "metaMedium", role: .metaMedium),
        Row(name: "chip", role: .chip),
        Row(name: "microLabel", role: .microLabel),
        Row(name: "kicker", role: .kicker),
        Row(name: "textButton", role: .textButton),
        Row(name: "textButtonProminent", role: .textButtonProminent),
        Row(name: "inlineButton", role: .inlineButton),
        Row(name: "mono.caption", role: .mono(.caption)),
        Row(name: "font.book.14", role: .custom(.book, size: 14)),
        Row(name: "font.medium.24", role: .custom(.medium, size: 24)),
        Row(name: "font.book.9", role: .custom(.book, size: 9)),
        Row(name: "font.semibold.11.caption", role: .custom(.semibold, size: 11, relativeTo: .caption)),
    ]

    // MARK: - References and the Bold Text lab

    private static let faces: [(key: String, postScript: String)] = [
        ("book", "PPNeueMontreal-Book"),
        ("bookItalic", "PPNeueMontreal-BookItalic"),
        ("medium", "PPNeueMontreal-Medium"),
        ("semibold", "PPNeueMontreal-Semibold"),
    ]

    /// Each face at a fixed 20 pt under regular legibility weight — the yardstick for every size —
    /// plus SF Pro at a fixed 20 pt and two system text styles measured against it.
    private var references: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.faces, id: \.key) { face in
                Text(Self.sample)
                    .font(.custom(face.postScript, fixedSize: 20))
                    .fixedSize()
                    .environment(\.legibilityWeight, .regular)
                    .accessibilityIdentifier("specimen.ref.\(face.key)")
            }
            Text(Self.sample)
                .font(.system(size: 20))
                .fixedSize()
                .environment(\.legibilityWeight, .regular)
                .accessibilityIdentifier("specimen.ref.system")
            ForEach([("body", Font.body), ("footnote", Font.footnote)], id: \.0) { name, font in
                Text(Self.sample)
                    .font(font)
                    .fixedSize()
                    .environment(\.legibilityWeight, .regular)
                    .accessibilityIdentifier("specimen.sys.\(name)")
            }
        }
    }

    /// What Bold Text does to each way of asking for a face, side by side with regular weight:
    /// widths change only if a heavier face (or a wider synthesis) is drawn.
    private var boldLab: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.faces, id: \.key) { face in
                labRow("custom.\(face.key)", font: .custom(face.postScript, fixedSize: 20))
            }
            labRow("family.regular", font: .custom("PP Neue Montreal", fixedSize: 20).weight(.regular))
            labRow("family.medium", font: .custom("PP Neue Montreal", fixedSize: 20).weight(.medium))
            labRow("system", font: .system(size: 20))
        }
    }

    private func labRow(_ name: String, font: Font) -> some View {
        HStack(spacing: 12) {
            Text(Self.sample).font(font).fixedSize()
                .environment(\.legibilityWeight, .regular)
                .accessibilityIdentifier("specimen.lab.regular.\(name)")
            Text(Self.sample).font(font).fixedSize()
                .environment(\.legibilityWeight, .bold)
                .accessibilityIdentifier("specimen.lab.bold.\(name)")
        }
    }
}
#endif
