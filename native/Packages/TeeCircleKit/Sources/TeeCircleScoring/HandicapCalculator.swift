import Foundation

/// TeeCircle's existing in-app handicap math. This is intentionally not represented as a WHS-certified index.
public enum HandicapCalculator {
    public static func differential(grossScore: Int, courseRating: Double, slopeRating: Int) -> Double {
        roundToTenth((Double(grossScore) - courseRating) * 113 / Double(slopeRating))
    }

    public static func index(from differentials: [Double]) -> Double? {
        let values = differentials.filter(\.isFinite).sorted()
        guard !values.isEmpty else { return nil }
        let countingScores = min(values.count, 8)
        let average = values.prefix(countingScores).reduce(0, +) / Double(countingScores)
        return roundToTenth(average)
    }

    public static func courseHandicap(
        handicapIndex: Double,
        slopeRating: Int,
        courseRating: Double,
        par: Int
    ) -> Int {
        let value = handicapIndex * Double(slopeRating) / 113 + (courseRating - Double(par))
        precondition(value.isFinite, "Course handicap inputs must be finite")
        // JavaScript Math.round chooses +infinity for exact negative halves.
        return Int((value + 0.5).rounded(.down))
    }

    private static func roundToTenth(_ value: Double) -> Double {
        ((value * 10) + 0.5).rounded(.down) / 10
    }
}
