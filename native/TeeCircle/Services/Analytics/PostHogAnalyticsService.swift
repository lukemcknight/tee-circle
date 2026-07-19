import Foundation
import PostHog

enum TeeCircleAnalyticsEvent: Sendable {
    case tripCreated(roundCount: Int, playerCount: Int)
    case inviteCreated
    case rosterClaimed
    case scoreAccepted(latencyMilliseconds: Int, offlineRetry: Bool)
    case scoreFailed(code: String, retryable: Bool)
    case messagesPost(kind: String)
    case liveActivityStarted
    case purchaseStarted
    case purchaseCancelled
    case purchaseVerified
    case purchasePendingVerification

    var name: String {
        switch self {
        case .tripCreated: "trip_created"
        case .inviteCreated: "trip_invite_created"
        case .rosterClaimed: "roster_seat_claimed"
        case .scoreAccepted: "score_write_accepted"
        case .scoreFailed: "score_write_failed"
        case .messagesPost: "messages_card_posted"
        case .liveActivityStarted: "live_activity_started"
        case .purchaseStarted: "trip_unlock_started"
        case .purchaseCancelled: "trip_unlock_cancelled"
        case .purchaseVerified: "trip_unlock_verified"
        case .purchasePendingVerification: "trip_unlock_pending_verification"
        }
    }

    /// Deliberately excludes names, emails, invite/session tokens, transaction IDs,
    /// handicaps, scores, and free-form text.
    var properties: [String: Any] {
        switch self {
        case let .tripCreated(roundCount, playerCount):
            ["round_count": roundCount, "player_count": playerCount]
        case let .scoreAccepted(latencyMilliseconds, offlineRetry):
            ["latency_ms": latencyMilliseconds, "offline_retry": offlineRetry]
        case let .scoreFailed(code, retryable):
            ["error_code": code, "retryable": retryable]
        case let .messagesPost(kind):
            ["card_kind": kind]
        default:
            [:]
        }
    }
}

@MainActor
final class PostHogAnalyticsService {
    private(set) var isConfigured = false

    func configure(projectToken: String, host: URL?, debug: Bool = false) {
        guard !isConfigured, !projectToken.isEmpty else { return }
        let config = PostHogConfig(
            projectToken: projectToken,
            host: host?.absoluteString ?? PostHogConfig.defaultHost
        )
        config.captureApplicationLifecycleEvents = true
        // TeeCircle records explicit screen and product events to avoid accidental
        // capture of trip/player labels rendered in the UI hierarchy.
        config.captureScreenViews = false
        config.sendFeatureFlagEvent = true
        config.preloadFeatureFlags = true
        config.debug = debug
        PostHogSDK.shared.setup(config)
        isConfigured = true
    }

    func identify(supabaseUserID: String) {
        guard isConfigured, !supabaseUserID.isEmpty else { return }
        // Supabase UUID only; never attach email, name, handicap, or roster data.
        PostHogSDK.shared.identify(supabaseUserID)
    }

    func capture(_ event: TeeCircleAnalyticsEvent) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    func isFeatureEnabled(_ key: String) -> Bool {
        guard isConfigured else { return false }
        return PostHogSDK.shared.isFeatureEnabled(key)
    }

    func reset() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
    }
}
