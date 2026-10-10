import SwiftUI
import StashKit
import UIKit

/// The source address strip: address / edit, or explicit cancel / save while editing.
/// Draft text stays local to the strip until Save. The parent owns durable committed writes.
struct DetailURLBar: View {
    let urlString: String
    var focus: FocusState<DetailField?>.Binding
    var onSave: (String) async -> Bool

    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var needsRetry = false
    @State private var error: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var url: URL? { URL(string: urlString) }

    /// What the bar shows: the whole URL at the standard sizes. At the accessibility sizes it drops
    /// the scheme (2bf review m3), so the host starts line 1 instead of "https://" filling it. The
    /// three lines can then carry the host and the path's end. VoiceOver, Copy link and the long
    /// press keep the whole URL.
    private var displayedURL: String {
        guard dynamicTypeSize.isAccessibilitySize, let separator = urlString.range(of: "://") else {
            return urlString
        }
        // Only a real scheme (RFC 3986: a letter, then letters, digits, "+", "-", "."), never a
        // "://" further into a scheme-less string.
        let scheme = urlString[..<separator.lowerBound]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else {
            return urlString
        }
        return String(urlString[separator.upperBound...])
    }

    /// The long-press preview's text: the URL with a zero-width break opportunity after each "/",
    /// "." and "-" (2bf review m4). So the wrap breaks there rather than hyphenating a word: AX3
    /// showed "reading.exam-" / "ple.com/", a hyphen the URL doesn't have. Display only; Copy link
    /// and VoiceOver use `urlString`.
    private var breakableURL: String {
        var out = ""
        for character in urlString {
            out.append(character)
            if character == "/" || character == "." || character == "-" { out.append("\u{200B}") }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                if editing {
                    TextField("Source address", text: $draft)
                        .stashFont(.code(.footnote))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .focused(focus, equals: .url)
                        .disabled(saving)
                        .accessibilityIdentifier("detail.url.editor")
                        .onSubmit { commit() }
                        .onChange(of: draft) { _, _ in error = nil }
                    cell("Cancel editing address", symbol: "xmark", identifier: "detail.url.cancel",
                         color: StashColor.destructive) { cancel() }
                        .disabled(saving)
                    cell("Save address", symbol: "checkmark", identifier: "detail.url.save",
                         fill: StashColor.spot) { commit() }
                        .disabled(saving)
                } else {
                    address
                    cell("Edit address", symbol: "pencil", identifier: "detail.url.edit") {
                        draft = urlString
                        error = nil
                        editing = true
                        focus.wrappedValue = .url
                    }
                }
            }
            .frame(minHeight: 44)
            .background(StashColor.surface, in: barShape)
            .overlay(barShape.strokeBorder(StashColor.ink, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.urlBar")

            if let error {
                Text(error).stashFont(.secondary).foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("detail.url.error")
            } else if saving {
                StashStatusLine(text: "saving address", busy: true)
                    .accessibilityIdentifier("detail.url.saving")
            }
        }
        .onChange(of: urlString) { _, _ in
            if !editing && !saving { draft = urlString; error = nil }
        }
    }

    private var address: some View {
        HStack(spacing: 10) {
            AsyncImage(url: faviconURL(for: urlString)) { phase in
                if case .success(let image) = phase { image.resizable() } else { Color.clear }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: StashRadius.object))
            .accessibilityHidden(true)
            Text(displayedURL)
                .stashFont(.code(.footnote))
                .foregroundStyle(StashColor.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(urlString)
                .accessibilityIdentifier("detail.urlText")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button { UIPasteboard.general.string = urlString } label: { Label("Copy link", systemImage: "doc.on.doc") }
            if let url { Link(destination: url) { Label("Open link", systemImage: "arrow.up.right.square") } }
        } preview: {
            Text(breakableURL)
                .stashFont(.code(.footnote)).foregroundStyle(StashColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading).padding(16)
                .accessibilityLabel(urlString)
        }
    }

    private func cell(_ label: String, symbol: String, identifier: String,
                      color: Color = StashColor.ink, fill: Color = StashColor.surface,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(color)
                .frame(width: 44, height: 44).background(fill)
                .overlay(alignment: .leading) { Rectangle().fill(StashColor.ink).frame(width: 1) }
        }
        .buttonStyle(.stashPlain)
        .stashIconControl(label, systemImage: symbol)
        .accessibilityIdentifier(identifier)
    }

    private func cancel() {
        editing = false
        needsRetry = false
        draft = urlString
        error = nil
        focus.wrappedValue = nil
    }

    private func commit() {
        guard !saving else { return }
        guard let next = LinkAddressEdit.normalize(draft) else {
            error = "That doesn't look like a web address."
            focus.wrappedValue = .url
            return
        }
        if next == urlString && !needsRetry { cancel(); return }
        saving = true
        error = nil
        focus.wrappedValue = nil
        Task {
            let saved = await onSave(next)
            saving = false
            needsRetry = !saved
            if saved {
                editing = false
                draft = next
            } else {
                error = "Couldn't sync the address. Kept on this device for retry."
            }
        }
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
    }
}
