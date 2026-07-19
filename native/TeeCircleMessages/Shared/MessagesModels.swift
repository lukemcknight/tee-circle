import Foundation
import TeeCircleDomain

/// The main app writes one credential per trip to the shared Keychain service below.
/// Keeping sessions trip-scoped makes revocation independent and limits a leaked token.
struct ExtensionSessionCredentialV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let tripId: String
    let sessionToken: String
    let deviceId: String
    let expiresAt: Date

    var isStructurallyValid: Bool {
        schemaVersion == 1
            && !tripId.isEmpty
            && sessionToken.count >= 24
            && !deviceId.isEmpty
    }

    func isUsable(deviceId currentDeviceId: String?, now: Date = .now) -> Bool {
        isStructurallyValid
            && currentDeviceId == deviceId
            && expiresAt.timeIntervalSince(now) > 30
    }
}

struct CachedMessagesTripV1: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let trip: Trip
    let inviteToken: String
    let claimedPlayer: TripPlayer?
    /// Internal round identifier copied by the main app or returned by bootstrap.
    let scoringRoundId: String?
    let scoringRoundHoleCount: Int?
    let snapshot: LeaderboardSnapshotV1
    let cachedAt: Date

    var id: String { trip.id }

    var nextHole: Int {
        min(max((snapshot.currentRound?.throughHole ?? 0) + 1, 1), holeCount)
    }

    var holeCount: Int {
        min(max(scoringRoundHoleCount ?? 18, 1), 18)
    }

    var canEnterScore: Bool {
        trip.lifecycle == .live
            && claimedPlayer != nil
            && scoringRoundId != nil
            && snapshot.currentRound != nil
    }

    func replacing(
        trip: Trip? = nil,
        player: TripPlayer?? = nil,
        scoringRoundId: String?? = nil,
        scoringRoundHoleCount: Int?? = nil,
        snapshot: LeaderboardSnapshotV1? = nil,
        cachedAt: Date = .now
    ) -> Self {
        Self(
            schemaVersion: 1,
            trip: trip ?? self.trip,
            inviteToken: inviteToken,
            claimedPlayer: player ?? claimedPlayer,
            scoringRoundId: scoringRoundId ?? self.scoringRoundId,
            scoringRoundHoleCount: scoringRoundHoleCount ?? self.scoringRoundHoleCount,
            snapshot: snapshot ?? self.snapshot,
            cachedAt: cachedAt
        )
    }
}

struct MessagesTripCacheV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let trips: [CachedMessagesTripV1]
}

struct PendingHoleInputV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let tripId: String
    let roundId: String
    let tripPlayerId: String
    var holeNumber: Int
    var strokes: Int
    var penalties: Int
    var idempotencyKey: String
    var updatedAt: Date

    mutating func markEdited() {
        idempotencyKey = UUID().uuidString.lowercased()
        updatedAt = .now
    }
}

struct MessagesBootstrapRequestV1: Encodable, Sendable {
    let schemaVersion = 1
    let tripId: String?
}

struct MessagesRoundReferenceV1: Codable, Equatable, Sendable {
    let roundId: String
    let publicId: String
    let name: String
    let status: String
    let holeCount: Int
}

struct MessagesBootstrapPayloadV1: Codable, Equatable, Sendable {
    let trip: Trip
    let snapshot: LeaderboardSnapshotV1
    let player: TripPlayer?
    let rounds: [MessagesRoundReferenceV1]

    var scoringRoundId: String? {
        activeRound?.roundId
    }

    var scoringRoundHoleCount: Int? {
        activeRound?.holeCount
    }

    private var activeRound: MessagesRoundReferenceV1? {
        guard let currentPublicId = snapshot.currentRound?.publicId else { return nil }
        return rounds.first(where: { $0.publicId == currentPublicId })
    }
}

struct ExtensionScoreCommandV1: Encodable, Equatable, Sendable {
    let schemaVersion = 1
    let roundId: String
    let tripPlayerId: String
    let holeNumber: Int
    let strokes: Int
    let penalties: Int
    let idempotencyKey: String
    let expectedScoreRevision: Int?
}

#if DEBUG
enum MessagesFixtures {
    static let trip: CachedMessagesTripV1 = {
        let tripId = "fixture-trip"
        let player = TripPlayer(
            id: "fixture-seat-sean",
            tripId: tripId,
            claimedUserId: "fixture-user",
            displayName: "Sean",
            role: .captain,
            rsvp: .accepted,
            handicapSnapshot: 9.4,
            sortOrder: 0
        )
        let snapshot = LeaderboardSnapshotV1(
            tripId: "summer-cup-2026",
            revision: 42,
            status: .live,
            primaryFormat: .stableford,
            currentRound: SnapshotRoundV1(
                publicId: "pinehurst-round",
                name: "Pinehurst No. 2",
                throughHole: 12
            ),
            boards: [
                LeaderboardBoardV1(
                    format: .stableford,
                    scoring: .net,
                    standings: [
                        .init(playerId: player.id, displayName: "Sean", rank: 1, value: 28, tied: false, holesPlayed: 12),
                        .init(playerId: "fixture-seat-marcus", displayName: "Marcus", rank: 2, value: 26, tied: false, holesPlayed: 12),
                        .init(playerId: "fixture-seat-luke", displayName: "Luke", rank: 3, value: 24, tied: false, holesPlayed: 11),
                    ]
                ),
                LeaderboardBoardV1(
                    format: .skins,
                    scoring: .net,
                    standings: [
                        .init(playerId: player.id, displayName: "Sean", rank: 1, value: 5, tied: false, holesPlayed: 12),
                        .init(playerId: "fixture-seat-marcus", displayName: "Marcus", rank: 2, value: 4, tied: false, holesPlayed: 12),
                    ]
                ),
            ],
            moment: .init(kind: .leadChange, summary: "Sean took the lead through 12"),
            generatedAt: .now.addingTimeInterval(-48)
        )
        return CachedMessagesTripV1(
            schemaVersion: 1,
            trip: Trip(
                id: tripId,
                publicId: "summer-cup-2026",
                ownerId: "fixture-user",
                name: "Pinehurst Summer Cup",
                startDate: "2026-07-13",
                endDate: "2026-07-15",
                timeZone: "America/New_York",
                lifecycle: .live,
                enabledFormats: [.stableford, .skins],
                primaryFormat: .stableford,
                scoringMode: .net,
                scoreRevision: 42,
                isEntitled: true
            ),
            inviteToken: "fixtureSummerCup26_abcdefghijklmnopqrstu",
            claimedPlayer: player,
            scoringRoundId: "fixture-round-id",
            scoringRoundHoleCount: 18,
            snapshot: snapshot,
            cachedAt: .now
        )
    }()
}
#endif
