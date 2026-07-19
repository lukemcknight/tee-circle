import Foundation
import Security
import TeeCircleAPI
import TeeCircleDomain

@MainActor
final class MessagesSharedStore {
    /// Stable integration names used by both the main app and Messages extension.
    static let credentialService = "com.teecircle.app.extension-session.v1"
    static let deviceIdentifierKey = "teecircle.device.id.v1"
    static let pendingScoresKey = "teecircle.messages.pending-scores.v1"
    static let cacheFileName = "messages-trips-v1.json"

    private let configuration: MessagesConfiguration
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(
        configuration: MessagesConfiguration = .current,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.defaults = UserDefaults(suiteName: configuration.appGroupIdentifier) ?? .standard
        self.fileManager = fileManager
    }

    var deviceIdentifier: String? {
        defaults.string(forKey: Self.deviceIdentifierKey)
    }

    func loadTrips() -> [CachedMessagesTripV1] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let cache = try? TeeCircleJSON.makeDecoder().decode(MessagesTripCacheV1.self, from: data),
              cache.schemaVersion == 1
        else {
            #if DEBUG
            return [MessagesFixtures.trip]
            #else
            return []
            #endif
        }
        return cache.trips
            .filter { $0.schemaVersion == 1 }
            .sorted { lhs, rhs in
                if lhs.trip.lifecycle == rhs.trip.lifecycle {
                    return lhs.trip.name.localizedCaseInsensitiveCompare(rhs.trip.name) == .orderedAscending
                }
                return lifecycleOrder(lhs.trip.lifecycle) < lifecycleOrder(rhs.trip.lifecycle)
            }
    }

    func saveTrips(_ trips: [CachedMessagesTripV1]) {
        guard let url = cacheURL,
              let data = try? TeeCircleJSON.makeEncoder().encode(
                MessagesTripCacheV1(schemaVersion: 1, trips: trips)
              )
        else { return }

        do {
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            // A stale cache is preferable to making the Messages composer unusable.
        }
    }

    func loadCredentials() -> [String: ExtensionSessionCredentialV1] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.credentialService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        if let accessGroup = configuration.keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return [:] }

        let dictionaries: [[String: Any]]
        if let values = item as? [[String: Any]] {
            dictionaries = values
        } else if let value = item as? [String: Any] {
            dictionaries = [value]
        } else {
            return [:]
        }

        return dictionaries.reduce(into: [:]) { result, dictionary in
            guard let data = dictionary[kSecValueData as String] as? Data,
                  let credential = try? TeeCircleJSON.makeDecoder().decode(
                    ExtensionSessionCredentialV1.self,
                    from: data
                  ),
                  credential.isStructurallyValid
            else { return }
            result[credential.tripId] = credential
        }
    }

    func pendingInput(for trip: CachedMessagesTripV1) -> PendingHoleInputV1? {
        guard let data = defaults.data(forKey: Self.pendingScoresKey),
              let inputs = try? TeeCircleJSON.makeDecoder().decode(
                [String: PendingHoleInputV1].self,
                from: data
              ),
              let input = inputs[trip.id],
              input.roundId == trip.scoringRoundId,
              input.tripPlayerId == trip.claimedPlayer?.id
        else { return nil }
        return input
    }

    func savePendingInput(_ input: PendingHoleInputV1) {
        var inputs = allPendingInputs()
        inputs[input.tripId] = input
        persistPendingInputs(inputs)
    }

    func clearPendingInput(tripId: String) {
        var inputs = allPendingInputs()
        inputs.removeValue(forKey: tripId)
        persistPendingInputs(inputs)
    }

    private var cacheURL: URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: configuration.appGroupIdentifier
        ) else { return nil }
        return container.appendingPathComponent(Self.cacheFileName, isDirectory: false)
    }

    private func allPendingInputs() -> [String: PendingHoleInputV1] {
        guard let data = defaults.data(forKey: Self.pendingScoresKey),
              let inputs = try? TeeCircleJSON.makeDecoder().decode(
                [String: PendingHoleInputV1].self,
                from: data
              )
        else { return [:] }
        return inputs
    }

    private func persistPendingInputs(_ inputs: [String: PendingHoleInputV1]) {
        if inputs.isEmpty {
            defaults.removeObject(forKey: Self.pendingScoresKey)
        } else if let data = try? TeeCircleJSON.makeEncoder().encode(inputs) {
            defaults.set(data, forKey: Self.pendingScoresKey)
        }
    }

    private func lifecycleOrder(_ lifecycle: TripLifecycle) -> Int {
        switch lifecycle {
        case .live: 0
        case .ready: 1
        case .draft: 2
        case .completed: 3
        case .archived: 4
        }
    }
}
