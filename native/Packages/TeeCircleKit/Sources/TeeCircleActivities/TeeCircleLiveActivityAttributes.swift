import Foundation
import TeeCircleDomain

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

public struct TeeCircleActivityContentState: Codable, Equatable, Hashable, Sendable {
    public let revision: Int
    public let status: TripLifecycle
    public let roundName: String?
    public let throughHole: Int
    public let leaderName: String?
    public let leaderValue: Int?
    public let viewerRank: Int?
    public let viewerValue: Int?
    public let skinsCarry: Int?
    public let updatedAt: Date

    public init(
        revision: Int,
        status: TripLifecycle,
        roundName: String?,
        throughHole: Int,
        leaderName: String?,
        leaderValue: Int?,
        viewerRank: Int?,
        viewerValue: Int?,
        skinsCarry: Int?,
        updatedAt: Date
    ) {
        self.revision = revision
        self.status = status
        self.roundName = roundName
        self.throughHole = throughHole
        self.leaderName = leaderName
        self.leaderValue = leaderValue
        self.viewerRank = viewerRank
        self.viewerValue = viewerValue
        self.skinsCarry = skinsCarry
        self.updatedAt = updatedAt
    }

    public var encodedSize: Int {
        (try? JSONEncoder().encode(self).count) ?? .max
    }

    public var fitsActivityKitPushLimit: Bool {
        encodedSize < 4_096
    }
}

public struct TeeCircleLiveActivityAttributes: Codable, Equatable, Hashable, Sendable {
    public let tripId: String
    public let tripName: String
    public let viewerPlayerId: String?

    public init(tripId: String, tripName: String, viewerPlayerId: String?) {
        self.tripId = tripId
        self.tripName = tripName
        self.viewerPlayerId = viewerPlayerId
    }
}

#if canImport(ActivityKit) && os(iOS)
@available(iOS 16.1, *)
extension TeeCircleLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = TeeCircleActivityContentState
}
#endif

public enum TeeCircleActivityMapper {
    public static func contentState(
        from snapshot: LeaderboardSnapshotV1,
        viewerPlayerId: String?,
        skinsCarry: Int? = nil
    ) -> TeeCircleActivityContentState {
        let board = snapshot.primaryBoard
        let leader = board?.standings.first(where: { $0.rank == 1 }) ?? board?.standings.first
        let viewer = viewerPlayerId.flatMap { id in
            board?.standings.first(where: { $0.playerId == id })
        }
        let resolvedSkinsCarry = skinsCarry ?? snapshot.boards
            .first(where: { $0.format == .skins })?
            .skinsCarry

        return TeeCircleActivityContentState(
            revision: snapshot.revision,
            status: snapshot.status,
            roundName: snapshot.currentRound?.name,
            throughHole: snapshot.currentRound?.throughHole ?? 0,
            leaderName: leader?.displayName,
            leaderValue: leader?.value,
            viewerRank: viewer?.rank,
            viewerValue: viewer?.value,
            skinsCarry: resolvedSkinsCarry,
            updatedAt: snapshot.generatedAt
        )
    }
}
