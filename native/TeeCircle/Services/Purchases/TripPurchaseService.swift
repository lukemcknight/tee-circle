import Combine
import Foundation
import RevenueCat

struct TripUnlockProduct: Equatable, Sendable {
    let productID: String
    let localizedTitle: String
    let localizedPrice: String
}

enum TripUnlockOutcome: Equatable, Sendable {
    case cancelled(purchaseIntentID: String)
    case pendingServerVerification(
        purchaseIntentID: String,
        transactionID: String,
        productID: String
    )
    case unlocked(PurchaseClaimResultV1)
}

enum TripPurchaseState: Equatable, Sendable {
    case idle
    case loadingProduct
    case ready(TripUnlockProduct)
    case creatingIntent
    case purchasing
    case verifying
    case failed(String)
}

enum TripPurchaseServiceError: LocalizedError, Equatable, Sendable {
    case missingConfiguration
    case productUnavailable(String)
    case productMismatch
    case missingTransaction
    case claimAlreadyInFlight
    case userMismatch
    case cancellationPending

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Purchases are not configured for this build."
        case let .productUnavailable(productID):
            "The App Store product \(productID) is not available."
        case .productMismatch:
            "The server purchase intent does not match this App Store product."
        case .missingTransaction:
            "The App Store completed the purchase without returning a transaction identifier."
        case .claimAlreadyInFlight:
            "This purchase is already being verified."
        case .userMismatch:
            "Sign in with the account that started this purchase to finish verification."
        case .cancellationPending:
            "The App Store purchase was cancelled, but TeeCircle could not release the pending trip yet. Reopen this trip and retry before unlocking another trip."
        }
    }
}

private struct PendingPurchaseClaim: Codable, Equatable, Sendable {
    let userID: String
    let purchaseIntentID: String
    let transactionID: String
    let productID: String
    let createdAt: Date
}

enum TripPurchaseSecureAccount {
    static func claim(for userID: String) -> String {
        "trip-unlock-v1:\(userID.lowercased())"
    }
}

/// RevenueCat coordinates StoreKit, but only the server's verified claim response
/// grants access. This service never synthesizes or caches a local entitlement.
@MainActor
final class TripPurchaseService: ObservableObject {
    @Published private(set) var state: TripPurchaseState = .idle

    private let repository: any TripPurchaseRepositoryProtocol
    private let apiKey: String
    private let configuredProductID: String
    private let claimStore = SecureKeychainStore(
        service: "com.teecircle.app.pending-purchase-claim",
        accessGroup: nil
    )
    private var product: StoreProduct?
    private var inFlightTransactionIDs: Set<String> = []
    private var configuredUserID: String?

    init(
        repository: any TripPurchaseRepositoryProtocol,
        apiKey: String,
        productID: String
    ) {
        self.repository = repository
        self.apiKey = apiKey
        configuredProductID = productID
    }

    func configure(forSupabaseUserID userID: String) async throws {
        configuredUserID = nil
        guard !apiKey.isEmpty, !userID.isEmpty else {
            throw TripPurchaseServiceError.missingConfiguration
        }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif

        if Purchases.isConfigured {
            if Purchases.shared.appUserID != userID {
                _ = try await Purchases.shared.logIn(userID)
            }
        } else {
            Purchases.configure(withAPIKey: apiKey, appUserID: userID)
        }
        configuredUserID = userID
    }

    @discardableResult
    func loadProduct() async throws -> TripUnlockProduct {
        guard Purchases.isConfigured, !configuredProductID.isEmpty else {
            throw TripPurchaseServiceError.missingConfiguration
        }
        state = .loadingProduct
        guard let product = await Purchases.shared.products([configuredProductID]).first else {
            let error = TripPurchaseServiceError.productUnavailable(configuredProductID)
            state = .failed(error.localizedDescription)
            throw error
        }
        self.product = product
        let display = TripUnlockProduct(
            productID: product.productIdentifier,
            localizedTitle: product.localizedTitle,
            localizedPrice: product.localizedPriceString
        )
        state = .ready(display)
        return display
    }

    /// Call only from the captain's explicit purchase button action.
    func purchaseTripUnlock(tripID: String) async throws -> TripUnlockOutcome {
        guard Purchases.isConfigured, let configuredUserID else {
            throw TripPurchaseServiceError.missingConfiguration
        }
        let idempotencyKey = UUID().uuidString.lowercased()
        state = .creatingIntent
        let intent = try await repository.createPurchaseIntent(
            tripID: tripID,
            idempotencyKey: idempotencyKey
        )
        guard intent.productId == configuredProductID else {
            try await cancelOrSurfaceCleanup(intent.purchaseIntentId)
            state = .failed(TripPurchaseServiceError.productMismatch.localizedDescription)
            throw TripPurchaseServiceError.productMismatch
        }

        let storeProduct: StoreProduct
        if let product, product.productIdentifier == intent.productId {
            storeProduct = product
        } else {
            guard let loaded = await Purchases.shared.products([intent.productId]).first else {
                let error = TripPurchaseServiceError.productUnavailable(intent.productId)
                try await cancelOrSurfaceCleanup(intent.purchaseIntentId)
                state = .failed(error.localizedDescription)
                throw error
            }
            product = loaded
            storeProduct = loaded
        }

        state = .purchasing
        let result: PurchaseResultData
        do {
            result = try await Purchases.shared.purchase(product: storeProduct)
        } catch {
            if (error as NSError).code == ErrorCode.purchaseCancelledError.rawValue {
                try await cancelOrSurfaceCleanup(intent.purchaseIntentId)
                state = .ready(productViewModel(storeProduct))
                return .cancelled(purchaseIntentID: intent.purchaseIntentId)
            }
            state = .failed(error.localizedDescription)
            throw error
        }
        if result.userCancelled {
            try await cancelOrSurfaceCleanup(intent.purchaseIntentId)
            state = .ready(productViewModel(storeProduct))
            return .cancelled(purchaseIntentID: intent.purchaseIntentId)
        }
        guard let transaction = result.transaction else {
            state = .failed(TripPurchaseServiceError.missingTransaction.localizedDescription)
            throw TripPurchaseServiceError.missingTransaction
        }

        let pending = PendingPurchaseClaim(
            userID: configuredUserID,
            purchaseIntentID: intent.purchaseIntentId,
            transactionID: transaction.transactionIdentifier,
            productID: transaction.productIdentifier,
            createdAt: Date()
        )
        try persistPendingClaim(pending)
        return await verify(pending)
    }

