import Foundation
import XCTest
import TeeCircleDomain
import TeeCircleScoring

final class ScoringFixtureTests: XCTestCase {
    func testSharedScoringFixtureMatchesSwiftEngine() throws {
        let fixture = try JSONDecoder().decode(
            ScoringFixture.self,
            from: Data(contentsOf: contractURL("native-v2-scoring-fixtures.json"))
        )

        XCTAssertEqual(fixture.schemaVersion, 1)
        for item in fixture.strokeAllocation {
            XCTAssertEqual(
                TeeCircleScoring.strokesReceived(
                    on: item.strokeIndex,
                    courseHandicap: item.courseHandicap,
                    holeCount: item.holeCount
                ),
                item.expected,
                "SI \(item.strokeIndex), handicap \(item.courseHandicap)"
            )
        }
        for item in fixture.stablefordPoints {
            XCTAssertEqual(
                TeeCircleScoring.stablefordPoints(netStrokes: item.netStrokes, par: item.par),
                item.expected
            )
        }
        for item in fixture.stablefordBoards {
            XCTAssertEqual(
                TeeCircleScoring.stableford(players: item.players, scoring: item.scoring),
                item.expected,
                item.name
            )
        }
        for item in fixture.skinsBoards {
            let result = TeeCircleScoring.skins(players: item.players, scoring: item.scoring)
            XCTAssertEqual(result.holes, item.expectedHoles, item.name)
            XCTAssertEqual(result.standings, item.expectedStandings, item.name)
        }
        for item in fixture.tripBoards {
            XCTAssertEqual(
                TeeCircleScoring.tripStandings(rounds: item.rounds, format: item.format, scoring: item.scoring),
                item.expected,
                item.name
            )
            if let expectedCarry = item.expectedCarry {
                XCTAssertEqual(
                    TeeCircleScoring.tripSkins(rounds: item.rounds, scoring: item.scoring).carry,
                    expectedCarry,
                    "\(item.name) carry"
                )
            }
        }
    }

    func testGrossModeLeavesStrokesUnchangedAndNilUnplayed() {
        let played = HoleScore(hole: 1, par: 4, strokeIndex: 5, strokes: 6, penalties: 1)
        let unplayed = HoleScore(hole: 1, par: 4, strokeIndex: 5, strokes: nil)
        XCTAssertEqual(TeeCircleScoring.netStrokes(for: played, courseHandicap: 9, scoring: .gross), 7)
        XCTAssertEqual(TeeCircleScoring.netStrokes(for: played, courseHandicap: 9, scoring: .net), 6)
        XCTAssertNil(TeeCircleScoring.netStrokes(for: unplayed, courseHandicap: 9, scoring: .net))
    }

    func testNineHoleBoardUsesNineHoleAllocation() {
        let player = PlayerRound(
            playerId: "nine-hole",
            courseHandicap: 10,
            holes: [HoleScore(hole: 1, par: 4, strokeIndex: 1, strokes: 5)]
        )
        XCTAssertEqual(
            TeeCircleScoring.stableford(players: [player], scoring: .net, holeCount: 9),
            [PlayerStanding(playerId: "nine-hole", value: 3)]
        )
    }

    func testEmptyAndDuplicateHoleInputsRemainLiveSafe() {
        XCTAssertEqual(TeeCircleScoring.skins(players: [], scoring: .gross), SkinsResult(holes: [], standings: []))

        let player = PlayerRound(
            playerId: "a",
            courseHandicap: 0,
            holes: [
                HoleScore(hole: 1, par: 4, strokeIndex: 1, strokes: 3),
                HoleScore(hole: 1, par: 4, strokeIndex: 1, strokes: 9),
            ]
        )
        XCTAssertEqual(
            TeeCircleScoring.skins(players: [player], scoring: .gross).holes,
            [.won(hole: 1, winnerId: "a", skins: 1)]
        )
    }

    private func contractURL(_ filename: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            root.deleteLastPathComponent()
        }
        return root.appendingPathComponent("contracts").appendingPathComponent(filename)
    }
}

private struct ScoringFixture: Decodable {
    let schemaVersion: Int
    let strokeAllocation: [StrokeAllocation]
    let stablefordPoints: [StablefordPoint]
    let stablefordBoards: [StablefordBoard]
    let skinsBoards: [SkinsBoard]
    let tripBoards: [TripBoard]
}

private struct StrokeAllocation: Decodable {
    let holeCount: Int
    let strokeIndex: Int
    let courseHandicap: Int
    let expected: Int
}

private struct StablefordPoint: Decodable {
    let netStrokes: Int?
    let par: Int
    let expected: Int
}

private struct StablefordBoard: Decodable {
    let name: String
    let scoring: ScoringMode
    let players: [PlayerRound]
    let expected: [PlayerStanding]
}

private struct SkinsBoard: Decodable {
    let name: String
    let scoring: ScoringMode
    let players: [PlayerRound]
    let expectedHoles: [SkinsHoleResult]
    let expectedStandings: [PlayerStanding]
}

private struct TripBoard: Decodable {
    let name: String
    let format: TournamentFormat
    let scoring: ScoringMode
    let rounds: [[PlayerRound]]
    let expected: [PlayerStanding]
    let expectedCarry: Int?
}
