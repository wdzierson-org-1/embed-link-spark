import SwiftUI
import StashKit
import Supabase

/// Phone numbers (Task 7): register up to 3 numbers for SMS/WhatsApp capture, mirroring
/// `usePhoneNumber.ts` + `src/utils/phoneNumber.ts`'s `formatPhoneNumber`/
/// `formatStoredPhoneNumber` exactly (clean value = 11 digits, "1" + 10-digit US number, no
/// leading "+" — the brief's own "E.164-ish" hedge acknowledges this isn't true E.164; kept this
/// way for data parity with rows the web already created under this same convention).
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

    private var formatted: PhoneFormat { formatPhoneNumber(input) }

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
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.phone.error")
            }
        } header: {
            Text("Phone Numbers")
        } footer: {
            Text("Register up to 3 numbers to send notes via SMS or WhatsApp.")
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

    private func row(_ number: PhoneNumberRow) -> some View {
        HStack {
            Text(formatStoredPhoneNumber(number.phoneNumber))
                .font(.system(.body, design: .monospaced))
            if number.verified {
                Text("Verified")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                deleteTarget = number
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("settings.phone.delete.\(number.id)")
        }
        .accessibilityIdentifier("settings.phone.row.\(number.id)")
    }

    private var addRow: some View {
        HStack {
            TextField("+1 (555) 123-4567", text: $input)
                .keyboardType(.phonePad)
                .onChange(of: input) { _, newValue in input = formatPhoneNumber(newValue).display }
                .accessibilityIdentifier("settings.phone.input")
            if isSaving {
                ProgressView()
            } else {
                Button("Add") { Task { await add() } }
                    .disabled(!formatted.isValid)
                    .accessibilityIdentifier("settings.phone.add")
            }
        }
    }

    // MARK: - Network

    private func load() async {
        defer { isLoading = false }
        await reload()
    }

    private func reload() async {
        do {
            let data = try await StashClient.shared.from("user_phone_numbers")
                .select("id,phone_number,verified")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: true)
                .execute().data
            numbers = try JSONDecoder().decode([PhoneNumberRow].self, from: data)
        } catch {
            errorMessage = "Couldn't load phone numbers."
        }
    }

    private func add() async {
        guard formatted.isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        // web-parity gap: no OTP, see known-issues — `verified: true` is set client-side, exactly
        // like `usePhoneNumber.ts`'s `registerPhoneNumber` (no verification step exists yet).
        let body: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "phone_number": .string(formatted.clean),
            "verified": .bool(true),
        ]
        do {
            try await StashClient.shared.from("user_phone_numbers")
                .upsert(body, onConflict: "phone_number")
                .execute()
            // Fire-and-forget welcome message (usePhoneNumber.ts:41-48) — its own try/catch on
            // web never fails the registration over this, so `try?` here discards any failure
            // the same way; nothing surfaced to the user either way.
            let welcomeBody: [String: AnyJSON] = ["phoneNumber": .string(formatted.clean)]
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
