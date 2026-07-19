import Foundation
import TeeCircleDomain

public struct LeaderboardCardPresentation: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: String { playerId }
        public let playerId: String
        public let rankText: String
        public let displayName: String
        public let progressText: String
        public let valueText: String

        public init(
            playerId: String,
            rankText: String,
            displayName: String,
            progressText: String,
            valueText: String
        ) {
            self.playerId = playerId
            self.rankText = rankText
            self.displayName = displayName
            self.progressText = progressText
            self.valueText = valueText
        }
    }

    public let eyebrow: String
    public let title: String
    public let subtitle: String
    public let rows: [Row]
    public let moment: String?
    public let isFinal: Bool

    public init(snapshot: LeaderboardSnapshotV1, maxRows: Int = 5) {
        let board = snapshot.primaryBoard
        eyebrow = snapshot.status.isTerminal ? "FINAL" : "LIVE LEADERBOARD"
        title = board.map(Self.boardTitle) ?? "Leaderboard"
        if let round = snapshot.currentRound {
            subtitle = round.throughHole > 0
                ? "\(round.name) · Through \(round.throughHole)"
                : round.name
        } else {
            subtitle = snapshot.status.isTerminal ? "Trip complete" : "Waiting for the first score"
        }
        rows = Array((board?.standings ?? []).prefix(max(0, maxRows))).map { standing in
            Row(
                playerId: standing.playerId,
                rankText: standing.tied ? "T\(standing.rank)" : "\(standing.rank)",
                displayName: standing.displayName,
                progressText: standing.holesPlayed == 1 ? "1 hole" : "\(standing.holesPlayed) holes",
                valueText: Self.valueText(value: standing.value, format: board?.format)
            )
        }
        moment = snapshot.moment?.summary
        isFinal = snapshot.status.isTerminal
    }

    private static func boardTitle(_ board: LeaderboardBoardV1) -> String {
        let format = switch board.format {
        case .stableford: "Stableford"
        case .skins: "Skins"
        }
        return "\(board.scoring == .net ? "Net" : "Gross") \(format)"
    }

    private static func valueText(value: Int, format: TournamentFormat?) -> String {
        switch format {
        case .skins:
            "\(value) \(value == 1 ? "skin" : "skins")"
        case .stableford, .none:
            "\(value) pts"
        }
    }
}


private extension TripLifecycle {
    var isTerminal: Bool { self == .completed || self == .archived }
}
