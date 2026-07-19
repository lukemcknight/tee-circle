import XCTest
import TeeCircleScoring

final class HandicapCalculatorTests: XCTestCase {
    func testDifferentialRoundsToOneDecimal() {
        XCTAssertEqual(
            HandicapCalculator.differential(grossScore: 85, courseRating: 72.2, slopeRating: 128),
            11.3
        )
        XCTAssertEqual(
            HandicapCalculator.differential(grossScore: 70, courseRating: 72.5, slopeRating: 125),
            -2.3
        )
    }

    func testIndexUsesLowestEightFiniteValues() {
        let values = [12.0, 4.0, 10.0, 8.0, .nan, 2.0, 6.0, 14.0, 16.0, 18.0]
        XCTAssertEqual(HandicapCalculator.index(from: values), 9.0)
        XCTAssertNil(HandicapCalculator.index(from: [.nan, .infinity]))
        XCTAssertNil(HandicapCalculator.index(from: []))
    }

    func testCourseHandicapMatchesExistingFormula() {
        XCTAssertEqual(
            HandicapCalculator.courseHandicap(
                handicapIndex: 10.4,
                slopeRating: 125,
                courseRating: 72.1,
                par: 72
            ),
            12
        )
    }

    func testNegativeHalfUsesJavaScriptMathRoundSemantics() {
        XCTAssertEqual(
            HandicapCalculator.courseHandicap(
                handicapIndex: -0.5,
                slopeRating: 113,
                courseRating: 72,
                par: 72
            ),
            0
        )
    }
}
