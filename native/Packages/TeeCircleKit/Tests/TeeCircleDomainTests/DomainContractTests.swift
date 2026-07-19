import XCTest
import TeeCircleAPI
import TeeCircleDomain

final class DomainContractTests: XCTestCase {
    func testLeaderboardSnapshotFixtureDecodesAndRoundTrips() throws {
        let data = try Data(contentsOf: contractURL("native-v2-leaderboard-snapshot-v1.json"))
        let snapshot = try TeeCircleJSON.makeDecoder().decode(LeaderboardSnapshotV1.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.tripId, "trip-pinehurst-2026")
        XCTAssertEqual(snapshot.revision, 42)
        XCTAssertEqual(snapshot.currentRound?.throughHole, 12)
        XCTAssertEqual(snapshot.primaryBoard?.standings.first?.displayName, "Sean")
        XCTAssertEqual(snapshot.moment?.kind, .leadChange)

        let encoded = try TeeCircleJSON.makeEncoder().encode(snapshot)
        XCTAssertEqual(try TeeCircleJSON.makeDecoder().decode(LeaderboardSnapshotV1.self, from: encoded), snapshot)
    }

    func testSnapshotAcceptsCanonicalRoutineAndFinalMomentKinds() throws {
        for rawValue in ["score_update", "final_result"] {
            let data = Data("{\"kind\":\"\(rawValue)\",\"summary\":\"Update\"}".utf8)
            let moment = try JSONDecoder().decode(LeaderboardMomentV1.self, from: data)
            XCTAssertEqual(moment.kind.rawValue, rawValue)
        }
    }

    func testSkinsCarryRoundTripsOnBoard() throws {
        let data = Data(#"{"format":"skins","scoring":"net","standings":[],"skinsCarry":3}"#.utf8)
        let board = try JSONDecoder().decode(LeaderboardBoardV1.self, from: data)
        XCTAssertEqual(board.skinsCarry, 3)
        XCTAssertEqual(
            try JSONDecoder().decode(LeaderboardBoardV1.self, from: JSONEncoder().encode(board)),
            board
        )
    }

    func testSkinsHoleResultUsesWireCompatibleShape() throws {
        let won = SkinsHoleResult.won(hole: 7, winnerId: "seat-a", skins: 3)
        let wonObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(won)) as? [String: Any]
        )
        XCTAssertEqual(wonObject["hole"] as? Int, 7)
        XCTAssertEqual(wonObject["winnerId"] as? String, "seat-a")
        XCTAssertEqual(wonObject["skins"] as? Int, 3)

        let carriedData = Data(#"{"hole":8,"winnerId":null,"carried":2}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(SkinsHoleResult.self, from: carriedData),
            .carried(hole: 8, carried: 2)
        )
    }

    func testAPIEnvelopeRoundTripsPayload() throws {
        let payload = ScoreHoleCommandV1(
            roundId: "round-1",
            tripPlayerId: "seat-1",
            hole: 6,
            strokes: 4,
            expectedRevision: 12,
            idempotencyKey: "5D24EA89-0A9F-478B-8AE3-CA5B1249A105"
        )
        let envelope = APIEnvelope(requestId: "request-1", data: payload)
        let encoded = try JSONEncoder().encode(envelope)
        XCTAssertEqual(try JSONDecoder().decode(APIEnvelope<ScoreHoleCommandV1>.self, from: encoded), envelope)
    }

    func testErrorEnvelopePreservesConflictCurrentScoreDetails() throws {
        let data = Data(#"""
        {
          "schemaVersion": 1,
          "requestId": "request-conflict",
          "error": {
            "code": "score_conflict",
            "message": "The score changed.",
            "retryable": false,
            "currentRevision": 9,
            "details": {
              "currentScore": { "strokes": 4, "penalties": 1, "revision": 9 }
            }
          }
        }
        """#.utf8)

        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        guard case let .object(score)? = envelope.error.details?["currentScore"] else {
            return XCTFail("Missing current score details")
        }
        XCTAssertEqual(score["strokes"]?.intValue, 4)
        XCTAssertEqual(score["penalties"]?.intValue, 1)
        XCTAssertEqual(score["revision"]?.intValue, 9)
    }

    func testTripModelsRetainStableRosterSeatIdentity() throws {
        let seat = TripPlayer(
            id: "seat-1",
            tripId: "trip-1",
            claimedUserId: nil,
            displayName: "Maya",
            role: .player,
            rsvp: .pending,
            handicapSnapshot: 8.4,
            sortOrder: 2
        )
        let encoded = try JSONEncoder().encode(seat)
        let decoded = try JSONDecoder().decode(TripPlayer.self, from: encoded)
        XCTAssertEqual(decoded.id, "seat-1")
        XCTAssertNil(decoded.claimedUserId)
        XCTAssertEqual(decoded, seat)
    }

    private func contractURL(_ filename: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            root.deleteLastPathComponent()
        }
        return root.appendingPathComponent("contracts").appendingPathComponent(filename)
    }
}
