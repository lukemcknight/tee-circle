import Foundation
import TeeCircleAPI
import TeeCircleDomain

enum NativeRSVPStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case yes
    case no
    case pending
}

struct NativeTripSummaryV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { tripId }
    let tripId: String
    let publicId: String
    let name: String
    let startsOn: String
    let endsOn: String
    let timezone: String
    let status: TripLifecycle
    let primaryFormat: TournamentFormat
    let scoringMode: ScoringMode
    let scoreRevision: Int
    let isCaptain: Bool
    let rosterCount: Int
    let latestSnapshotRevision: Int?
}

struct NativeTripDetailV1: Codable, Equatable, Sendable {
    let tripId: String
    let publicId: String
    let name: String
    let startsOn: String
    let endsOn: String
    let timezone: String
    let status: TripLifecycle
    let enabledFormats: [TournamentFormat]
    let primaryFormat: TournamentFormat
    let scoringMode: ScoringMode
    let scoreRevision: Int
    let isCaptain: Bool
    let canManage: Bool
    let isUnlocked: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct NativeRosterSeatV1: Codable, Equatable, Identifiable, Sendable {
    var id: String { tripPlayerId }
    let tripPlayerId: String
    let displayName: String
    let role: TripPlayerRole
    let rsvp: NativeRSVPStatus
    let handicapSnapshot: Double?
    let claimed: Bool
    let isCurrentUser: Bool
    /// Optimistic concurrency token returned by `get_trip_bootstrap_v1`.
    let updatedAt: Date?
}

struct NativeRoundHoleV1: Codable, Equatable, Identifiable, Sendable {
    var id: Int { holeNumber }
    let holeNumber: Int
    let par: Int
    let strokeIndex: Int?
    let yards: Int?
}

struct NativeRoundPlayerV1: Codable, Equatable, Sendable {
    let tripPlayerId: String
    let courseHandicap: Int?
    let playingHandicap: Int?
    let status: String
}

struct NativeStoredHoleScoreV1: Codable, Equatable, Identifiable, Sendable {
    var id: String { scoreId }
    let scoreId: String
    let tripPlayerId: String
    let holeNumber: Int
    let strokes: Int
    let penalties: Int
    let revision: Int
    let updatedAt: Date
}

struct NativeTripRoundV1: Codable, Equatable, Identifiable, Sendable {
    var id: String { roundId }
    let roundId: String
    let publicId: String
    let tripOrder: Int
    let courseName: String
    let teeTime: Date?
    let holeCount: Int
    let walkRide: String?
    let status: RoundLifecycle
    let legacySourceRoundId: String?
    /// Optimistic concurrency token returned by `get_trip_bootstrap_v1`.
    let nativeUpdatedAt: Date?
    let holes: [NativeRoundHoleV1]
    let players: [NativeRoundPlayerV1]
    let scores: [NativeStoredHoleScoreV1]
}

struct ReadinessIssueV1: Codable, Equatable, Hashable, Sendable {
    let code: String
}

struct NativeTripBootstrapV1: Codable, Equatable, Sendable {
    let trip: NativeTripDetailV1
    let roster: [NativeRosterSeatV1]
    let rounds: [NativeTripRoundV1]
    let snapshot: LeaderboardSnapshotV1?
    let readinessIssues: [ReadinessIssueV1]
}

struct NativeLegacyRoundV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { roundId }
    let roundId: String
    let courseName: String
    let teeTime: Date
    let holeCount: Int
    let walkRide: String?
    let legacyStatus: String
    let isCreator: Bool
    let canConvert: Bool
}

struct LegacyConversionResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let publicId: String
    let roundId: String
    let legacySourceRoundId: String
    let needsCourseCard: Bool
}

struct TripInviteCredentialV1: Codable, Equatable, Hashable, Sendable {
    let inviteId: String
    /// Returned by the server only when the invite is created.
    let inviteToken: String
    let url: URL
    let expiresAt: Date?
}

enum TripInviteStatusV1: String, Codable, Equatable, Hashable, Sendable {
    case active
    case revoked
    case expired
    case exhausted
}

struct TripInviteMetadataV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { inviteId }
    let inviteId: String
    let createdAt: Date
    let expiresAt: Date?
    let revokedAt: Date?
    let useCount: Int
    let maxUses: Int?
    let status: TripInviteStatusV1
}

struct RevocationResultV1: Codable, Equatable, Hashable, Sendable {
    let revoked: Bool
}

struct ExtensionSessionIssueResultV1: Codable, Equatable, Hashable, Sendable {
    let sessionId: String
    /// A bearer secret. Store only in the shared Keychain vault.
    let sessionToken: String
    let tripId: String
    let tripPlayerId: String
    let expiresAt: Date
}

