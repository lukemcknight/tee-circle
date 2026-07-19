import Foundation

public struct LeaderboardSnapshotV1: Codable, Equatable, Hashable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let tripId: String
    public let revision: Int
    public let status: TripLifecycle
    public let primaryFormat: TournamentFormat
    public let currentRound: SnapshotRoundV1?
    public let boards: [LeaderboardBoardV1]
    public let moment: LeaderboardMomentV1?
    public let generatedAt: Date

    public init(
        schemaVersion: Int = Self.supportedSchemaVersion,
        tripId: String,
        revision: Int,
        status: TripLifecycle,
        primaryFormat: TournamentFormat,
        currentRound: SnapshotRoundV1?,
        boards: [LeaderboardBoardV1],
        moment: LeaderboardMomentV1?,
        generatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.tripId = tripId
        self.revision = revision
        self.status = status
        self.primaryFormat = primaryFormat
        self.currentRound = currentRound
        self.boards = boards
        self.moment = moment
        self.generatedAt = generatedAt
    }

    public var primaryBoard: LeaderboardBoardV1? {
        boards.first(where: { $0.format == primaryFormat }) ?? boards.first
    }
}

public struct SnapshotRoundV1: Codable, Equatable, Hashable, Sendable {
    public let publicId: String
    public let name: String
    public let throughHole: Int

    public init(publicId: String, name: String, throughHole: Int) {
        self.publicId = publicId
        self.name = name
        self.throughHole = throughHole
    }
}

public struct LeaderboardBoardV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { "\(format.rawValue)-\(scoring.rawValue)" }
    public let format: TournamentFormat
    public let scoring: ScoringMode
    public let standings: [LeaderboardStandingV1]
    public let skinsCarry: Int?

    public init(
        format: TournamentFormat,
        scoring: ScoringMode,
        standings: [LeaderboardStandingV1],
        skinsCarry: Int? = nil
    ) {
        self.format = format
        self.scoring = scoring
        self.standings = standings
        self.skinsCarry = skinsCarry
    }
}

public struct LeaderboardStandingV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { playerId }
    public let playerId: String
    public let displayName: String
    public let rank: Int
    public let value: Int
    public let tied: Bool
    public let holesPlayed: Int

    public init(
        playerId: String,
        displayName: String,
        rank: Int,
        value: Int,
        tied: Bool,
        holesPlayed: Int
    ) {
        self.playerId = playerId
        self.displayName = displayName
        self.rank = rank
        self.value = value
        self.tied = tied
        self.holesPlayed = holesPlayed
    }
}

public struct LeaderboardMomentV1: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case leadChange = "lead_change"
        case skinWon = "skin_won"
        case roundStarted = "round_started"
        case roundCompleted = "round_completed"
        case tripCompleted = "trip_completed"
        case scoreUpdate = "score_update"
        case finalResult = "final_result"
    }

    public let kind: Kind
    public let summary: String

    public init(kind: Kind, summary: String) {
        self.kind = kind
        self.summary = summary
    }
}
