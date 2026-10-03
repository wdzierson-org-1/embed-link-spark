import SwiftUI
import StashKit
import Supabase

/// Phone numbers (Task 7): register up to 3 numbers for SMS/WhatsApp capture, mirroring
/// `usePhoneNumber.ts` + `src/utils/phoneNumber.ts`'s `formatPhoneNumber`/
/// `formatStoredPhoneNumber` exactly (clean value = 11 digits, "1" + 10-digit US number, no
/// leading "+" — the brief's own "E.164-ish" hedge acknowledges this isn't true E.164; kept this
/// way for data parity with rows the web already created under this same convention).
///
/// Plan 14 T3 (punch-list A8, "phone storage bug"): the FINAL clean/valid value this view stores
/// now comes from `StashKit.PhoneNumber.normalize` — the single source of truth shared with
/// `SessionStore.signUp` — rather than this file's own private `formatPhoneNumber` below, which
/// stays ONLY as the as-you-type DISPLAY formatter for the text field (cosmetic; never used to
/// decide validity or what gets written to `user_phone_numbers.phone_number` anymore). The two
/// happen to agree on every case today, but only one of them is the contract other platforms and
/// this file's own sign-up counterpart are pinned to.
///
/// **Web-parity gap: no OTP, see known-issues.** `usePhoneNumber.ts`'s `registerPhoneNumber`
/// upserts `verified: true` unconditionally (no verification step exists on either platform yet)
/// — this port matches that as-is rather than unilaterally "fixing" it; a real OTP/verification
/// flow is tracked separately.
struct PhoneSection: View {
    let userId: UUID

    @State private var numbers: [PhoneNumberRow] = []
    @State private var isLoading = true
    @State private var input = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var deleteTarget: PhoneNumberRow?

    /// Display-only — see the type's doc comment above.
    private var formatted: PhoneFormat { formatPhoneNumber(input) }
    /// The authoritative validity check for the "Add" button and `add()` itself.
    private var normalizedInput: Result<String, PhoneNumberError> { PhoneNumber.normalize(input) }
    private var isInputValid: Bool { if case .success = normalizedInput { return true }; return false }

    var body: some View {
        Section {
            if isLoading {
                ProgressView()
            } else {
                ForEach(numbers) { number in
                    row(number)
                }
                if numbers.count < 3 {
                    addRow
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("settings.phone.error")
            }
        } header: {
            settingsCaption("Phone Numbers")
        } footer: {
            settingsCaption("Register up to 3 numbers to send notes via SMS or WhatsApp.")
        }
        .task { await load() }
        .confirmationDialog(
            deleteConfirmMessage,
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Number", role: .destructive) {
                if let target = deleteTarget { Task { await delete(target) } }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
    }

    private var deleteConfirmMessage: String {
        guard let deleteTarget else { return "" }
        return "You will no longer be able to send notes from \(formatStoredPhoneNumber(deleteTarget.phoneNumber)) until you register it again."
    }

    /// Plan 16: the number, its "Verified" note and the remove button on one line while they fit;
    /// at the larger text sizes the note and the button go under the number, which then has the
    /// row's whole width and wraps when even that is too narrow — at AX3 "+1 (555) 123-4567" in
    /// mono is wider than the row — instead of truncating to "+1 (555) 123-45…" (fix round 1).
    private func row(_ number: PhoneNumberRow) -> some View {
        let display = formatStoredPhoneNumber(number.phoneNumber)
        return ViewThatFits(in: .horizontal) {
            HStack {
                phoneText(display)
                    .lineLimit(1)
                if number.verified { verifiedText }
                Spacer()
                removeButton(number, display: display)
            }
            VStack(alignment: .leading, spacing: 4) {
                phoneText(display)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if number.verified { verifiedText }
                    Spacer()
                    removeButton(number, display: display)
                }
            }
        }
        .accessibilityIdentifier("settings.phone.row.\(number.id)")
    }

    /// Tabular mono for the formatted digits — same sanctioned system-monospace exception as the
    /// capture-recorder timer (15 pt, `.subheadline`). One line beside the other controls, as
    /// many as it needs on its own (`row`).
    private func phoneText(_ display: String) -> some View {
        Text(display)
            .stashFont(.mono(.subheadline))
    }

    private var verifiedText: some View {
        Text("Verified")
            .stashFont(.meta)
            .foregroundStyle(StashColor.muted)
    }

    /// A 44 pt target (`.stashPlain` — the tap stays on the button, not the row), named for
    /// VoiceOver and the Large Content Viewer.
    private func removeButton(_ number: PhoneNumberRow, display: String) -> some View {
        Button {
            deleteTarget = number
        } label: {
            Image(systemName: "trash").foregroundStyle(StashColor.destructive)
        }
        .buttonStyle(.stashPlain)
        .stashIconControl("Remove \(display)", systemImage: "trash")
        .accessibilityIdentifier("settings.phone.delete.\(number.id)")
    }

    private var addRow: some View {
        HStack {
            // Plan 16: the placeholder in `muted` (the system's is 1.7:1).
            TextField("Phone number", text: $input,
                      prompt: Text("+1 (555) 123-4567").foregroundStyle(StashColor.muted))
                .keyboardType(.phonePad)
                .onChange(of: input) { _, newValue in input = formatPhoneNumber(newValue).display }
                .accessibilityIdentifier("settings.phone.input")
            if isSaving {
                ProgressView()
            } else {
                // Plan 16: a 44 pt target (`.stashPlain`; it was the word, 31 × 21 pt). A plain
                // button doesn't tint itself: violet-600 while it can act (5.18:1), `faint` while
                // it's disabled (the one use `faint` has for text).
                Button("Add") { Task { await add() } }
                    .buttonStyle(.stashPlain)
                    .foregroundStyle(isInputValid ? StashColor.violet600 : StashColor.faint)
                    .disabled(!isInputValid)
                    .accessibilityIdentifier("settings.phone.add")
            }
        }
    }

    // MARK: - Network

    /// Runs on every appearance (the list stays in place between visits, so only the very first
    /// load shows a spinner; later ones refresh silently). Plan 15 (M6): leaving Settings while
    /// the request is in flight cancels it — that is not a failure, so it neither shows "Couldn't
    /// load phone numbers." nor ends the first-load spinner over an empty list; the next
    /// appearance simply loads again.
    private func load() async {
        // UI tests only (`CaptureTestHooks.phoneFixture`; always nil in Release): one made-up row.
        if let fixture = CaptureTestHooks.phoneFixture {
            numbers = [PhoneNumberRow(id: fixture.id, phoneNumber: fixture.phoneNumber, verified: true)]
            isLoading = false
            return
        }
        if await reload() { isLoading = false }
    }

    /// `false` only when the request was cancelled (nothing learned, nothing shown).
    @discardableResult
    private func reload() async -> Bool {
        do {
            let data = try await StashClient.shared.from("user_phone_numbers")
                .select("id,phone_number,verified")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: true)
                .execute().data
            numbers = try JSONDecoder().decode([PhoneNumberRow].self, from: data)
            // A successful read retires an earlier "couldn't load" (M6 — it used to stick).
            if errorMessage == Self.loadFailedMessage { errorMessage = nil }
            return true
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
            errorMessage = Self.loadFailedMessage
            return true
        }
    }