struct AcceptedHoleScoreV1: Codable, Equatable, Hashable, Sendable {
    let roundId: String
    let tripPlayerId: String
    let holeNumber: Int
    let strokes: Int
    let penalties: Int
    let grossTotal: Int
}

struct ActivityDispatchResultV1: Codable, Equatable, Hashable, Sendable {
    let status: String
    let processed: Int?
    let code: String?
}

struct RecordHoleScoreResultV1: Codable, Equatable, Sendable {
    let tripId: String
    let scoreId: String
    let acceptedRevision: Int
    let revision: Int
    let idempotentReplay: Bool
    let score: AcceptedHoleScoreV1
    let snapshot: LeaderboardSnapshotV1
    let activityDispatch: ActivityDispatchResultV1
}

enum APNsEnvironment: String, Codable, CaseIterable, Hashable, Sendable {
    case sandbox
    case production
}

struct DevicePushRegistrationResultV1: Codable, Equatable, Hashable, Sendable {
    let registrationId: String
    let provider: String
    let environment: APNsEnvironment
}

struct LiveActivityRegistrationResultV1: Codable, Equatable, Hashable, Sendable {
    let subscriptionId: String
    let tripId: String
    let activityId: String
}

struct PurchaseIntentV1: Codable, Equatable, Hashable, Sendable {
    let purchaseIntentId: String
    let tripId: String
    let productId: String
    let expiresAt: Date
}

enum PurchaseIntentStatusV1: String, Codable, Equatable, Hashable, Sendable {
    case pending
    case verified
    case cancelled
    case expired
}

struct PurchaseIntentCancellationResultV1: Codable, Equatable, Hashable, Sendable {
    let purchaseIntentId: String
    let tripId: String
    let status: PurchaseIntentStatusV1
}

struct PurchaseClaimResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let unlocked: Bool
    let idempotentReplay: Bool
}

// MARK: - Versioned command inputs and results

struct CreateNativeTripInputV1: Codable, Equatable, Sendable {
    let name: String
    let startsOn: String
    let endsOn: String
    let timezone: String
    let enabledFormats: [TournamentFormat]
    let primaryFormat: TournamentFormat
    let scoringMode: ScoringMode
    let captainDisplayName: String
    let captainHandicap: Double?
}

struct CreateNativeTripResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let publicId: String
    let status: TripLifecycle
    let scoreRevision: Int
}

struct UpdateNativeTripInputV1: Codable, Equatable, Sendable {
    let name: String?
    let startsOn: String?
    let endsOn: String?
    let timezone: String?
    let enabledFormats: [TournamentFormat]?
    let primaryFormat: TournamentFormat?
    let scoringMode: ScoringMode?

    init(
        name: String? = nil,
        startsOn: String? = nil,
        endsOn: String? = nil,
        timezone: String? = nil,
        enabledFormats: [TournamentFormat]? = nil,
        primaryFormat: TournamentFormat? = nil,
        scoringMode: ScoringMode? = nil
    ) {
        self.name = name
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.timezone = timezone
        self.enabledFormats = enabledFormats
        self.primaryFormat = primaryFormat
        self.scoringMode = scoringMode
    }
}

struct UpdateNativeTripResultV1: Codable, Equatable, Sendable {
    let tripId: String
    let status: TripLifecycle
    let updatedAt: Date
}

struct CreateCourseCardHoleInputV1: Codable, Equatable, Hashable, Sendable {
    let holeNumber: Int
    let par: Int
    let strokeIndex: Int?
    let yards: Int?
}

struct CreateCourseCardInputV1: Codable, Equatable, Sendable {
    let name: String
    let courseName: String
    let holes: [CreateCourseCardHoleInputV1]
}

struct CreateCourseCardResultV1: Codable, Equatable, Sendable {
    let courseCardId: String
    let holeCount: Int
    let updatedAt: Date
}

struct UpdateCourseCardInputV1: Codable, Equatable, Sendable {
    let name: String
    let courseName: String
    let holes: [CreateCourseCardHoleInputV1]
}

struct UpdateCourseCardResultV1: Codable, Equatable, Identifiable, Sendable {
    var id: String { courseCardId }
    let courseCardId: String
    let name: String
    let courseName: String
    let holeCount: Int
    let createdAt: Date
    let updatedAt: Date
    let holes: [CreateCourseCardHoleInputV1]

    private enum CodingKeys: String, CodingKey {
        case courseCardId = "id"
        case name, courseName, holeCount, createdAt, updatedAt, holes
    }
}

