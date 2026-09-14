import Foundation

/// Port of `src/utils/phoneNumber.ts`'s STORAGE half — the final, validated digit string this
/// app ever writes to `user_phone_numbers.phone_number` — as distinct from that same web file's
/// `formatPhoneNumber` as-you-type DISPLAY formatting, which stays a small, purely cosmetic
/// concern local to `PhoneSection`'s own text field (plan-14 Global Constraints: "the display
/// formatter there can stay").
///
/// Punch-list A8 ("phone storage bug"): web's sign-up path (`Auth.tsx handleSignUp` →
/// `usePhoneNumber.ts registerPhoneNumber`) passes the RAW typed string straight through a bare
/// `phone.replace(/\D/g, '')` — no leading-"1" normalization — while web's Settings path
/// (`PhoneNumberSetup.tsx`) first runs the input through `formatPhoneNumber(...).cleanValue`
/// (which DOES prepend "1") before ever calling `registerPhoneNumber`. The two paths therefore
/// store two different shapes for the same real number (10 digits vs. 11-digit "1"-prefixed),
/// which is the bug: `checkPhoneUniqueness`/WhatsApp inbound matching key on the digit string
/// verbatim, so a sign-up-created row silently never matches its Settings-created twin. `iOS`
/// closes this by running EVERY phone-number write (sign-up and Settings) through this one
/// function, so both paths always produce the same normalized shape.
public enum PhoneNumberError: Error, Equatable, Sendable {
    case invalid
}

public enum PhoneNumber {
    /// Strips every non-digit character first (parity with web's `input.replace(/\D/g, '')`), so
    /// `"+1 (555) 123-4567"`, `"555-123-4567"`, and `"5551234567"` all normalize identically.
    ///
    /// - Exactly 10 digits → assume US, prepend the country code: `"1" + digits`.
    /// - Exactly 11 digits, leading "1" → already E.164-without-plus; kept as-is.
    /// - Anything else (too short, too long, 11 digits NOT leading "1", non-numeric-only input
    ///   with no digits at all) → `.invalid`. There is no partial/best-effort success case —
    ///   this is the FINAL validation gate, not the as-you-type formatter.
    public static func normalize(_ input: String) -> Result<String, PhoneNumberError> {
        let digits = input.filter(\.isNumber)
        switch digits.count {
        case 10:
            return .success("1" + digits)
        case 11 where digits.hasPrefix("1"):
            return .success(digits)
        default:
            return .failure(.invalid)
        }
    }
}
