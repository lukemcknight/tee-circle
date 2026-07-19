import Foundation

/// All server route assumptions live here. RPC names mirror the additive v1
/// migration; the purchase claim is an Edge Function because verification uses
/// RevenueCat server credentials that must never be shipped in the app.
enum TeeCircleEndpointCatalog {
    static let createTrip = rpc("create_trip_v1")
    static let updateTrip = rpc("update_trip_v1")
    static let createCourseCard = rpc("create_course_card_v1")
    static let updateCourseCard = rpc("update_course_card_v1")
    static let courseCards = rpc("get_course_cards_v1")
    static let addTripPlayer = rpc("add_trip_player_v1")
    static let createTripRound = rpc("create_trip_round_v1")
    static let updateTripRound = rpc("update_trip_round_v1")
    static let deleteTripRound = rpc("delete_trip_round_v1")
    static let setRoundParticipation = rpc("set_round_participation_v1")
    static let releaseTripPlayer = rpc("release_trip_player_claim_v1")
    static let updateTripPlayer = rpc("update_trip_player_v1")
    static let deleteTripPlayer = rpc("delete_trip_player_v1")
    static let setTripStatus = rpc("set_trip_status_v1")
    static let setTripRoundStatus = rpc("set_trip_round_status_v1")
    static let startTrip = rpc("start_trip_v1")
    static let advanceTripRound = rpc("advance_trip_round_v1")
    static let transferTripOwnership = rpc("transfer_trip_ownership_v1")
    static let accountDeletionBlockers = rpc("get_account_deletion_blockers_v1")
    static let acceptTripInvite = rpc("accept_trip_invite_v1")
    static let myProfile = rpc("get_my_profile_v1")
    static let updateMyProfile = rpc("update_my_profile_v1")
    static let myTrips = rpc("get_my_trips_v1")
    static let tripBootstrap = rpc("get_trip_bootstrap_v1")
    static let legacyRounds = rpc("get_legacy_rounds_v1")
    static let convertLegacyRound = rpc("convert_legacy_round_v1")
    static let recordHoleScore = "/functions/v1/record-score-v1"
    static let createInvite = rpc("create_trip_invite_v1")
    static let listInvites = rpc("list_trip_invites_v1")
    static let rotateInvite = rpc("rotate_trip_invite_v1")
    static let revokeInvite = rpc("revoke_trip_invite_v1")
    static let issueExtensionSession = rpc("issue_extension_session_v1")
    static let revokeExtensionSession = rpc("revoke_extension_session_v1")
    static let registerDevicePush = rpc("register_device_push_v1")
    static let unregisterDevicePush = rpc("unregister_device_push_v1")
    static let registerLiveActivity = rpc("register_live_activity_v1")
    static let endLiveActivity = rpc("end_live_activity_v1")
    static let createPurchaseIntent = rpc("create_trip_purchase_intent_v1")
    static let cancelPurchaseIntent = rpc("cancel_trip_purchase_intent_v1")
    static let previewInvite = "/functions/v1/preview-trip-v1"
    static let claimPurchase = "/functions/v1/claim-trip-purchase-v1"

    /// Deliberately explicit until additive backend commands exist. UI must hide
    /// or disable these operations rather than falling back to direct table writes.
    static let unsupportedCapabilities: Set<UnsupportedServerCapability> = [
        .deleteAccount,
    ]

    private static func rpc(_ function: String) -> String {
        "/rest/v1/rpc/\(function)"
    }
}

enum UnsupportedServerCapability: String, CaseIterable, Hashable, Sendable {
    case deleteAccount
}
