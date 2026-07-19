import Foundation
import TeeCircleDomain

struct HoleScoreKey: Hashable, Sendable {
    let roundID: String
    let playerID: String
    let hole: Int
}

struct LocalHoleScore: Equatable, Hashable, Sendable {
    let strokes: Int
    let penalties: Int

    var grossStrokes: Int { strokes + penalties }
}

struct LocalTripExperience: Identifiable, Sendable {
    var id: String { trip.id }
    var trip: Trip
    var players: [TripPlayer]
    var rounds: [TripRound]
    var roundPlayers: [TripRoundPlayer]
    var scores: [HoleScoreKey: LocalHoleScore]
    var latestSnapshot: LeaderboardSnapshotV1?
    var inviteToken: String

    /// A final ActivityKit state is safe to apply only when it is the server's
    /// canonical snapshot for the trip revision we just loaded.
    var canonicalTerminalSnapshot: LeaderboardSnapshotV1? {
        guard [.completed, .archived].contains(trip.lifecycle),
              let latestSnapshot,
              [.completed, .archived].contains(latestSnapshot.status),
              latestSnapshot.revision == trip.scoreRevision
        else { return nil }
        return latestSnapshot
    }

    @available(*, deprecated, renamed: "canonicalTerminalSnapshot")
    var canonicalCompletedSnapshot: LeaderboardSnapshotV1? {
        canonicalTerminalSnapshot
    }

    var bootstrap: TripBootstrap {
        TripBootstrap(
            trip: trip,
            players: players,
            rounds: rounds,
            roundPlayers: roundPlayers,
            latestSnapshot: latestSnapshot
        )
    }
}

struct CreateTripDraft: Sendable {
    struct RoundDraft: Identifiable, Sendable {
        let id: UUID
        var name: String
        var courseName: String
        var scheduledAt: Date
        var holeCount: Int
        var holes: [RoundHole]
        var walkRide: String

        init(
            id: UUID = UUID(),
            name: String = "Opening Round",
            courseName: String = "",
            scheduledAt: Date = .now,
            holeCount: Int = 18,
            holes: [RoundHole] = CreateTripDraft.standardHoles,
            walkRide: String = "ride"
        ) {
            self.id = id
            self.name = name
            self.courseName = courseName
            self.scheduledAt = scheduledAt
            self.holeCount = holeCount
            self.holes = holes
            self.walkRide = walkRide
        }
    }

    var name = ""
    var startDate = Date.now
    var endDate = Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now
    var rounds = [RoundDraft()]
    var playerNames = ["You"]
    var playerHandicaps: [Double?] = [nil]
    var enabledFormats: Set<TournamentFormat> = [.stableford, .skins]
    var primaryFormat: TournamentFormat = .stableford
    var scoringMode: ScoringMode = .net

    static let standardHoles: [RoundHole] = {
        let pars = [4, 4, 3, 5, 4, 4, 5, 3, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4]
        return pars.enumerated().map { index, par in
            RoundHole(number: index + 1, par: par, strokeIndex: index + 1)
        }
    }()

    static func singleRound(
        courseName: String,
        teeTime: Date,
        holeCount: Int,
        walkRide: String,
        playerNames: [String],
        holes: [RoundHole]? = nil,
        calendar: Calendar = .current
    ) -> CreateTripDraft {
        let normalizedCourse = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHoleCount = holeCount <= 9 ? 9 : 18
        let normalizedPlayers = playerNames.compactMap { rawName -> String? in
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        let normalizedHoles = Array((holes ?? standardHoles).prefix(normalizedHoleCount))
        let day = calendar.startOfDay(for: teeTime)

        var draft = CreateTripDraft()
        draft.name = normalizedCourse
        draft.startDate = day
        draft.endDate = day
        draft.rounds = [
            .init(
                name: "Round at \(normalizedCourse)",
                courseName: normalizedCourse,
                scheduledAt: teeTime,
                holeCount: normalizedHoleCount,
                holes: normalizedHoles,
                walkRide: walkRide == "walk" ? "walk" : "ride"
            ),
        ]
        draft.playerNames = normalizedPlayers.isEmpty ? ["Player"] : normalizedPlayers
        draft.playerHandicaps = Array(repeating: nil, count: draft.playerNames.count)
        draft.scoringMode = .gross
        return draft
    }
}
