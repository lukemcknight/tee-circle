import XCTest
@testable import TeeCircle

/// The client rules here exist only to gate the submit button; the server
/// revalidates everything. These tests pin them to the same shapes as
/// `tee_internal.normalize_username` and `src/utils/username.ts` so a handle
/// accepted in one place is never rejected in another.
final class ProfileIdentityTests: XCTestCase {
    func testUsernameNormalizationMatchesTheSharedRule() {
        XCTAssertEqual(Username.normalize("  @JordanBell  "), "jordanbell")
        XCTAssertEqual(Username.normalize("@@doubled"), "doubled")
        XCTAssertEqual(Username.normalize("Mixed_Case-99"), "mixed_case-99")
        XCTAssertEqual(Username.normalize("   "), "")
    }

    func testUsernameValidationBoundaries() {
        XCTAssertFalse(Username.isValid("ab"), "two characters is below the shared minimum")
        XCTAssertTrue(Username.isValid("abc"))
        XCTAssertTrue(Username.isValid(String(repeating: "a", count: 20)))
        XCTAssertFalse(Username.isValid(String(repeating: "a", count: 21)))
        XCTAssertTrue(Username.isValid("with_underscore-and-hyphen".prefix(20).description))
        XCTAssertFalse(Username.isValid("has spaces"))
        XCTAssertFalse(Username.isValid("emoji⛳️golf"))
        XCTAssertFalse(Username.isValid("dots.not.allowed"))
    }

    func testUsernameValidationAcceptsAHandleThatOnlyNormalizesToValid() {
        // The form should accept what the user typed, because the value sent to
        // the server is the normalized one.
        XCTAssertTrue(Username.isValid("@JordanBell"))
        XCTAssertNil(Username.validationMessage(for: "  @JordanBell "))
    }

    func testUsernameValidationMessagesAreSpecific() {
        XCTAssertNotNil(Username.validationMessage(for: ""))
        XCTAssertNotNil(Username.validationMessage(for: "ab"))
        XCTAssertNotNil(Username.validationMessage(for: String(repeating: "a", count: 21)))
        XCTAssertNotNil(Username.validationMessage(for: "has spaces"))
        XCTAssertNil(Username.validationMessage(for: "valid-handle"))
    }

    func testUsernameDisplayAddsTheAtSignOnlyForPresentation() {
        XCTAssertEqual(Username.display("jordanbell"), "@jordanbell")
        XCTAssertNil(Username.display(nil))
        XCTAssertNil(Username.display(""))
    }

    func testPlayerNameMatchesTheLegacyColumnLimit() {
        XCTAssertFalse(PlayerName.isValid("   "))
        XCTAssertTrue(PlayerName.isValid("  Jordan Bell  "))
        XCTAssertEqual(PlayerName.normalize("  Jordan Bell  "), "Jordan Bell")
        XCTAssertTrue(PlayerName.isValid(String(repeating: "a", count: 80)))
        XCTAssertFalse(PlayerName.isValid(String(repeating: "a", count: 81)))
    }

    func testUsernameFailureCodesRouteToTheHandleField() {
        XCTAssertTrue(ProfileSaveOutcome.failed(code: "username_taken", message: "x").isUsernameProblem)
        XCTAssertTrue(ProfileSaveOutcome.failed(code: "invalid_username", message: "x").isUsernameProblem)
        XCTAssertFalse(ProfileSaveOutcome.failed(code: "invalid_request", message: "x").isUsernameProblem)
        XCTAssertFalse(ProfileSaveOutcome.failed(code: nil, message: "x").isUsernameProblem)
        XCTAssertFalse(ProfileSaveOutcome.saved.isUsernameProblem)
    }

    func testProfileIsIncompleteUntilBothFieldsExist() {
        XCTAssertTrue(NativeProfileV1(userId: "u", fullName: "Jordan", username: "jordan").isComplete)
        XCTAssertFalse(NativeProfileV1(userId: "u", fullName: "Jordan", username: nil).isComplete)
        XCTAssertFalse(NativeProfileV1(userId: "u", fullName: nil, username: "jordan").isComplete)
        XCTAssertFalse(NativeProfileV1(userId: "u", fullName: "", username: "jordan").isComplete)
        XCTAssertFalse(NativeProfileV1(userId: "u", fullName: "Jordan", username: "").isComplete)
    }

    func testAppleNameIsCapturedOnceAndBounded() {
        var components = PersonNameComponents()
        components.givenName = "Jordan"
        components.familyName = "Bell"
        XCTAssertEqual(PlayerName.fromAppleComponents(components), "Jordan Bell")

        // Apple omits the name on every authorization after the first.
        XCTAssertNil(PlayerName.fromAppleComponents(nil))
        XCTAssertNil(PlayerName.fromAppleComponents(PersonNameComponents()))

        var overlong = PersonNameComponents()
        overlong.givenName = String(repeating: "a", count: 200)
        let formatted = PlayerName.fromAppleComponents(overlong)
        XCTAssertEqual(formatted?.count, PlayerName.maxLength)
    }
}
