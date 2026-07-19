import Foundation

public enum TripLifecycle: String, Codable, CaseIterable, Hashable, Sendable {
    case draft
    case ready
    case live
    case completed
    case archived
}

public enum RoundLifecycle: String, Codable, CaseIterable, Hashable, Sendable {
    case scheduled
    case live
    case completed
}

public enum TripPlayerRole: String, Codable, CaseIterable, Hashable, Sendable {
    case captain
    case scorer
    case player
}

public enum RSVPStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case accepted
    case declined
}

public struct Trip: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let publicId: String
    public let ownerId: String
    public let name: String
    /// An ISO-8601 calendar date (`yyyy-MM-dd`) interpreted in `timeZone`.
    public let startDate: String
    /// An ISO-8601 calendar date (`yyyy-MM-dd`) interpreted in `timeZone`.
    public let endDate: String
    public let timeZone: String
    public let lifecycle: TripLifecycle
    public let enabledFormats: [TournamentFormat]
    public let primaryFormat: TournamentFormat
    public let scoringMode: ScoringMode
    public let scoreRevision: Int
    public let isEntitled: Bool

    public init(
        id: String,
        publicId: String,
        ownerId: String,
        name: String,
        startDate: String,
        endDate: String,
        timeZone: String,
        lifecycle: TripLifecycle,
        enabledFormats: [TournamentFormat],
        primaryFormat: TournamentFormat,
        scoringMode: ScoringMode,
        scoreRevision: Int,
        isEntitled: Bool
    ) {
        self.id = id
        self.publicId = publicId
        self.ownerId = ownerId
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.timeZone = timeZone
        self.lifecycle = lifecycle
        self.enabledFormats = enabledFormats
        self.primaryFormat = primaryFormat
        self.scoringMode = scoringMode
        self.scoreRevision = scoreRevision
        self.isEntitled = isEntitled
    }
}

public struct TripPlayer: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let tripId: String
    public let claimedUserId: String?
    public let displayName: String
    public let role: TripPlayerRole
    public let rsvp: RSVPStatus
    public let handicapSnapshot: Double?
    public let sortOrder: Int

    public init(
        id: String,
        tripId: String,
        claimedUserId: String?,
        displayName: String,
        role: TripPlayerRole,
        rsvp: RSVPStatus,
        handicapSnapshot: Double?,
        sortOrder: Int
    ) {
        self.id = id
        self.tripId = tripId
        self.claimedUserId = claimedUserId
        self.displayName = displayName
        self.role = role
        self.rsvp = rsvp
        self.handicapSnapshot = handicapSnapshot
        self.sortOrder = sortOrder
    }
}

public struct TripRound: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let publicId: String
    public let tripId: String
    public let name: String
    public let courseName: String
    public let order: Int
    public let scheduledAt: Date?
    public let lifecycle: RoundLifecycle
    /// Expected immutable card length, retained even while a converted legacy
    /// draft is waiting for its manual par/stroke-index card.
    public let holeCount: Int
    public let holes: [RoundHole]

    public init(
        id: String,
        publicId: String,
        tripId: String,
        name: String,
        courseName: String,
        order: Int,
        scheduledAt: Date?,
        lifecycle: RoundLifecycle,
        holeCount: Int? = nil,
        holes: [RoundHole]
    ) {
        self.id = id
        self.publicId = publicId
        self.tripId = tripId
        self.name = name
        self.courseName = courseName
        self.order = order
        self.scheduledAt = scheduledAt
        self.lifecycle = lifecycle
        self.holeCount = holeCount ?? holes.count
        self.holes = holes
    }
}

public struct RoundHole: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let par: Int
    public let strokeIndex: Int?

    public init(number: Int, par: Int, strokeIndex: Int?) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
    }
}

public struct TripRoundPlayer: Codable, Equatable, Hashable, Sendable {
    public let roundId: String
    public let tripPlayerId: String
    public let isActive: Bool
    public let courseHandicap: Int?
    public let playingHandicap: Int?

    public init(
        roundId: String,
        tripPlayerId: String,
        isActive: Bool,
        courseHandicap: Int?,
        playingHandicap: Int?
    ) {
        self.roundId = roundId
        self.tripPlayerId = tripPlayerId
        self.isActive = isActive
        self.courseHandicap = courseHandicap
        self.playingHandicap = playingHandicap
    }
}

public struct CourseCard: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let ownerId: String
    public let name: String
    public let teeName: String?
    public let holes: [CourseCardHole]

    public init(id: String, ownerId: String, name: String, teeName: String?, holes: [CourseCardHole]) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.teeName = teeName
        self.holes = holes
    }
}

public struct CourseCardHole: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let par: Int
    public let strokeIndex: Int?

    public init(number: Int, par: Int, strokeIndex: Int?) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
    }
}

public struct TripBootstrap: Codable, Equatable, Sendable {
    public let trip: Trip
    public let players: [TripPlayer]
    public let rounds: [TripRound]
    public let roundPlayers: [TripRoundPlayer]
    public let latestSnapshot: LeaderboardSnapshotV1?

    public init(
        trip: Trip,
        players: [TripPlayer],
        rounds: [TripRound],
        roundPlayers: [TripRoundPlayer],
        latestSnapshot: LeaderboardSnapshotV1?
    ) {
        self.trip = trip
        self.players = players
        self.rounds = rounds
        self.roundPlayers = roundPlayers
        self.latestSnapshot = latestSnapshot
    }
}

public struct LegacyRoundSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let courseName: String
    public let startsAt: Date
    public let holes: Int
    public let inviteeDisplayNames: [String]

    public init(
        id: String,
        courseName: String,
        startsAt: Date,
        holes: Int,
        inviteeDisplayNames: [String]
    ) {
        self.id = id
        self.courseName = courseName
        self.startsAt = startsAt
        self.holes = holes
        self.inviteeDisplayNames = inviteeDisplayNames
    }
}