    /// Retries the small client-to-server handoff after a crash or network loss.
    /// RevenueCat's webhook independently reconciles the same transaction.
    func reconcilePendingClaim() async -> TripUnlockOutcome? {
        guard let pending = try? loadPendingClaim() else { return nil }
        return await verify(pending)
    }

    func clearRevenueCatUser() async {
        if Purchases.isConfigured, !Purchases.shared.isAnonymous {
            _ = try? await Purchases.shared.logOut()
        }
        configuredUserID = nil
        product = nil
        state = .idle
    }

    /// Releases a server intent only while StoreKit has produced no transaction.
    /// A failed cancellation is deliberately surfaced. Otherwise the server's
    /// one-pending-intent invariant could block another trip for 24 hours while
    /// the UI incorrectly reports a clean cancellation.
    @discardableResult
    func cancelUnconsumedIntent(
        _ purchaseIntentID: String
    ) async throws -> PurchaseIntentCancellationResultV1 {
        try await repository.cancelPurchaseIntent(intentID: purchaseIntentID)
    }

    private func cancelOrSurfaceCleanup(_ purchaseIntentID: String) async throws {
        do {
            _ = try await cancelUnconsumedIntent(purchaseIntentID)
        } catch {
            state = .failed(TripPurchaseServiceError.cancellationPending.localizedDescription)
            throw TripPurchaseServiceError.cancellationPending
        }
    }

    private func verify(_ pending: PendingPurchaseClaim) async -> TripUnlockOutcome {
        guard pending.userID == configuredUserID else {
            state = .failed(TripPurchaseServiceError.userMismatch.localizedDescription)
            return .pendingServerVerification(
                purchaseIntentID: pending.purchaseIntentID,
                transactionID: pending.transactionID,
                productID: pending.productID
            )
        }
        guard inFlightTransactionIDs.insert(pending.transactionID).inserted else {
            state = .failed(TripPurchaseServiceError.claimAlreadyInFlight.localizedDescription)
            return .pendingServerVerification(
                purchaseIntentID: pending.purchaseIntentID,
                transactionID: pending.transactionID,
                productID: pending.productID
            )
        }
        defer { inFlightTransactionIDs.remove(pending.transactionID) }
        state = .verifying
        do {
            let claim = try await repository.claimPurchase(
                intentID: pending.purchaseIntentID,
                transactionID: pending.transactionID,
                productID: pending.productID
            )
            // Server verification is the sole point at which the UI may show unlocked.
            guard claim.unlocked else {
                state = .failed("The purchase is still awaiting server verification.")
                return .pendingServerVerification(
                    purchaseIntentID: pending.purchaseIntentID,
                    transactionID: pending.transactionID,
                    productID: pending.productID
                )
            }
            try? claimStore.remove(account: TripPurchaseSecureAccount.claim(for: pending.userID))
            state = product.map { .ready(productViewModel($0)) } ?? .idle
            return .unlocked(claim)
        } catch {
            state = .failed("Purchase received. TeeCircle is confirming it with the server.")
            return .pendingServerVerification(
                purchaseIntentID: pending.purchaseIntentID,
                transactionID: pending.transactionID,
                productID: pending.productID
            )
        }
    }

    private func persistPendingClaim(_ claim: PendingPurchaseClaim) throws {
        guard claim.userID == configuredUserID else {
            throw TripPurchaseServiceError.userMismatch
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try claimStore.set(
            encoder.encode(claim),
            account: TripPurchaseSecureAccount.claim(for: claim.userID)
        )
    }

    private func loadPendingClaim() throws -> PendingPurchaseClaim? {
        guard let configuredUserID,
              let data = try claimStore.data(
                account: TripPurchaseSecureAccount.claim(for: configuredUserID)
              )
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let claim = try decoder.decode(PendingPurchaseClaim.self, from: data)
        guard claim.userID == configuredUserID else {
            throw TripPurchaseServiceError.userMismatch
        }
        return claim
    }

    private func productViewModel(_ product: StoreProduct) -> TripUnlockProduct {
        TripUnlockProduct(
            productID: product.productIdentifier,
            localizedTitle: product.localizedTitle,
            localizedPrice: product.localizedPriceString
        )
    }
}