struct NativeCourseCardV1: Codable, Equatable, Identifiable, Sendable {
    var id: String { courseCardId }
    let courseCardId: String
    let name: String
    let courseName: String
    let holeCount: Int
    let createdAt: Date
    let updatedAt: Date
    let holes: [CreateCourseCardHoleInputV1]

    private enum CodingKeys: String, CodingKey {
        case courseCardId = "id"
        case name, courseName, holeCount, createdAt, updatedAt, holes
    }
}

/// The signed-in account's identity. Both fields are optional because a
/// native-only signup has no `public.profiles` row until it saves one, and the
/// client treats "either is missing" as still needing setup.
struct NativeProfileV1: Codable, Equatable, Sendable {
    let userId: String
    let fullName: String?
    let username: String?

    var isComplete: Bool {
        (fullName?.isEmpty == false) && (username?.isEmpty == false)
    }
}

struct AddTripPlayerInputV1: Codable, Equatable, Sendable {
    let displayName: String
    let role: TripPlayerRole
    let rsvp: NativeRSVPStatus
    let handicap: Double?
}

struct AddTripPlayerResultV1: Codable, Equatable, Hashable, Sendable {
    let tripPlayerId: String
    let displayName: String
    let claimed: Bool
}

struct CreateTripRoundInputV1: Codable, Equatable, Sendable {
    let courseCardId: String
    let teeTime: Date
    let walkRide: String
}

struct CreateTripRoundResultV1: Codable, Equatable, Hashable, Sendable {
    let roundId: String
    let publicId: String
    let tripOrder: Int
    let status: RoundLifecycle
}

enum NullableFieldPatchV1<Value: Codable & Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case clear
    case set(Value)
}

struct UpdateTripRoundInputV1: Codable, Equatable, Sendable {
    let courseCardId: String?
    let teeTime: NullableFieldPatchV1<Date>
    let walkRide: NullableFieldPatchV1<String>
    let tripOrder: Int?

    init(
        courseCardId: String? = nil,
        teeTime: NullableFieldPatchV1<Date> = .unchanged,
        walkRide: NullableFieldPatchV1<String> = .unchanged,
        tripOrder: Int? = nil
    ) {
        self.courseCardId = courseCardId
        self.teeTime = teeTime
        self.walkRide = walkRide
        self.tripOrder = tripOrder
    }

    private enum CodingKeys: String, CodingKey {
        case courseCardId, teeTime, walkRide, tripOrder
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        courseCardId = try container.decodeIfPresent(String.self, forKey: .courseCardId)
        tripOrder = try container.decodeIfPresent(Int.self, forKey: .tripOrder)
        teeTime = try Self.decodePatch(Date.self, key: .teeTime, from: container)
        walkRide = try Self.decodePatch(String.self, key: .walkRide, from: container)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(courseCardId, forKey: .courseCardId)
        try container.encodeIfPresent(tripOrder, forKey: .tripOrder)
        try Self.encodePatch(teeTime, key: .teeTime, to: &container)
        try Self.encodePatch(walkRide, key: .walkRide, to: &container)
    }

    private static func decodePatch<Value: Codable & Equatable & Sendable>(
        _ type: Value.Type,
        key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> NullableFieldPatchV1<Value> {
        guard container.contains(key) else { return .unchanged }
        if try container.decodeNil(forKey: key) { return .clear }
        return .set(try container.decode(type, forKey: key))
    }

    private static func encodePatch<Value: Codable & Equatable & Sendable>(
        _ patch: NullableFieldPatchV1<Value>,
        key: CodingKeys,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch patch {
        case .unchanged:
            break
        case .clear:
            try container.encodeNil(forKey: key)
        case let .set(value):
            try container.encode(value, forKey: key)
        }
    }
}

struct UpdateTripRoundResultV1: Codable, Equatable, Sendable {
    let tripId: String
    let roundId: String
    let publicId: String
    let tripOrder: Int
    let status: RoundLifecycle
    let courseName: String
    let teeTime: Date?
    let holeCount: Int
    let walkRide: String?
    let nativeUpdatedAt: Date
}

struct DeleteTripRoundResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let roundId: String
    let deleted: Bool
    let remainingRoundCount: Int
}

enum RoundParticipationStatusV1: String, Codable, CaseIterable, Hashable, Sendable {
    case active
    case withdrawn
}

struct SetRoundParticipationResultV1: Codable, Equatable, Hashable, Sendable {
    let roundId: String
    let tripPlayerId: String
    let status: RoundParticipationStatusV1
}

struct TripPlayerClaimResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let tripPlayerId: String
    let displayName: String?
    let claimed: Bool
}

struct DeclineTripSeatResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let tripPlayerId: String
    let rsvp: NativeRSVPStatus
    let claimed: Bool
}

