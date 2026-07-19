import XCTest
import TeeCircleDomain
@testable import TeeCircle

@MainActor
final class TeeCircleStoreTests: XCTestCase {
    private func makeStore() -> TeeCircleStore {
        TeeCircleStore(
            configuration: AppConfiguration(
                supabaseURL: URL(string: "https://example.supabase.co"),
                supabasePublishableKey: "fixture-key",
                webBaseURL: URL(string: "https://teecircle.vercel.app")!,
                keychainAccessGroup: nil,
                postHogHost: nil,
                postHogToken: "",
                googleIOSClientID: "",
                googleServerClientID: "",
                revenueCatPublicKey: "",
                revenueCatTripProductID: "com.teecircle.app.trip_unlock_2999",
                useMockData: true
            )
        )
    }

    func testFixtureStartsSignedInWithLiveTripAndLegacyRound() {
        let store = makeStore()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.trips.first?.trip.name, "Pinehurst Cup")
        XCTAssertEqual(store.trips.first?.latestSnapshot?.revision, 24)
        XCTAssertEqual(store.legacyRounds.count, 1)
    }

    func testCreateTripCopiesCourseCardAndRosterSeats() throws {
        let store = makeStore()
        var draft = CreateTripDraft()
        draft.name = "Two Course Cup"
        draft.playerNames = ["Luke", "Sean"]
        draft.playerHandicaps = [8.2, 12.4]
        draft.rounds = [
            .init(name: "Opening", courseName: "No. 2", holeCount: 9),
            .init(name: "Final", courseName: "No. 4", holeCount: 18),
        ]

        let id = store.createTrip(from: draft)
        let created = try XCTUnwrap(store.trip(id: id))

        XCTAssertEqual(created.rounds.count, 2)
        XCTAssertEqual(created.rounds[0].holes.count, 9)
        XCTAssertEqual(created.players.count, 2)
        XCTAssertEqual(created.players.first?.claimedUserId, store.currentUserID)
        XCTAssertNotEqual(created.rounds[0].holes[0].number, 0)
    }

    func testSingleRoundDraftKeepsTheOriginalMVPDefaults() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let teeTime = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 8, minute: 30))
        )

        let draft = CreateTripDraft.singleRound(
            courseName: "  Bethpage Black  ",
            teeTime: teeTime,
            holeCount: 9,
            walkRide: "walk",
            playerNames: ["Luke", "  Sean  ", ""],
            calendar: calendar
        )

        XCTAssertEqual(draft.name, "Bethpage Black")
        XCTAssertEqual(draft.startDate, calendar.startOfDay(for: teeTime))
        XCTAssertEqual(draft.endDate, draft.startDate)
        XCTAssertEqual(draft.playerNames, ["Luke", "Sean"])
        XCTAssertEqual(draft.playerHandicaps.count, 2)
        XCTAssertEqual(draft.scoringMode, .gross)
        XCTAssertEqual(draft.rounds.count, 1)
        XCTAssertEqual(draft.rounds[0].courseName, "Bethpage Black")
        XCTAssertEqual(draft.rounds[0].scheduledAt, teeTime)
        XCTAssertEqual(draft.rounds[0].holeCount, 9)
        XCTAssertEqual(draft.rounds[0].holes.count, 9)
        XCTAssertEqual(draft.rounds[0].walkRide, "walk")
    }

    func testSingleRoundDraftCreatesAReadyNativeExperience() throws {
        let store = makeStore()
        let draft = CreateTripDraft.singleRound(
            courseName: "Pine Needles",
            teeTime: .now,
            holeCount: 18,
            walkRide: "ride",
            playerNames: ["Luke"]
        )

        let id = store.createTrip(from: draft)
        let created = try XCTUnwrap(store.trip(id: id))

        XCTAssertEqual(created.trip.name, "Pine Needles")
        XCTAssertEqual(created.trip.lifecycle, .ready)
        XCTAssertEqual(created.players.count, 1)
        XCTAssertEqual(created.rounds.count, 1)
        XCTAssertEqual(created.rounds[0].holes.count, 18)
    }

    func testLegacyConversionNeverMutatesLegacySource() throws {
        let store = makeStore()
        let original = try XCTUnwrap(store.legacyRounds.first)

        let newID = try XCTUnwrap(store.convertLegacyRound(original.id))
        let converted = try XCTUnwrap(store.trip(id: newID))

        XCTAssertEqual(store.legacyRounds.first, original)
        XCTAssertEqual(converted.rounds.count, 1)
        XCTAssertEqual(converted.rounds[0].courseName, original.courseName)
        XCTAssertEqual(converted.rounds[0].holes.count, original.holes)
    }

    func testScoringAdvancesRevisionAndSnapshot() throws {
        let store = makeStore()
        let trip = try XCTUnwrap(store.trips.first)
        let round = try XCTUnwrap(trip.rounds.first)
        let player = try XCTUnwrap(trip.players.first)
        let before = trip.trip.scoreRevision

        store.recordScore(tripID: trip.id, roundID: round.id, playerID: player.id, hole: 7, strokes: 4)

        let updated = try XCTUnwrap(store.trip(id: trip.id))
        XCTAssertEqual(updated.trip.scoreRevision, before + 1)
        XCTAssertEqual(updated.latestSnapshot?.revision, before + 1)
        XCTAssertEqual(
            updated.scores[HoleScoreKey(roundID: round.id, playerID: player.id, hole: 7)],
            LocalHoleScore(strokes: 4, penalties: 0)
        )
    }

    func testPenaltyStrokesRemainSeparateAndCountTowardGross() throws {
        let store = makeStore()
        let trip = try XCTUnwrap(store.trips.first)
        let round = try XCTUnwrap(trip.rounds.first)
        let player = try XCTUnwrap(trip.players.first)

        store.recordScore(
            tripID: trip.id,
            roundID: round.id,
            playerID: player.id,
            hole: 8,
            strokes: 4,
            penalties: 2
        )

        let score = try XCTUnwrap(
            store.trip(id: trip.id)?.scores[
                HoleScoreKey(roundID: round.id, playerID: player.id, hole: 8)
            ]
        )
        XCTAssertEqual(score.strokes, 4)
        XCTAssertEqual(score.penalties, 2)
        XCTAssertEqual(score.grossStrokes, 6)
    }

    func testOfflinePreviewAggregatesCompletedAndLiveRounds() throws {
        let store = makeStore()
        let trip = try XCTUnwrap(store.trips.first)
        let player = try XCTUnwrap(trip.players.first)

        store.completeCurrentRound(tripID: trip.id)
        let nextRound = try XCTUnwrap(
            store.trip(id: trip.id)?.rounds.first(where: { $0.lifecycle == .live })
        )
        store.recordScore(
            tripID: trip.id,
            roundID: nextRound.id,
            playerID: player.id,
            hole: 1,
            strokes: 4,
            penalties: 1
        )

        let snapshot = try XCTUnwrap(store.trip(id: trip.id)?.latestSnapshot)
        let stableford = try XCTUnwrap(snapshot.boards.first(where: { $0.format == .stableford }))
        let standing = try XCTUnwrap(stableford.standings.first(where: { $0.playerId == player.id }))
        XCTAssertEqual(standing.holesPlayed, 7)
        XCTAssertEqual(snapshot.currentRound?.publicId, nextRound.publicId)
        XCTAssertNotNil(snapshot.boards.first(where: { $0.format == .skins })?.skinsCarry)
        XCTAssertEqual(snapshot.moment?.kind, .scoreUpdate)
    }

    func testTripCannotStartBeforeServerEntitlementFixtureIsGranted() {
        let store = makeStore()
        var draft = CreateTripDraft()
        draft.name = "Locked Trip"
        draft.playerNames = ["Luke", "Sean"]
        draft.playerHandicaps = [10, 10]
        draft.rounds = [.init(courseName: "Pine Needles")]
        let id = store.createTrip(from: draft)

        store.startTournament(id)
        XCTAssertEqual(store.trip(id: id)?.trip.lifecycle, .ready)

        store.unlockTrip(id)
        store.startTournament(id)
        XCTAssertEqual(store.trip(id: id)?.trip.lifecycle, .live)
    }

    func testShareURLUsesCurrentCanonicalHostAndOpaqueToken() {
        let store = makeStore()
        let trip = try! XCTUnwrap(store.trips.first)
        let url = try! XCTUnwrap(store.shareURL(for: trip.id))

        XCTAssertEqual(url.host, "teecircle.vercel.app")
        XCTAssertEqual(url.pathComponents.dropFirst().first, "t")
        XCTAssertFalse(url.absoluteString.contains(trip.trip.id))
    }

    func testOnlyExactCompletedSnapshotCanEndLiveActivity() throws {
        let store = makeStore()
        var experience = try XCTUnwrap(store.trips.first)
        experience.trip = experience.trip.replacing(lifecycle: .completed, scoreRevision: 25)
        let original = try XCTUnwrap(experience.latestSnapshot)

        experience.latestSnapshot = snapshot(
            basedOn: original,
            revision: 24,
            status: .completed
        )
        XCTAssertNil(experience.canonicalTerminalSnapshot)

        experience.latestSnapshot = snapshot(
            basedOn: original,
            revision: 25,
            status: .live
        )
        XCTAssertNil(experience.canonicalTerminalSnapshot)

        experience.latestSnapshot = snapshot(
            basedOn: original,
            revision: 25,
            status: .completed
        )
        XCTAssertEqual(experience.canonicalTerminalSnapshot?.revision, 25)

        experience.trip = experience.trip.replacing(lifecycle: .archived)
        experience.latestSnapshot = snapshot(
            basedOn: original,
            revision: 25,
            status: .archived
        )
        XCTAssertEqual(experience.canonicalTerminalSnapshot?.status, .archived)
    }

    func testCaptainCanAssignDesignatedScorerInFixture() async throws {
        let store = makeStore()
        let experience = try XCTUnwrap(store.trips.first)
        let player = try XCTUnwrap(experience.players.first(where: { $0.role == .player }))

        await store.setTripPlayerRoleProduction(
            tripID: experience.id,
            playerID: player.id,
            role: .scorer
        )

        XCTAssertEqual(store.trip(id: experience.id)?.players.first(where: { $0.id == player.id })?.role, .scorer)
    }

    func testCompletedTieSummaryDoesNotDeclareSoleWinner() throws {
        let store = makeStore()
        var experience = try XCTUnwrap(store.trips.first)
        experience.trip = experience.trip.replacing(lifecycle: .completed, scoreRevision: 25)
        experience.rounds[0] = experience.rounds[0].replacing(lifecycle: .completed)
        experience.scores = [:]

        let result = store.makeSnapshot(for: experience)
        let leader = try XCTUnwrap(result.primaryBoard?.standings.first)

        XCTAssertTrue(leader.tied)
        XCTAssertEqual(result.moment?.kind, .finalResult)
        XCTAssertEqual(result.moment?.summary, "The final standings are tied at the top")
        XCTAssertFalse(result.moment?.summary.contains("finishes on top") == true)
    }

    private func snapshot(
        basedOn source: LeaderboardSnapshotV1,
        revision: Int,
        status: TripLifecycle
    ) -> LeaderboardSnapshotV1 {
        LeaderboardSnapshotV1(
            tripId: source.tripId,
            revision: revision,
            status: status,
            primaryFormat: source.primaryFormat,
            currentRound: source.currentRound,
            boards: source.boards,
            moment: source.moment,
            generatedAt: source.generatedAt
        )
    }
}
