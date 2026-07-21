import XCTest
@testable import TeeCircle

@MainActor
final class CourseSearchControllerTests: XCTestCase {
    func testMissingKeyDisablesSearchAndNeverSuggests() {
        let controller = CourseSearchController(apiKey: "   ")

        XCTAssertFalse(controller.isEnabled)
        controller.update(query: "Bethpage Black")
        XCTAssertTrue(controller.suggestions.isEmpty)
    }

    func testShortQueryClearsSuggestionsWithoutSearching() {
        let controller = CourseSearchController(apiKey: "fixture-key")

        XCTAssertTrue(controller.isEnabled)
        controller.update(query: "Be")
        XCTAssertTrue(controller.suggestions.isEmpty)
    }

    /// Mirrors how CreateRoundView/CreateTripView build their controller: under
    /// mock/UI-testing mode the effective key must be empty even when a real
    /// key is configured, so fixture runs never fire live, billed Places calls.
    func testEffectiveKeyIsEmptyUnderMockDataRegardlessOfConfiguredKey() {
        XCTAssertEqual(
            CourseSearchController.effectiveKey(configuredKey: "real-fixture-key", useMockData: true),
            ""
        )
        XCTAssertEqual(
            CourseSearchController.effectiveKey(configuredKey: "real-fixture-key", useMockData: false),
            "real-fixture-key"
        )

        let controller = CourseSearchController(
            apiKey: CourseSearchController.effectiveKey(configuredKey: "real-fixture-key", useMockData: true)
        )
        XCTAssertFalse(controller.isEnabled)
    }
}
