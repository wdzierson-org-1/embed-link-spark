import XCTest
@testable import StashKit

/// Parity cases for `PhoneNumber.normalize` (there is no dedicated web test file for
/// `src/utils/phoneNumber.ts` to port line-for-line — verified by search — so these are derived
/// directly from that function's own documented behavior: 10 digits → prepend "1"; already
/// "1" + 10 digits → kept; everything else → invalid).
final class PhoneNumberTests: XCTestCase {
    func testTenDigitsPrependsCountryCode() {
        XCTAssertEqual(PhoneNumber.normalize("5551234567"), .success("15551234567"))
    }

    func testFormattedTenDigitsStripsPunctuationThenPrepends() {
        XCTAssertEqual(PhoneNumber.normalize("(555) 123-4567"), .success("15551234567"))
        XCTAssertEqual(PhoneNumber.normalize("555-123-4567"), .success("15551234567"))
    }

    func testLeadingOnePlusTenDigitsIsKeptAsIs() {
        XCTAssertEqual(PhoneNumber.normalize("15551234567"), .success("15551234567"))
        XCTAssertEqual(PhoneNumber.normalize("+1 (555) 123-4567"), .success("15551234567"))
    }

    func testTooShortIsInvalid() {
        XCTAssertEqual(PhoneNumber.normalize("555123"), .failure(.invalid))
        XCTAssertEqual(PhoneNumber.normalize(""), .failure(.invalid))
    }

    func testTooLongIsInvalid() {
        XCTAssertEqual(PhoneNumber.normalize("155512345678"), .failure(.invalid))
    }

    func testElevenDigitsNotLeadingOneIsInvalid() {
        XCTAssertEqual(PhoneNumber.normalize("25551234567"), .failure(.invalid))
    }

    func testNonNumericInputIsInvalid() {
        XCTAssertEqual(PhoneNumber.normalize("not a phone"), .failure(.invalid))
    }

    /// The punch-list A8 regression case itself: sign-up's raw 10-digit input must normalize to
    /// the SAME shape Settings' `formatPhoneNumber(...).cleanValue` already produces, so both
    /// paths write the identical row for the identical real number.
    func testSignUpAndSettingsPathsAgreeOnTheSameNumber() {
        let signUpRaw = "5551234567"          // what Auth.tsx/SessionStore.signUp sees, unformatted
        let settingsFormatted = "+1 (555) 123-4567"   // what PhoneSection's display formatter shows
        XCTAssertEqual(PhoneNumber.normalize(signUpRaw), PhoneNumber.normalize(settingsFormatted))
    }
}
