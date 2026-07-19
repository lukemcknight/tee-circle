import XCTest
import TeeCircleDomain
@testable import TeeCircle

final class NativeServiceContractTests: XCTestCase {
    func testMessagesCredentialWireShapeContainsOnlyDeviceScopedBearerFields() throws {
        let credential = ExtensionSessionCredentialV1(
            schemaVersion: 1,
            tripId: "trip-id",
            sessionToken: String(repeating: "a", count: 48),
            deviceId: "device-id",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(credential)) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            Set(["schemaVersion", "tripId", "sessionToken", "deviceId", "expiresAt"])
        )
        XCTAssertNil(object["sessionId"])
        XCTAssertNil(object["userId"])
    }

    func testMessagesCacheCarriesActualNineHoleRoundCount() throws {
        let trip = Trip(
            id: "trip-id",
            publicId: "public-id",
            ownerId: "owner-id",
            name: "Nine Hole Cup",
            startDate: "2026-07-13",
            endDate: "2026-07-13",
            timeZone: "America/New_York",
            lifecycle: .live,
            enabledFormats: [.stableford],
            primaryFormat: .stableford,
            scoringMode: .gross,
            scoreRevision: 1,
            isEntitled: true
        )
        let snapshot = LeaderboardSnapshotV1(
            tripId: "public-id",
            revision: 1,
            status: .live,
            primaryFormat: .stableford,
            currentRound: .init(publicId: "round-public", name: "Short Course", throughHole: 3),
            boards: [],
            moment: nil,
            generatedAt: .now
        )
        let cached = CachedMessagesTripV1(
            schemaVersion: 1,
            trip: trip,
            inviteToken: String(repeating: "b", count: 64),
            claimedPlayer: nil,
            scoringRoundId: "round-id",
            scoringRoundHoleCount: 9,
            snapshot: snapshot,
            cachedAt: .now
        )

        XCTAssertEqual(cached.scoringRoundHoleCount, 9)
    }

    func testRepositoryCatalogUsesOnlyVersionedCommands() {
        XCTAssertTrue(TeeCircleEndpointCatalog.createTrip.hasSuffix("/create_trip_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.acceptTripInvite.hasSuffix("/accept_trip_invite_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.updateCourseCard.hasSuffix("/update_course_card_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.updateTripRound.hasSuffix("/update_trip_round_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.deleteTripRound.hasSuffix("/delete_trip_round_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.deleteTripPlayer.hasSuffix("/delete_trip_player_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.startTrip.hasSuffix("/start_trip_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.advanceTripRound.hasSuffix("/advance_trip_round_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.listInvites.hasSuffix("/list_trip_invites_v1"))
        XCTAssertTrue(TeeCircleEndpointCatalog.rotateInvite.hasSuffix("/rotate_trip_invite_v1"))
        XCTAssertTrue(
            TeeCircleEndpointCatalog.cancelPurchaseIntent.hasSuffix(
                "/cancel_trip_purchase_intent_v1"
            )
        )
        XCTAssertEqual(TeeCircleEndpointCatalog.recordHoleScore, "/functions/v1/record-score-v1")
        XCTAssertEqual(TeeCircleEndpointCatalog.claimPurchase, "/functions/v1/claim-trip-purchase-v1")
        XCTAssertEqual(TeeCircleEndpointCatalog.previewInvite, "/functions/v1/preview-trip-v1")
        XCTAssertEqual(TeeCircleEndpointCatalog.unsupportedCapabilities, [.deleteAccount])
    }

    func testInviteMetadataCannotCarryBearerSecrets() throws {
        let metadata = TripInviteMetadataV1(
            inviteId: "invite-id",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_086_400),
            revokedAt: Date(timeIntervalSince1970: 1_800_000_100),
            useCount: 0,
            maxUses: 12,
            status: .revoked
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            Set(["inviteId", "createdAt", "expiresAt", "revokedAt", "useCount", "maxUses", "status"])
        )
        XCTAssertNil(object["inviteToken"])
        XCTAssertNil(object["tokenHash"])
        XCTAssertNil(object["url"])
    }

    func testPurchaseIntentCancellationMatchesPostgRESTContract() throws {
        let arguments = try encodedJSONObject(
            CancelPurchaseIntentArguments(pPurchaseIntentId: "intent-id")
        )
        XCTAssertEqual(Set(arguments.keys), ["p_purchase_intent_id"])
        XCTAssertEqual(arguments["p_purchase_intent_id"] as? String, "intent-id")

        let result = try JSONDecoder().decode(
            PurchaseIntentCancellationResultV1.self,
            from: Data("""
            {
              "purchaseIntentId": "intent-id",
              "tripId": "trip-id",
              "status": "cancelled"
            }
            """.utf8)
        )
        XCTAssertEqual(result.purchaseIntentId, "intent-id")
        XCTAssertEqual(result.tripId, "trip-id")
        XCTAssertEqual(result.status, .cancelled)
    }

    func testPendingPurchaseClaimsAreNamespacedBySupabaseUser() {
        let first = TripPurchaseSecureAccount.claim(for: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
        let second = TripPurchaseSecureAccount.claim(for: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSuffix("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    }

    @MainActor
    func testUnconsumedPurchaseCancellationCallsRepository() async throws {
        let repository = PurchaseRepositorySpy()
        let service = TripPurchaseService(
            repository: repository,
            apiKey: "fixture-key",
            productID: "com.teecircle.app.trip_unlock_2999"
        )

        let result = try await service.cancelUnconsumedIntent("intent-id")
        let cancelledIDs = await repository.cancelledIntentIDs()

        XCTAssertEqual(result.status, .cancelled)
        XCTAssertEqual(cancelledIDs, ["intent-id"])
    }

    func testAtomicLifecycleCommandArgumentsMatchPostgRESTNames() throws {
        let start = try encodedJSONObject(
            StartTripArguments(pTripId: "trip-id", pExpectedScoreRevision: 8)
        )
        XCTAssertEqual(Set(start.keys), Set(["p_trip_id", "p_expected_score_revision"]))
        XCTAssertEqual(start["p_expected_score_revision"] as? Int, 8)

        let advance = try encodedJSONObject(
            AdvanceTripRoundArguments(
                pTripId: "trip-id",
                pCurrentRoundId: "round-id",
                pExpectedScoreRevision: 9,
                pAllowIncomplete: false
            )
        )
        XCTAssertEqual(
            Set(advance.keys),
            Set(["p_trip_id", "p_current_round_id", "p_expected_score_revision", "p_allow_incomplete"])
        )
        XCTAssertEqual(advance["p_allow_incomplete"] as? Bool, false)
    }

    func testAtomicAdvanceResponseDecodesFinalRound() throws {
        let result = try JSONDecoder().decode(
            AdvanceTripRoundResultV1.self,
            from: Data("""
            {
              "tripId":"trip-id",
              "tripStatus":"completed",
              "currentRoundId":"round-id",
              "currentRoundStatus":"completed",
              "nextRoundId":null,
              "nextRoundStatus":null,
              "scoreRevision":10
            }
            """.utf8)
        )
        XCTAssertEqual(result.tripStatus, .completed)
        XCTAssertNil(result.nextRoundId)
        XCTAssertEqual(result.scoreRevision, 10)
    }

    func testAuthenticatedScoreUsesEdgeCommandShape() throws {
        let object = try encodedJSONObject(
            AuthenticatedScoreArguments(
                schemaVersion: 1,
                roundId: "round-id",
                tripPlayerId: "seat-id",
                holeNumber: 7,
                strokes: 4,
                penalties: 1,
                idempotencyKey: "command-id",
                expectedScoreRevision: 42
            )
        )
        XCTAssertEqual(
            Set(object.keys),
            Set([
                "schemaVersion", "roundId", "tripPlayerId", "holeNumber",
                "strokes", "penalties", "idempotencyKey", "expectedScoreRevision",
            ])
        )
        XCTAssertEqual(object["strokes"] as? Int, 4)
        XCTAssertEqual(object["penalties"] as? Int, 1)
        XCTAssertEqual(object["expectedScoreRevision"] as? Int, 42)
    }

    func testAuthenticatedScoreResponseCarriesCanonicalSnapshot() throws {
        let json = """
        {
          "tripId": "trip-id",
          "scoreId": "score-id",
          "acceptedRevision": 41,
          "revision": 42,
          "idempotentReplay": false,
          "score": {
            "roundId": "round-id",
            "tripPlayerId": "seat-id",
            "holeNumber": 7,
            "strokes": 4,
            "penalties": 1,
            "grossTotal": 5
          },
          "snapshot": {
            "schemaVersion": 1,
            "tripId": "public-trip-id",
            "revision": 42,
            "status": "live",
            "primaryFormat": "stableford",
            "currentRound": null,
            "boards": [],
            "moment": { "kind": "score_update", "summary": "Standings updated" },
            "generatedAt": "2026-07-13T18:42:10Z"
          },
          "activityDispatch": { "status": "disabled", "processed": 0 }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(RecordHoleScoreResultV1.self, from: Data(json.utf8))

        XCTAssertEqual(result.score.grossTotal, 5)
        XCTAssertEqual(result.revision, result.snapshot.revision)
        XCTAssertEqual(result.snapshot.moment?.kind, .scoreUpdate)
    }

    func testEditCommandArgumentsMatchPostgRESTRPCNames() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let cardArguments = UpdateCourseCardArguments(
            pCourseCardId: "card-id",
            pInput: .init(
                name: "Home Card",
                courseName: "Pinehurst No. 2",
                holes: [.init(holeNumber: 1, par: 4, strokeIndex: 1, yards: 420)]
            ),
            pExpectedUpdatedAt: timestamp
        )
        let cardObject = try encodedJSONObject(cardArguments)

        XCTAssertEqual(
            Set(cardObject.keys),
            Set(["p_course_card_id", "p_input", "p_expected_updated_at"])
        )
        XCTAssertEqual(cardObject["p_course_card_id"] as? String, "card-id")
        let cardInput = try XCTUnwrap(cardObject["p_input"] as? [String: Any])
        XCTAssertEqual(cardInput["courseName"] as? String, "Pinehurst No. 2")

        let roundArguments = UpdateTripRoundArguments(
            pRoundId: "round-id",
            pInput: .init(courseCardId: "card-id", walkRide: .clear, tripOrder: 2),
            pExpectedNativeUpdatedAt: timestamp
        )
        let roundObject = try encodedJSONObject(roundArguments)

        XCTAssertEqual(
            Set(roundObject.keys),
            Set(["p_round_id", "p_input", "p_expected_native_updated_at"])
        )
        let roundInput = try XCTUnwrap(roundObject["p_input"] as? [String: Any])
        XCTAssertEqual(roundInput["courseCardId"] as? String, "card-id")
        XCTAssertEqual(roundInput["tripOrder"] as? Int, 2)
        XCTAssertNil(roundInput["teeTime"])
        XCTAssertTrue(roundInput["walkRide"] is NSNull)
    }

    func testDeleteCommandArgumentsCarryIdempotencyAndConflictTokens() throws {
        let roundObject = try encodedJSONObject(
            DeleteTripRoundArguments(
                pRoundId: "round-id",
                pIdempotencyKey: "round-command-id",
                pExpectedNativeUpdatedAt: nil
            )
        )
        XCTAssertEqual(roundObject["p_round_id"] as? String, "round-id")
        XCTAssertEqual(roundObject["p_idempotency_key"] as? String, "round-command-id")
        XCTAssertTrue(roundObject["p_expected_native_updated_at"] is NSNull)

        let playerObject = try encodedJSONObject(
            DeleteTripPlayerArguments(
                pTripPlayerId: "seat-id",
                pIdempotencyKey: "player-command-id",
                pExpectedUpdatedAt: nil
            )
        )
        XCTAssertEqual(playerObject["p_trip_player_id"] as? String, "seat-id")
        XCTAssertEqual(playerObject["p_idempotency_key"] as? String, "player-command-id")
        XCTAssertTrue(playerObject["p_expected_updated_at"] is NSNull)
    }

    func testUpdatedCourseCardDecodesServerIDField() throws {
        let json = """
        {
          "id": "card-id",
          "name": "Home Card",
          "courseName": "Pinehurst No. 2",
          "holeCount": 9,
          "createdAt": "2026-07-13T12:00:00Z",
          "updatedAt": "2026-07-13T12:30:00Z",
          "holes": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(UpdateCourseCardResultV1.self, from: Data(json.utf8))

        XCTAssertEqual(result.courseCardId, "card-id")
        XCTAssertEqual(result.holeCount, 9)
    }

    func testAuthSessionDoesNotIncludeProviderTokens() {
        let session = NativeAuthSession(
            userID: "user-id",
            email: "player@example.com",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(NativeAuthState.signedIn(session), .signedIn(session))
        XCTAssertFalse(Mirror(reflecting: session).children.contains { $0.label == "accessToken" })
    }

    func testOfflineScoreQueuePreservesUserAndOriginalRevision() async {
        let suite = "teecircle.pending-score-test.\(UUID().uuidString)"
        let queue = PendingScoreQueue(appGroupIdentifier: suite)
        await queue.removeAll()
        let queued = QueuedHoleScore(
            tripID: "trip-id",
            userID: "user-a",
            roundID: "round-id",
            playerID: "seat-id",
            holeNumber: 4,
            strokes: 5,
            penalties: 1,
            expectedRevision: 17,
            idempotencyKey: UUID().uuidString.lowercased(),
            queuedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        await queue.enqueue(queued)
        let restored = await queue.all()
        XCTAssertEqual(restored, [queued])
        XCTAssertEqual(restored.first?.userID, "user-a")
        XCTAssertEqual(restored.first?.expectedRevision, 17)
        await queue.removeAll()
    }

    private func encodedJSONObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any]
        )
    }
}

private actor PurchaseRepositorySpy: TripPurchaseRepositoryProtocol {
    private var cancellations: [String] = []

    func createPurchaseIntent(
        tripID: String,
        idempotencyKey: String
    ) async throws -> PurchaseIntentV1 {
        PurchaseIntentV1(
            purchaseIntentId: "intent-id",
            tripId: tripID,
            productId: "com.teecircle.app.trip_unlock_2999",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func cancelPurchaseIntent(
        intentID: String
    ) async throws -> PurchaseIntentCancellationResultV1 {
        cancellations.append(intentID)
        return PurchaseIntentCancellationResultV1(
            purchaseIntentId: intentID,
            tripId: "trip-id",
            status: .cancelled
        )
    }

    func claimPurchase(
        intentID: String,
        transactionID: String,
        productID: String
    ) async throws -> PurchaseClaimResultV1 {
        PurchaseClaimResultV1(tripId: "trip-id", unlocked: true, idempotentReplay: false)
    }

    func cancelledIntentIDs() -> [String] {
        cancellations
    }
}
