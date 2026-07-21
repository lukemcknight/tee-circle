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
}
