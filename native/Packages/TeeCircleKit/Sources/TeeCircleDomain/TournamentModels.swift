import Foundation

public enum TournamentFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case stableford
    case skins
}

public enum ScoringMode: String, Codable, CaseIterable, Hashable, Sendable {
    case gross
    case net
}

public struct HoleScore: Codable, Equatable, Hashable, Sendable {
    public let hole: Int
    public let par: Int
    public let strokeIndex: Int
    public let strokes: Int?
    /// Penalty strokes are stored separately from played strokes and added once
    /// before gross or net scoring is calculated.
    public let penalties: Int

    public init(hole: Int, par: Int, strokeIndex: Int, strokes: Int?, penalties: Int = 0) {
        self.hole = hole
        self.par = par
        self.strokeIndex = strokeIndex
        self.strokes = strokes
        self.penalties = penalties
    }

    private enum CodingKeys: String, CodingKey {
        case hole
        case par
        case strokeIndex
        case strokes
        case penalties
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hole = try container.decode(Int.self, forKey: .hole)
        par = try container.decode(Int.self, forKey: .par)
        strokeIndex = try container.decode(Int.self, forKey: .strokeIndex)
        strokes = try container.decodeIfPresent(Int.self, forKey: .strokes)
        penalties = try container.decodeIfPresent(Int.self, forKey: .penalties) ?? 0
    }
}

public struct PlayerRound: Codable, Equatable, Hashable, Sendable {
    public let playerId: String
    public let courseHandicap: Int
    public let holes: [HoleScore]

    public init(playerId: String, courseHandicap: Int, holes: [HoleScore]) {
        self.playerId = playerId
        self.courseHandicap = courseHandicap
        self.holes = holes
    }
}

public struct PlayerStanding: Codable, Equatable, Hashable, Sendable {
    public let playerId: String
    public let value: Int

    public init(playerId: String, value: Int) {
        self.playerId = playerId
        self.value = value
    }
}

public enum SkinsHoleResult: Codable, Equatable, Hashable, Sendable {
    case won(hole: Int, winnerId: String, skins: Int)
    case carried(hole: Int, carried: Int)

    private enum CodingKeys: String, CodingKey {
        case hole
        case winnerId
        case skins
        case carried
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hole = try container.decode(Int.self, forKey: .hole)
        if let winnerId = try container.decodeIfPresent(String.self, forKey: .winnerId) {
            self = .won(
                hole: hole,
                winnerId: winnerId,
                skins: try container.decode(Int.self, forKey: .skins)
            )
        } else {
            self = .carried(
                hole: hole,
                carried: try container.decode(Int.self, forKey: .carried)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .won(hole, winnerId, skins):
            try container.encode(hole, forKey: .hole)
            try container.encode(winnerId, forKey: .winnerId)
            try container.encode(skins, forKey: .skins)
        case let .carried(hole, carried):
            try container.encode(hole, forKey: .hole)
            try container.encodeNil(forKey: .winnerId)
            try container.encode(carried, forKey: .carried)
        }
    }
}

public struct SkinsResult: Codable, Equatable, Hashable, Sendable {
    public let holes: [SkinsHoleResult]
    public let standings: [PlayerStanding]
    /// Value of the next unresolved skin, including the current hole's skin.
    public let carry: Int

    public init(holes: [SkinsHoleResult], standings: [PlayerStanding], carry: Int = 1) {
        self.holes = holes
        self.standings = standings
        self.carry = carry
    }
}
