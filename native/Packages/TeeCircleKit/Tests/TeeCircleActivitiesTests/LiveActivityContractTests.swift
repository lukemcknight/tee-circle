import XCTest
import TeeCircleActivities
import TeeCircleDomain

final class LiveActivityContractTests: XCTestCase {
    func testMapsAuthoritativeSnapshotForLeaderAndViewer() {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = LeaderboardSnapshotV1(
            tripId: "trip-1",
            revision: 42,
            status: .live,
            primaryFormat: .stableford,
            currentRound: .init(publicId: "round-1", name: "No. 2", throughHole: 12),
            boards: [
                .init(
                    format: .stableford,
                    scoring: .net,
                    standings: [
                        .init(playerId: "sean", displayName: "Sean", rank: 1, value: 28, tied: false, holesPlayed: 12),
                        .init(playerId: "luke", displayName: "Luke", rank: 2, value: 26, tied: false, holesPlayed: 12),
                    ]
                ),
                .init(
                    format: .skins,
                    scoring: .net,
                    standings: [],
                    skinsCarry: 3
                )
            ],
            moment: nil,
            generatedAt: generatedAt
        )

        let state = TeeCircleActivityMapper.contentState(
            from: snapshot,
            viewerPlayerId: "luke"
        )

        XCTAssertEqual(state.revision, 42)
        XCTAssertEqual(state.roundName, "No. 2")
        XCTAssertEqual(state.throughHole, 12)
        XCTAssertEqual(state.leaderName, "Sean")
        XCTAssertEqual(state.leaderValue, 28)
        XCTAssertEqual(state.viewerRank, 2)
        XCTAssertEqual(state.viewerValue, 26)
        XCTAssertEqual(state.skinsCarry, 3)
        XCTAssertEqual(state.updatedAt, generatedAt)
        XCTAssertTrue(state.fitsActivityKitPushLimit)
        XCTAssertLessThan(state.encodedSize, 1_024)
    }

    func testEmptyBoardProducesSafeOptionalValues() {
        let snapshot = LeaderboardSnapshotV1(
            tripId: "trip-1",
            revision: 0,
            status: .ready,
            primaryFormat: .skins,
            currentRound: nil,
            boards: [],
            moment: nil,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let state = TeeCircleActivityMapper.contentState(from: snapshot, viewerPlayerId: "missing")

        XCTAssertNil(state.leaderName)
        XCTAssertNil(state.viewerRank)
        XCTAssertEqual(state.throughHole, 0)
    }

    func testAttributesRoundTripWithoutSecrets() throws {
        let attributes = TeeCircleLiveActivityAttributes(
            tripId: "public-trip-id",
            tripName: "Pinehurst Weekend",
            viewerPlayerId: "seat-1"
        )
        let data = try JSONEncoder().encode(attributes)
        XCTAssertEqual(try JSONDecoder().decode(TeeCircleLiveActivityAttributes.self, from: data), attributes)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("token"))
    }
}