    private static let loadFailedMessage = "Couldn't load phone numbers."

    private func add() async {
        guard case .success(let clean) = normalizedInput else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        // web-parity gap: no OTP, see known-issues — `verified: true` is set client-side, exactly
        // like `usePhoneNumber.ts`'s `registerPhoneNumber` (no verification step exists yet).
        let body: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "phone_number": .string(clean),
            "verified": .bool(true),
        ]
        do {
            try await StashClient.shared.from("user_phone_numbers")
                .upsert(body, onConflict: "phone_number")
                .execute()
            // Fire-and-forget welcome message (usePhoneNumber.ts:41-48) — its own try/catch on
            // web never fails the registration over this, so `try?` here discards any failure
            // the same way; nothing surfaced to the user either way.
            let welcomeBody: [String: AnyJSON] = ["phoneNumber": .string(clean)]
            try? await StashClient.shared.functions
                .invoke("send-welcome-message", options: FunctionInvokeOptions(body: welcomeBody))
            input = ""
            await reload()
        } catch {
            errorMessage = "Couldn't register that number — try again."
        }
    }

    private func delete(_ number: PhoneNumberRow) async {
        deleteTarget = nil
        errorMessage = nil
        do {
            try await StashClient.shared.from("user_phone_numbers")
                .delete()
                .eq("id", value: number.id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
            numbers.removeAll { $0.id == number.id }
        } catch {
            errorMessage = "Couldn't remove that number — try again."
        }
    }
}

// MARK: - Model + formatting (port of src/utils/phoneNumber.ts)

private struct PhoneNumberRow: Codable, Identifiable, Sendable {
    let id: UUID
    let phoneNumber: String
    let verified: Bool
    enum CodingKeys: String, CodingKey { case id, phoneNumber = "phone_number", verified }
}

private struct PhoneFormat {
    let display: String
    let clean: String
    let isValid: Bool
}

/// Port of `formatPhoneNumber` (src/utils/phoneNumber.ts:7-48) — as-you-type US phone formatting.
/// `clean`: digits only, "1" prepended if missing, capped at 11. `isValid`: exactly 11 digits
/// starting with "1". `display`: `+1 (555) 123-4567`-style, growing as digits are typed.
private func formatPhoneNumber(_ input: String) -> PhoneFormat {
    let digits = input.filter(\.isNumber)
    var cleanDigits = digits
    if !digits.isEmpty, !digits.hasPrefix("1") {
        cleanDigits = "1" + digits
    }
    if cleanDigits.count > 11 {
        cleanDigits = String(cleanDigits.prefix(11))
    }

    var display = ""
    if !cleanDigits.isEmpty {
        display = "+1"
        if cleanDigits.count > 1 {
            let phoneDigits = String(cleanDigits.dropFirst())
            if phoneDigits.count <= 3 {
                display += " (\(phoneDigits)"
            } else if phoneDigits.count <= 6 {
                let area = phoneDigits.prefix(3)
                let rest = phoneDigits.dropFirst(3)
                display += " (\(area)) \(rest)"
            } else {
                let area = phoneDigits.prefix(3)
                let exchange = phoneDigits.dropFirst(3).prefix(3)
                let last = phoneDigits.dropFirst(6)
                display += " (\(area)) \(exchange)-\(last)"
            }
        }
    }

    let isValid = cleanDigits.count == 11 && cleanDigits.hasPrefix("1")
    return PhoneFormat(display: display.isEmpty ? input : display, clean: cleanDigits, isValid: isValid)
}

/// Port of `formatStoredPhoneNumber` (src/utils/phoneNumber.ts:50-58) — redisplays an already
/// clean 11-digit stored value; falls back to the raw string for anything that doesn't match
/// (defensive only — every row this app itself writes already satisfies the shape).
private func formatStoredPhoneNumber(_ phone: String) -> String {
    guard phone.count == 11, phone.hasPrefix("1") else { return phone }
    let areaCode = phone.dropFirst(1).prefix(3)
    let exchange = phone.dropFirst(4).prefix(3)
    let number = phone.dropFirst(7)
    return "+1 (\(areaCode)) \(exchange)-\(number)"
}
