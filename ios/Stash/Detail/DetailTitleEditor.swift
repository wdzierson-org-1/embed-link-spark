import StashKit
import SwiftUI

/// A short reading title and an explicit editor. The draft never enters the item's autosave
/// state until Save, so cancelling or closing cannot publish an unfinished title.
struct DetailTitleEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let placeholder: String
    var focus: FocusState<DetailField?>.Binding
    var onSave: (String) async -> Bool

    @Binding var editing: Bool
    @State private var draft = ""
    @State private var saving = false
    @State private var needsRetry = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing {
                TextField("Title", text: draftBinding,
                          prompt: Text(placeholder).foregroundStyle(StashColor.muted), axis: .vertical)
                    .stashFont(.panelTitle)
                    .stashTracking(-0.02, role: .panelTitle)
                    .foregroundStyle(StashColor.ink)
                    .textFieldStyle(.plain)
                    // At accessibility sizes the keyboard leaves a short viewport. Keep
                    // the full draft scrollable inside the field and its actions in reach.
                    .lineLimit(1...(dynamicTypeSize.isAccessibilitySize ? 2 : 6))
                    .focused(focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { focus.wrappedValue = nil }
                    .padding(10)
                    .background(StashColor.surface)
                    .overlay(Rectangle().strokeBorder(StashColor.ink, lineWidth: 1))
                    .disabled(saving)
                    .accessibilityIdentifier("detail.title.editor")
                HStack(spacing: 12) {
                    Button {
                        editing = false
                        focus.wrappedValue = nil
                        error = nil
                        needsRetry = false
                    } label: {
                        Text("Cancel").stashFont(.textButton)
                            .frame(minWidth: 64, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityIdentifier("detail.title.cancel")
                    Button(action: commit) {
                        Text(saving ? "Saving…" : "Save")
                            .stashFont(.textButtonProminent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(StashColor.white)
                            .background(StashColor.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityIdentifier("detail.title.save")
                }
                if let error {
                    Text(error).stashFont(.secondary).foregroundStyle(StashColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("detail.title.error")
                }
            } else {
                Button {
                    draft = title
                    error = nil
                    editing = true
                } label: {
                    Text(title.isEmpty ? placeholder : title)
                        .stashFont(.panelTitle)
                        .stashTracking(-0.02, role: .panelTitle)
                        .foregroundStyle(title.isEmpty ? StashColor.muted : StashColor.ink)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title.isEmpty ? placeholder : title)
                .accessibilityHint("Edit title")
                .accessibilityIdentifier("detail.title")
            }
        }
        // Wait until the editor exists before handing focus to the shared keyboard control.
        .task(id: editing) {
            if editing { focus.wrappedValue = .title }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { next in
            if let edit = OneLineTitleEdit.resolve(old: draft, new: next) {
                draft = edit.title ?? ""
                if edit.endsEditing { focus.wrappedValue = nil }
            } else { draft = next }
            error = nil
        })
    }

    private func commit() {
        guard !saving else { return }
        if draft == title && !needsRetry {
            editing = false
            focus.wrappedValue = nil
            return
        }
        saving = true
        error = nil
        focus.wrappedValue = nil
        let value = draft
        Task {
            let saved = await onSave(value)
            saving = false
            needsRetry = !saved
            if saved { editing = false }
            else { error = "Couldn't sync the title. Kept on this device for retry." }
        }
    }
}
