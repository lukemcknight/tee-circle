import Foundation

/// Owns the production-only service graph. Explicit fixture launches never
/// create this graph, which keeps demo state from becoming an accidental
/// entitlement or write path in TestFlight/App Store builds.
@MainActor
final class TeeCircleProductionServices {
    let auth: SupabaseSessionService
    let repository: any TeeCircleRepositoryProtocol
    let sharedStore: SharedExtensionSessionStore
    let purchases: TripPurchaseService
    let liveActivity: TeeCircleLiveActivityService
    let push: APNsRegistrationService
    let analytics: PostHogAnalyticsService
    let pendingScores: PendingScoreQueue
    let invites: InviteCredentialVault
    let realtime: TripRealtimeHintService

    init?(configuration: AppConfiguration) {
        guard !configuration.useMockData,
              let supabaseURL = configuration.supabaseURL,
              !configuration.supabasePublishableKey.isEmpty
        else { return nil }

        let auth = SupabaseSessionService(
            supabaseURL: supabaseURL,
            publishableKey: configuration.supabasePublishableKey
        )
        let repository = TeeCircleRepository(
            supabaseURL: supabaseURL,
            publishableKey: configuration.supabasePublishableKey,
            tokenProvider: auth
        )
        let sharedStore = SharedExtensionSessionStore(
            keychainAccessGroup: configuration.keychainAccessGroup
        )
        let analytics = PostHogAnalyticsService()
        analytics.configure(
            projectToken: configuration.postHogToken,
            host: configuration.postHogHost,
            debug: false
        )

        self.auth = auth
        self.repository = repository
        self.sharedStore = sharedStore
        self.purchases = TripPurchaseService(
            repository: repository,
            apiKey: configuration.revenueCatPublicKey,
            productID: configuration.revenueCatTripProductID
        )
        self.liveActivity = TeeCircleLiveActivityService(
            repository: repository,
            sharedStore: sharedStore
        )
        self.push = APNsRegistrationService(
            repository: repository,
            sharedStore: sharedStore
        )
        self.analytics = analytics
        self.pendingScores = PendingScoreQueue()
        self.invites = InviteCredentialVault()
        self.realtime = TripRealtimeHintService(client: auth.client)
    }
}
