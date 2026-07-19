import XCTest
import TeeCircleDesign
import TeeCircleDomain

final class LeaderboardPresentationTests: XCTestCase {
    func testStablefordPresentationUsesTieAndProgressLabels() {
        let presentation = LeaderboardCardPresentation(snapshot: sampleSnapshot(), maxRows: 2)

        XCTAssertEqual(presentation.eyebrow, "LIVE LEADERBOARD")
        XCTAssertEqual(presentation.title, "Net Stableford")
        XCTAssertEqual(presentation.subtitle, "Pinehurst No. 2 · Through 12")
        XCTAssertEqual(presentation.rows.map(\.rankText), ["1", "T2"])
        XCTAssertEqual(presentation.rows.map(\.valueText), ["28 pts", "26 pts"])
        XCTAssertEqual(presentation.rows.last?.progressText, "12 holes")
        XCTAssertEqual(presentation.moment, "Sean took the lead through 12")
    }

    func testSkinsPresentationPluralizesAndHonorsLimit() {
        let board = LeaderboardBoardV1(
            format: .skins,
            scoring: .gross,
            standings: [
                .init(playerId: "a", displayName: "A", rank: 1, value: 1, tied: false, holesPlayed: 1),
                .init(playerId: "b", displayName: "B", rank: 2, value: 0, tied: false, holesPlayed: 1),
            ]
        )
        let snapshot = LeaderboardSnapshotV1(
            tripId: "trip",
            revision: 1,
            status: .live,
            primaryFormat: .skins,
            currentRound: nil,
            boards: [board],
            moment: nil,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let presentation = LeaderboardCardPresentation(snapshot: snapshot, maxRows: 1)

        XCTAssertEqual(presentation.title, "Gross Skins")
        XCTAssertEqual(presentation.rows.map(\.valueText), ["1 skin"])
        XCTAssertEqual(presentation.rows.first?.progressText, "1 hole")
    }

    func testCompletedEmptyPresentationHasFinalFallback() {
        let snapshot = LeaderboardSnapshotV1(
            tripId: "trip",
            revision: 9,
            status: .completed,
            primaryFormat: .stableford,
            currentRound: nil,
            boards: [],
            moment: nil,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let presentation = LeaderboardCardPresentation(snapshot: snapshot)
        XCTAssertEqual(presentation.eyebrow, "FINAL")
        XCTAssertEqual(presentation.subtitle, "Trip complete")
        XCTAssertTrue(presentation.isFinal)
        XCTAssertTrue(presentation.rows.isEmpty)
    }

    private func sampleSnapshot() -> LeaderboardSnapshotV1 {
        LeaderboardSnapshotV1(
            tripId: "trip",
            revision: 42,
            status: .live,
            primaryFormat: .stableford,
            currentRound: .init(publicId: "round", name: "Pinehurst No. 2", throughHole: 12),
            boards: [
                .init(
                    format: .stableford,
                    scoring: .net,
                    standings: [
                        .init(playerId: "sean", displayName: "Sean", rank: 1, value: 28, tied: false, holesPlayed: 12),
                        .init(playerId: "luke", displayName: "Luke", rank: 2, value: 26, tied: true, holesPlayed: 12),
                        .init(playerId: "maya", displayName: "Maya", rank: 2, value: 26, tied: true, holesPlayed: 11),
                    ]
                )
            ],
            moment: .init(kind: .leadChange, summary: "Sean took the lead through 12"),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