enum HandicapPatchV1: Equatable, Sendable {
    case unchanged
    case clear
    case set(Double)
}

struct UpdateTripPlayerInputV1: Encodable, Equatable, Sendable {
    let displayName: String?
    let role: TripPlayerRole?
    let rsvp: NativeRSVPStatus?
    let handicap: HandicapPatchV1

    init(
        displayName: String? = nil,
        role: TripPlayerRole? = nil,
        rsvp: NativeRSVPStatus? = nil,
        handicap: HandicapPatchV1 = .unchanged
    ) {
        self.displayName = displayName
        self.role = role
        self.rsvp = rsvp
        self.handicap = handicap
    }

    private enum CodingKeys: String, CodingKey { case displayName, role, rsvp, handicap }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(rsvp, forKey: .rsvp)
        switch handicap {
        case .unchanged:
            break
        case .clear:
            try container.encodeNil(forKey: .handicap)
        case let .set(value):
            try container.encode(value, forKey: .handicap)
        }
    }
}

struct UpdateTripPlayerResultV1: Codable, Equatable, Sendable {
    let tripPlayerId: String
    let displayName: String
    let role: TripPlayerRole
    let rsvp: NativeRSVPStatus
    let handicapSnapshot: Double?
}

struct DeleteTripPlayerResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let tripPlayerId: String
    let deleted: Bool
    let remainingPlayerCount: Int
    let scoreRevision: Int
}

struct TripLifecycleResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let status: TripLifecycle
    let scoreRevision: Int
}

struct RoundLifecycleResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let roundId: String
    let status: RoundLifecycle
    let scoreRevision: Int
}

struct StartTripResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let tripStatus: TripLifecycle
    let currentRoundId: String
    let currentRoundStatus: RoundLifecycle
    let scoreRevision: Int
}

struct AdvanceTripRoundResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let tripStatus: TripLifecycle
    let currentRoundId: String
    let currentRoundStatus: RoundLifecycle
    let nextRoundId: String?
    let nextRoundStatus: RoundLifecycle?
    let scoreRevision: Int
}

struct TransferTripOwnershipResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let newOwnerTripPlayerId: String
}

struct OwnedTripDeletionBlockerV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { tripId }
    let tripId: String
    let name: String
    let status: TripLifecycle
}

struct AccountDeletionBlockersV1: Codable, Equatable, Sendable {
    let canDelete: Bool
    let ownedTrips: [OwnedTripDeletionBlockerV1]
}

struct AccountDeletionResultV1: Codable, Equatable, Hashable, Sendable {
    let deleted: Bool
}

struct PublicPreviewRoundV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { publicId }
    let publicId: String
    let courseName: String
    let teeTime: Date?
    let holeCount: Int
    let status: RoundLifecycle
}

struct PublicTripPreviewV1: Codable, Equatable, Sendable {
    let publicId: String
    let name: String
    let startsOn: String
    let endsOn: String
    let timezone: String
    let status: TripLifecycle
    let enabledFormats: [TournamentFormat]
    let primaryFormat: TournamentFormat
    let scoringMode: ScoringMode
    let scoreRevision: Int
    let rosterCount: Int
    let rounds: [PublicPreviewRoundV1]
}

struct InvitePreviewPayloadV1: Codable, Equatable, Sendable {
    let trip: PublicTripPreviewV1
    let snapshot: LeaderboardSnapshotV1?
}

struct InviteAcceptanceTripV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let publicId: String
    let name: String
    let status: TripLifecycle
    let startsOn: String
    let endsOn: String
}

struct OpenInviteSeatV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { tripPlayerId }
    let tripPlayerId: String
    let displayName: String
    let role: TripPlayerRole
}

/// The first invite call discovers privacy-safe open seats; a second call with
/// a selected seat atomically accepts and returns the member bootstrap.
struct InviteAcceptanceResultV1: Codable, Equatable, Sendable {
    let accepted: Bool
    let trip: InviteAcceptanceTripV1?
    let openSeats: [OpenInviteSeatV1]?
    let tripId: String?
    let tripPlayerId: String?
    let bootstrap: NativeTripBootstrapV1?
}

enum TeeCircleRepositoryError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case unsupportedSchemaVersion(Int)
    case malformedEnvelope
    case server(APIErrorPayload)
    case transport(TeeCircleAPIClientError)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "TeeCircle's server configuration is missing."
        case let .unsupportedSchemaVersion(version):
            "The server returned unsupported schema version \(version)."
        case .malformedEnvelope:
            "The server returned an incomplete response."
        case let .server(error):
            error.message
        case let .transport(error):
            error.localizedDescription
        }
    }
}
