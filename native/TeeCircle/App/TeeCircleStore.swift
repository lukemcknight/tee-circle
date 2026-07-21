import Combine
import Foundation
import TeeCircleDomain
import TeeCircleScoring

@MainActor
final class TeeCircleStore: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var selectedTab: AppTab = .rounds
    @Published var golfersPath: [GolferSummary] = []
    @Published var isAuthenticated: Bool
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var trips: [LocalTripExperience]
    @Published var legacyRounds: [LegacyRoundSummary]
    @Published var courseCards: [CourseCard]
    @Published var currentDisplayName = "Player"
    @Published var currentUsername: String?
    /// True once the server has confirmed this account has no name or handle yet.
    /// Nil means the profile has not been read, so the gate stays closed rather
    /// than flashing setup at someone who already has one.
    @Published var needsProfileSetup: Bool?
    @Published var isRestoringSession = false
    @Published var pendingScoreKeys: Set<HoleScoreKey> = []
    @Published var pendingInvite: PendingInviteSelection?
    @Published var inviteMetadataByTrip: [String: [TripInviteMetadataV1]] = [:]

    let configuration: AppConfiguration
    let production: TeeCircleProductionServices?
    var inviteCredentials: [String: TripInviteCredentialV1] = [:]
    var pendingDeepLinkToken: String?
    var pendingInternalTripID: String?
    /// Held between the Apple authorization callback and the profile read that
    /// follows it. Apple only ever supplies this once per account.
    var pendingAppleFullName: String?

    var currentUserID: String {
        if configuration.useMockData,
           ProcessInfo.processInfo.arguments.contains("-ui-invitee") {
            return "fixture-invitee"
        }
        return production?.auth.currentUserID ?? "demo-user"
    }

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        self.isAuthenticated = configuration.useMockData
        self.production = TeeCircleProductionServices(configuration: configuration)
        let seed = Self.seedData()
        self.trips = configuration.useMockData ? seed.trips : []
        self.legacyRounds = configuration.useMockData ? seed.legacyRounds : []
        self.courseCards = configuration.useMockData ? Self.seedCourseCards() : []
        // Fixture flag for the profile setup gate: an account that authenticated
        // but has no name or handle yet.
        let fixtureNeedsProfile = configuration.useMockData
            && ProcessInfo.processInfo.arguments.contains("-ui-needs-profile")
        self.currentDisplayName = configuration.useMockData && !fixtureNeedsProfile ? "Luke" : "Player"
        self.currentUsername = configuration.useMockData && !fixtureNeedsProfile ? "luke" : nil
        self.needsProfileSetup = configuration.useMockData ? fixtureNeedsProfile : nil
    }

    func start() async {
        guard !configuration.useMockData else { return }
        await restoreProductionSession()
    }

    func enterPreview() {
        isAuthenticated = true
        if trips.isEmpty {
            let seed = Self.seedData()
            trips = seed.trips
            legacyRounds = seed.legacyRounds
            courseCards = Self.seedCourseCards()
        }
    }

    func signOut() {
        guard !configuration.useMockData else {
            isAuthenticated = false
            path.removeAll()
            golfersPath.removeAll()
            selectedTab = .rounds
            return
        }
        Task { await signOutProductionSession() }
    }

    func trip(id: String) -> LocalTripExperience? {
        trips.first(where: { $0.id == id })
    }

    /// Trip detail is registered only in the Rounds stack, so opening one from
    /// anywhere else has to bring that tab forward with it.
    func showTrip(_ tripID: String) {
        selectedTab = .rounds
        path = [.trip(tripID)]
    }

    func createTrip(from draft: CreateTripDraft) -> String {
        let tripID = UUID().uuidString.lowercased()
        let publicID = UUID().uuidString.lowercased()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let formats = TournamentFormat.allCases.filter { draft.enabledFormats.contains($0) }
        let trip = Trip(
            id: tripID,
            publicId: publicID,
            ownerId: currentUserID,
            name: draft.name.isEmpty ? "Untitled Golf Trip" : draft.name,
            startDate: formatter.string(from: draft.startDate),
            endDate: formatter.string(from: draft.endDate),
            timeZone: TimeZone.current.identifier,
            lifecycle: .ready,
            enabledFormats: formats.isEmpty ? [.stableford] : formats,
            primaryFormat: formats.contains(draft.primaryFormat) ? draft.primaryFormat : (formats.first ?? .stableford),
            scoringMode: draft.scoringMode,
            scoreRevision: 0,
            isEntitled: false
        )

        let players = draft.playerNames.enumerated().compactMap { index, rawName -> TripPlayer? in
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return TripPlayer(
                id: UUID().uuidString.lowercased(),
                tripId: tripID,
                claimedUserId: index == 0 ? currentUserID : nil,
                displayName: name,
                role: index == 0 ? .captain : .player,
                rsvp: index == 0 ? .accepted : .pending,
                handicapSnapshot: draft.playerHandicaps.indices.contains(index) ? draft.playerHandicaps[index] : nil,
                sortOrder: index
            )
        }

        let rounds = draft.rounds.enumerated().map { index, round in
            TripRound(
                id: UUID().uuidString.lowercased(),
                publicId: UUID().uuidString.lowercased(),
                tripId: tripID,
                name: round.name.isEmpty ? "Round \(index + 1)" : round.name,
                courseName: round.courseName.isEmpty ? "Course TBD" : round.courseName,
                order: index,
                scheduledAt: round.scheduledAt,
                lifecycle: .scheduled,
                holes: Array(round.holes.prefix(round.holeCount))
            )
        }

        let roundPlayers = rounds.flatMap { round in
            players.map { player in
                TripRoundPlayer(
                    roundId: round.id,
                    tripPlayerId: player.id,
                    isActive: true,
                    courseHandicap: player.handicapSnapshot.map { Int($0.rounded()) },
                    playingHandicap: player.handicapSnapshot.map { Int($0.rounded()) }
                )
            }
        }

        let experience = LocalTripExperience(
            trip: trip,
            players: players,
            rounds: rounds,
            roundPlayers: roundPlayers,
            scores: [:],
            latestSnapshot: nil,
            inviteToken: Self.makeInviteToken()
        )
        for round in draft.rounds {
            let templateHoles = Array(round.holes.prefix(round.holeCount)).map {
                CourseCardHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
            }
            let normalizedName = round.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedName.isEmpty,
               !courseCards.contains(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame && $0.holes == templateHoles }) {
                courseCards.append(
                    CourseCard(
                        id: UUID().uuidString.lowercased(),
                        ownerId: currentUserID,
                        name: normalizedName,
                        teeName: nil,
                        holes: templateHoles
                    )
                )
            }
        }
        trips.insert(experience, at: 0)
        return tripID
    }

    func convertLegacyRound(_ legacyID: String) -> String? {
        guard let legacy = legacyRounds.first(where: { $0.id == legacyID }) else { return nil }
        var draft = CreateTripDraft()
        draft.name = "\(legacy.courseName) Trip"
        draft.startDate = legacy.startsAt
        draft.endDate = legacy.startsAt
        draft.rounds = [
            .init(
                name: "Round 1",
                courseName: legacy.courseName,
                scheduledAt: legacy.startsAt,
                holeCount: legacy.holes,
                holes: Array(CreateTripDraft.standardHoles.prefix(legacy.holes))
            ),
        ]
        draft.playerNames = [currentDisplayName] + legacy.inviteeDisplayNames
        draft.playerHandicaps = Array(repeating: nil, count: draft.playerNames.count)
        let tripID = createTrip(from: draft)
        if ProcessInfo.processInfo.arguments.contains("-ui-legacy-needs-setup"),
           let tripIndex = trips.firstIndex(where: { $0.id == tripID }),
           let existingRound = trips[tripIndex].rounds.first
        {
            trips[tripIndex].trip = trips[tripIndex].trip.replacing(lifecycle: .draft)
            trips[tripIndex].rounds[0] = TripRound(
                id: existingRound.id,
                publicId: existingRound.publicId,
                tripId: existingRound.tripId,
                name: existingRound.name,
                courseName: existingRound.courseName,
                order: existingRound.order,
                scheduledAt: existingRound.scheduledAt,
                lifecycle: .scheduled,
                holeCount: legacy.holes,
                holes: []
            )
        }
        return tripID
    }

    func unlockTrip(_ tripID: String) {
        replaceTrip(tripID) { experience in
            experience.trip = experience.trip.replacing(isEntitled: true)
        }
    }

    func startTournament(_ tripID: String) {
        replaceTrip(tripID) { experience in
            guard experience.trip.isEntitled else { return }
            experience.trip = experience.trip.replacing(
                lifecycle: .live,
                scoreRevision: experience.trip.scoreRevision + 1
            )
            if let first = experience.rounds.indices.first {
                experience.rounds[first] = experience.rounds[first].replacing(lifecycle: .live)
            }
            experience.latestSnapshot = self.makeSnapshot(for: experience)
        }
    }

    func claimPlayer(tripID: String, playerID: String) {
        replaceTrip(tripID) { experience in
            guard !experience.players.contains(where: { $0.claimedUserId == currentUserID }) else { return }
            guard let index = experience.players.firstIndex(where: { $0.id == playerID }) else { return }
            let player = experience.players[index]
            guard player.claimedUserId == nil else { return }
            experience.players[index] = TripPlayer(
                id: player.id,
                tripId: player.tripId,
                claimedUserId: currentUserID,
                displayName: player.displayName,
                role: player.role,
                rsvp: .accepted,
                handicapSnapshot: player.handicapSnapshot,
                sortOrder: player.sortOrder
            )
        }
    }

    func revokePlayerClaim(tripID: String, playerID: String) {
        replaceTrip(tripID) { experience in
            guard experience.trip.ownerId == currentUserID,
                  let index = experience.players.firstIndex(where: { $0.id == playerID })
            else { return }
            let player = experience.players[index]
            guard player.role != .captain else { return }
            experience.players[index] = TripPlayer(
                id: player.id,
                tripId: player.tripId,
                claimedUserId: nil,
                displayName: player.displayName,
                role: player.role,
                rsvp: .pending,
                handicapSnapshot: player.handicapSnapshot,
                sortOrder: player.sortOrder
            )
        }
    }

    func declineSeat(tripID: String, playerID: String) {
        replaceTrip(tripID) { experience in
            guard let index = experience.players.firstIndex(where: { $0.id == playerID }),
                  experience.players[index].claimedUserId == currentUserID,
                  experience.players[index].role != .captain
            else { return }
            let player = experience.players[index]
            experience.players[index] = TripPlayer(
                id: player.id,
                tripId: player.tripId,
                claimedUserId: nil,
                displayName: player.displayName,
                role: player.role,
                rsvp: .declined,
                handicapSnapshot: player.handicapSnapshot,
                sortOrder: player.sortOrder
            )
        }
    }

    func rotateInvite(tripID: String) {
        replaceTrip(tripID) { experience in
            guard experience.trip.ownerId == currentUserID else { return }
            experience.inviteToken = Self.makeInviteToken()
        }
    }

    func completeCurrentRound(tripID: String) {
        replaceTrip(tripID) { experience in
            guard experience.trip.ownerId == currentUserID,
                  let current = experience.rounds.firstIndex(where: { $0.lifecycle == .live })
            else { return }
            experience.rounds[current] = experience.rounds[current].replacing(lifecycle: .completed)
            if experience.rounds.indices.contains(current + 1) {
                experience.rounds[current + 1] = experience.rounds[current + 1].replacing(lifecycle: .live)
                experience.trip = experience.trip.replacing(scoreRevision: experience.trip.scoreRevision + 1)
            } else {
                experience.trip = experience.trip.replacing(
                    lifecycle: .completed,
                    scoreRevision: experience.trip.scoreRevision + 1
                )
            }
            experience.latestSnapshot = self.makeSnapshot(for: experience)
        }
    }

    func recordScore(
        tripID: String,
        roundID: String,
        playerID: String,
        hole: Int,
        strokes: Int,
        penalties: Int = 0
    ) {
        replaceTrip(tripID) { experience in
            let key = HoleScoreKey(roundID: roundID, playerID: playerID, hole: hole)
            experience.scores[key] = LocalHoleScore(
                strokes: max(1, strokes),
                penalties: max(0, penalties)
            )
            experience.trip = experience.trip.replacing(scoreRevision: experience.trip.scoreRevision + 1)
            experience.latestSnapshot = self.makeSnapshot(for: experience)
        }
    }

    func shareURL(for tripID: String) -> URL? {
        guard let trip = trip(id: tripID) else { return nil }
        return configuration.webBaseURL.appending(path: "t").appending(path: trip.inviteToken)
    }

    func replaceTrip(_ tripID: String, mutation: (inout LocalTripExperience) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == tripID }) else { return }
        var copy = trips[index]
        mutation(&copy)
        trips[index] = copy
    }

    func makeSnapshot(for experience: LocalTripExperience) -> LeaderboardSnapshotV1 {
        let currentRound = experience.rounds.first(where: { $0.lifecycle == .live })
            ?? experience.rounds.last(where: { $0.lifecycle == .completed })
            ?? experience.rounds.first

        let scoringRounds = experience.rounds
            .filter { $0.lifecycle == .live || $0.lifecycle == .completed }
            .sorted { $0.order < $1.order }
        let roundPlayerRounds: [[PlayerRound]] = scoringRounds.map { round in
            experience.roundPlayers
                .filter { $0.roundId == round.id && $0.isActive }
                .compactMap { participation in
                    guard experience.players.contains(where: { $0.id == participation.tripPlayerId }) else {
                        return nil
                    }
                    let holes = round.holes.map { hole in
                        let score = experience.scores[
                            HoleScoreKey(
                                roundID: round.id,
                                playerID: participation.tripPlayerId,
                                hole: hole.number
                            )
                        ]
                        return HoleScore(
                            hole: hole.number,
                            par: hole.par,
                            strokeIndex: hole.strokeIndex ?? hole.number,
                            strokes: score?.strokes,
                            penalties: score?.penalties ?? 0
                        )
                    }
                    return PlayerRound(
                        playerId: participation.tripPlayerId,
                        courseHandicap: participation.playingHandicap ?? participation.courseHandicap ?? 0,
                        holes: holes
                    )
                }
        }
        let holeCounts = scoringRounds.map(\.holes.count)

        let currentPlayerRounds = currentRound.flatMap { round in
            scoringRounds.firstIndex(where: { $0.id == round.id }).map { roundPlayerRounds[$0] }
        } ?? []
        let throughHole = currentPlayerRounds.flatMap(\.holes)
            .filter { $0.strokes != nil }
            .map(\.hole)
            .max() ?? 0
        let holesPlayedByPlayer = Dictionary(
            grouping: roundPlayerRounds.flatMap { $0 },
            by: \.playerId
        ).mapValues { rounds in
            rounds.reduce(0) { $0 + $1.holes.filter { $0.strokes != nil }.count }
        }

        let boards = experience.trip.enabledFormats.map { format -> LeaderboardBoardV1 in
            let raw: [PlayerStanding]
            let skinsCarry: Int?
            switch format {
            case .stableford:
                raw = TeeCircleScoring.tripStandings(
                    rounds: roundPlayerRounds,
                    format: .stableford,
                    scoring: experience.trip.scoringMode,
                    holeCounts: holeCounts
                )
                skinsCarry = nil
            case .skins:
                let skins = TeeCircleScoring.tripSkins(
                    rounds: roundPlayerRounds,
                    scoring: experience.trip.scoringMode,
                    holeCounts: holeCounts
                )
                raw = skins.standings
                skinsCarry = skins.carry
            }
            let grouped = Dictionary(grouping: raw, by: \.value)
            var rankByValue: [Int: Int] = [:]
            for (index, item) in raw.enumerated() where rankByValue[item.value] == nil {
                rankByValue[item.value] = index + 1
            }
            let standings = raw.enumerated().map { index, item in
                let player = experience.players.first(where: { $0.id == item.playerId })
                return LeaderboardStandingV1(
                    playerId: item.playerId,
                    displayName: player?.displayName ?? "Player",
                    rank: rankByValue[item.value] ?? index + 1,
                    value: item.value,
                    tied: (grouped[item.value]?.count ?? 0) > 1,
                    holesPlayed: holesPlayedByPlayer[item.playerId] ?? 0
                )
            }
            return LeaderboardBoardV1(
                format: format,
                scoring: experience.trip.scoringMode,
                standings: standings,
                skinsCarry: skinsCarry
            )
        }

        let leader = boards.first(where: { $0.format == experience.trip.primaryFormat })?.standings.first
        return LeaderboardSnapshotV1(
            tripId: experience.trip.publicId,
            revision: experience.trip.scoreRevision,
            status: experience.trip.lifecycle,
            primaryFormat: experience.trip.primaryFormat,
            currentRound: currentRound.map {
                SnapshotRoundV1(publicId: $0.publicId, name: $0.name, throughHole: throughHole)
            },
            boards: boards,
            moment: leader.map {
                let kind: LeaderboardMomentV1.Kind = experience.trip.lifecycle == .completed
                    ? .finalResult
                    : .scoreUpdate
                return LeaderboardMomentV1(
                    kind: kind,
                    summary: experience.trip.lifecycle == .completed
                        ? ($0.tied
                            ? "The final standings are tied at the top"
                            : "\($0.displayName) finishes on top")
                        : "\($0.displayName) leads through \(throughHole)"
                )
            },
            generatedAt: .now
        )
    }

    private static func makeInviteToken() -> String {
        (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func seedCourseCards() -> [CourseCard] {
        [
            CourseCard(
                id: "pinehurst-no2-blue",
                ownerId: "demo-user",
                name: "Pinehurst No. 2",
                teeName: "Blue",
                holes: CreateTripDraft.standardHoles.map {
                    CourseCardHole(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex)
                }
            ),
        ]
    }

    private static func seedData() -> (trips: [LocalTripExperience], legacyRounds: [LegacyRoundSummary]) {
        let tripID = "pinehurst-2026"
        let players = [
            TripPlayer(id: "luke", tripId: tripID, claimedUserId: "demo-user", displayName: "Luke", role: .captain, rsvp: .accepted, handicapSnapshot: 9.4, sortOrder: 0),
            TripPlayer(id: "sean", tripId: tripID, claimedUserId: "sean-user", displayName: "Sean", role: .player, rsvp: .accepted, handicapSnapshot: 12.1, sortOrder: 1),
            TripPlayer(id: "mike", tripId: tripID, claimedUserId: nil, displayName: "Mike", role: .player, rsvp: .pending, handicapSnapshot: 7.8, sortOrder: 2),
            TripPlayer(id: "chris", tripId: tripID, claimedUserId: "chris-user", displayName: "Chris", role: .scorer, rsvp: .accepted, handicapSnapshot: 15.2, sortOrder: 3),
        ]
        let round = TripRound(
            id: "round-1",
            publicId: "no2-opening",
            tripId: tripID,
            name: "Opening Round",
            courseName: "Pinehurst No. 2",
            order: 0,
            scheduledAt: .now,
            lifecycle: .live,
            holes: CreateTripDraft.standardHoles
        )
        let roundTwo = TripRound(
            id: "round-2",
            publicId: "no4-finale",
            tripId: tripID,
            name: "Final Round",
            courseName: "Pinehurst No. 4",
            order: 1,
            scheduledAt: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            lifecycle: .scheduled,
            holes: CreateTripDraft.standardHoles
        )
        let trip = Trip(
            id: tripID,
            publicId: "trip-pinehurst-2026",
            ownerId: "demo-user",
            name: "Pinehurst Cup",
            startDate: "2026-07-13",
            endDate: "2026-07-15",
            timeZone: "America/New_York",
            lifecycle: .live,
            enabledFormats: [.stableford, .skins],
            primaryFormat: .stableford,
            scoringMode: .net,
            scoreRevision: 24,
            isEntitled: true
        )
        let roundPlayers = [round, roundTwo].flatMap { item in
            players.map { player in
                TripRoundPlayer(
                    roundId: item.id,
                    tripPlayerId: player.id,
                    isActive: true,
                    courseHandicap: player.handicapSnapshot.map { Int($0.rounded()) },
                    playingHandicap: player.handicapSnapshot.map { Int($0.rounded()) }
                )
            }
        }
        var scores: [HoleScoreKey: LocalHoleScore] = [:]
        let sample: [String: [Int]] = [
            "luke": [4, 5, 3, 5, 4, 4],
            "sean": [5, 4, 4, 5, 3, 5],
            "mike": [4, 4, 3, 6, 4, 4],
            "chris": [5, 5, 4, 5, 4, 5],
        ]
        for (playerID, values) in sample {
            for (index, value) in values.enumerated() {
                scores[HoleScoreKey(roundID: round.id, playerID: playerID, hole: index + 1)] =
                    LocalHoleScore(strokes: value, penalties: 0)
            }
        }
        var experience = LocalTripExperience(
            trip: trip,
            players: players,
            rounds: [round, roundTwo],
            roundPlayers: roundPlayers,
            scores: scores,
            latestSnapshot: nil,
            inviteToken: "c1b8e71fa49e44efaf411ba277297ccfa6dd67c8e40d4361b8d62b3c1f946d31"
        )
        let store = TeeCircleStoreSeedSnapshotBuilder()
        experience.latestSnapshot = store.make(for: experience)

        let legacy = LegacyRoundSummary(
            id: "legacy-1",
            courseName: "Bethpage Black",
            startsAt: Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now,
            holes: 18,
            inviteeDisplayNames: ["Sean", "Mike"]
        )
        return ([experience, seedBandonExperience()], [legacy])
    }

    /// A second, finished trip sharing Sean and Chris. Without it the golfers
    /// list never exercises cross-trip merging — every seat would appear exactly
    /// once and the aggregated round counts would be indistinguishable from a
    /// single-trip read.
    private static func seedBandonExperience() -> LocalTripExperience {
        let tripID = "bandon-2026"
        let players = [
            TripPlayer(id: "bandon-luke", tripId: tripID, claimedUserId: "demo-user", displayName: "Luke", role: .captain, rsvp: .accepted, handicapSnapshot: 9.4, sortOrder: 0),
            TripPlayer(id: "bandon-sean", tripId: tripID, claimedUserId: "sean-user", displayName: "Sean", role: .player, rsvp: .accepted, handicapSnapshot: 12.1, sortOrder: 1),
            TripPlayer(id: "bandon-chris", tripId: tripID, claimedUserId: "chris-user", displayName: "Chris", role: .player, rsvp: .accepted, handicapSnapshot: 15.2, sortOrder: 2),
        ]
        let round = TripRound(
            id: "bandon-round-1",
            publicId: "bandon-preserve",
            tripId: tripID,
            name: "Preserve Loop",
            courseName: "Bandon Preserve",
            order: 0,
            scheduledAt: Calendar.current.date(byAdding: .day, value: -34, to: .now),
            lifecycle: .completed,
            holes: CreateTripDraft.standardHoles
        )
        let trip = Trip(
            id: tripID,
            publicId: "trip-bandon-2026",
            ownerId: "demo-user",
            name: "Bandon Weekend",
            startDate: "2026-06-12",
            endDate: "2026-06-13",
            timeZone: "America/Los_Angeles",
            lifecycle: .completed,
            enabledFormats: [.stableford],
            primaryFormat: .stableford,
            scoringMode: .net,
            scoreRevision: 18,
            isEntitled: true
        )
        return LocalTripExperience(
            trip: trip,
            players: players,
            rounds: [round],
            roundPlayers: players.map { player in
                TripRoundPlayer(
                    roundId: round.id,
                    tripPlayerId: player.id,
                    isActive: true,
                    courseHandicap: player.handicapSnapshot.map { Int($0.rounded()) },
                    playingHandicap: player.handicapSnapshot.map { Int($0.rounded()) }
                )
            },
            scores: [:],
            latestSnapshot: nil,
            inviteToken: "b7d1e2f3a4c5b6978081726354af90cd12ef34ab56cd78ef90ab12cd34ef5678"
        )
    }
}

private struct TeeCircleStoreSeedSnapshotBuilder {
    func make(for experience: LocalTripExperience) -> LeaderboardSnapshotV1 {
        let board = LeaderboardBoardV1(
            format: .stableford,
            scoring: .net,
            standings: [
                .init(playerId: "sean", displayName: "Sean", rank: 1, value: 14, tied: false, holesPlayed: 6),
                .init(playerId: "luke", displayName: "Luke", rank: 2, value: 13, tied: false, holesPlayed: 6),
                .init(playerId: "mike", displayName: "Mike", rank: 3, value: 12, tied: false, holesPlayed: 6),
                .init(playerId: "chris", displayName: "Chris", rank: 4, value: 10, tied: false, holesPlayed: 6),
            ]
        )
        let skins = LeaderboardBoardV1(
            format: .skins,
            scoring: .net,
            standings: [
                .init(playerId: "mike", displayName: "Mike", rank: 1, value: 3, tied: false, holesPlayed: 6),
                .init(playerId: "sean", displayName: "Sean", rank: 2, value: 2, tied: false, holesPlayed: 6),
                .init(playerId: "luke", displayName: "Luke", rank: 3, value: 1, tied: false, holesPlayed: 6),
                .init(playerId: "chris", displayName: "Chris", rank: 4, value: 0, tied: false, holesPlayed: 6),
            ]
        )
        return LeaderboardSnapshotV1(
            tripId: experience.trip.publicId,
            revision: experience.trip.scoreRevision,
            status: .live,
            primaryFormat: .stableford,
            currentRound: .init(publicId: "no2-opening", name: "Opening Round", throughHole: 6),
            boards: [board, skins],
            moment: .init(kind: .leadChange, summary: "Sean took the lead through 6"),
            generatedAt: .now
        )
    }
}

extension Trip {
    func replacing(
        lifecycle: TripLifecycle? = nil,
        scoreRevision: Int? = nil,
        isEntitled: Bool? = nil
    ) -> Trip {
        Trip(
            id: id,
            publicId: publicId,
            ownerId: ownerId,
            name: name,
            startDate: startDate,
            endDate: endDate,
            timeZone: timeZone,
            lifecycle: lifecycle ?? self.lifecycle,
            enabledFormats: enabledFormats,
            primaryFormat: primaryFormat,
            scoringMode: scoringMode,
            scoreRevision: scoreRevision ?? self.scoreRevision,
            isEntitled: isEntitled ?? self.isEntitled
        )
    }
}

extension TripRound {
    func replacing(lifecycle: RoundLifecycle) -> TripRound {
        TripRound(
            id: id,
            publicId: publicId,
            tripId: tripId,
            name: name,
            courseName: courseName,
            order: order,
            scheduledAt: scheduledAt,
            lifecycle: lifecycle,
            holeCount: holeCount,
            holes: holes
        )
    }
}
