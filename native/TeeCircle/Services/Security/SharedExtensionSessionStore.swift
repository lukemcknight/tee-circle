import Foundation
import Security
import TeeCircleAPI
import TeeCircleDomain

enum TeeCircleSharedSecurity {
    static let appGroupIdentifier = "group.com.teecircle.app.shared"
    static let extensionCredentialService = "com.teecircle.app.extension-session.v1"
    static let deviceIdentifierKey = "teecircle.device.id.v1"
    static let messagesCacheFileName = "messages-trips-v1.json"
}

enum SecureStoreError: LocalizedError, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidStoredData
    case appGroupUnavailable
    case expiredCredential
    case deviceMismatch

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "Keychain operation failed (\(status))."
        case .invalidStoredData:
            "The saved Messages connection could not be read."
        case .appGroupUnavailable:
            "The TeeCircle shared app container is unavailable."
        case .expiredCredential:
            "Open TeeCircle to reconnect Messages."
        case .deviceMismatch:
            "This Messages connection belongs to a different device."
        }
    }
}

/// This JSON shape is shared verbatim with the Messages target. There is one
/// generic-password Keychain item per trip, with `tripId` as the item account.
struct ExtensionSessionCredentialV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let tripId: String
    let sessionToken: String
    let deviceId: String
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= Date() }
}

/// This is the exact App Group cache shape consumed by TeeCircleMessages.
/// `scoringRoundHoleCount` was added as an optional field, so v1 caches written
/// by older builds continue to decode.
struct CachedMessagesTripV1: Codable, Equatable, Identifiable, Sendable {
    let schemaVersion: Int
    let trip: Trip
    let inviteToken: String
    let claimedPlayer: TripPlayer?
    let scoringRoundId: String?
    let scoringRoundHoleCount: Int?
    let snapshot: LeaderboardSnapshotV1
    let cachedAt: Date

    var id: String { trip.id }
}

struct MessagesTripCacheV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let trips: [CachedMessagesTripV1]
}

struct SecureKeychainStore: Sendable {
    let service: String
    let accessGroup: String?

    func data(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw SecureStoreError.invalidStoredData }
        return data
    }

    func allItems() throws -> [(account: String, data: Data)] {
        var query = baseQuery(account: nil)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }

        let dictionaries: [[String: Any]]
        if let values = result as? [[String: Any]] {
            dictionaries = values
        } else if let value = result as? [String: Any] {
            dictionaries = [value]
        } else {
            throw SecureStoreError.invalidStoredData
        }
        return try dictionaries.map { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data
            else { throw SecureStoreError.invalidStoredData }
            return (account, data)
        }
    }

    func set(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SecureStoreError.unexpectedStatus(addStatus) }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// Owns the main-app side of the Messages bridge. Session bearer tokens only
/// enter the shared Keychain; the App Group contains display data and invite URLs.
/// Pending score drafts remain extension-owned and are never cleared here.
actor SharedExtensionSessionStore {
    private static let sessionIDsKey = "teecircle.extension.session-ids.v1"

    private let keychain: SecureKeychainStore
    private let appGroupIdentifier: String
    private let defaults: UserDefaults?
    private let fileManager: FileManager

    init(
        appGroupIdentifier: String = TeeCircleSharedSecurity.appGroupIdentifier,
        keychainAccessGroup: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
        defaults = UserDefaults(suiteName: appGroupIdentifier)
        keychain = SecureKeychainStore(
            service: TeeCircleSharedSecurity.extensionCredentialService,
            accessGroup: keychainAccessGroup
        )
    }

    /// Stored in App Group defaults because the extension must bind each
    /// credential to the same installation identifier.
    func stableDeviceID() throws -> String {
        guard let defaults else { throw SecureStoreError.appGroupUnavailable }
        if let identifier = defaults.string(forKey: TeeCircleSharedSecurity.deviceIdentifierKey),
           !identifier.isEmpty {
            return identifier
        }
        let identifier = UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: TeeCircleSharedSecurity.deviceIdentifierKey)
        return identifier
    }

    func save(issue: ExtensionSessionIssueResultV1, deviceID: String) throws {
        guard deviceID == (try stableDeviceID()) else { throw SecureStoreError.deviceMismatch }
        let credential = ExtensionSessionCredentialV1(
            schemaVersion: 1,
            tripId: issue.tripId,
            sessionToken: issue.sessionToken,
            deviceId: deviceID,
            expiresAt: issue.expiresAt
        )
        try keychain.set(
            TeeCircleJSON.makeEncoder().encode(credential),
            account: issue.tripId
        )
        var sessionIDs = try storedSessionIDs()
        sessionIDs[issue.tripId] = issue.sessionId
        try persistSessionIDs(sessionIDs)
    }

    func credential(for tripID: String) throws -> ExtensionSessionCredentialV1? {
        guard let data = try keychain.data(account: tripID) else { return nil }
        let credential = try TeeCircleJSON.makeDecoder().decode(
            ExtensionSessionCredentialV1.self,
            from: data
        )
        guard credential.schemaVersion == 1, credential.tripId == tripID else {
            throw SecureStoreError.invalidStoredData
        }
        guard credential.deviceId == (try stableDeviceID()) else {
            throw SecureStoreError.deviceMismatch
        }
        guard !credential.isExpired else { throw SecureStoreError.expiredCredential }
        return credential
    }

    func credentials() throws -> [String: ExtensionSessionCredentialV1] {
        let deviceID = try stableDeviceID()
        return try keychain.allItems().reduce(into: [:]) { result, item in
            let credential = try TeeCircleJSON.makeDecoder().decode(
                ExtensionSessionCredentialV1.self,
                from: item.data
            )
            guard credential.schemaVersion == 1,
                  credential.tripId == item.account,
                  credential.deviceId == deviceID
            else { throw SecureStoreError.invalidStoredData }
            if !credential.isExpired {
                result[credential.tripId] = credential
            }
        }
    }

    func serverSessionID(for tripID: String) throws -> String? {
        try storedSessionIDs()[tripID]
    }

    /// Call the repository revoke command first when a server session ID exists.
    /// Local removal intentionally leaves any extension-owned unsent score draft.
    func revokeLocally(tripID: String) throws {
        try keychain.remove(account: tripID)
        var sessionIDs = try storedSessionIDs()
        sessionIDs.removeValue(forKey: tripID)
        try persistSessionIDs(sessionIDs)
    }

    func revokeAllLocally() throws {
        for item in try keychain.allItems() {
            try keychain.remove(account: item.account)
        }
        try persistSessionIDs([:])
        try removeMessagesCache()
    }

    func saveTrips(_ trips: [CachedMessagesTripV1]) throws {
        let payload = MessagesTripCacheV1(schemaVersion: 1, trips: trips)
        let data = try TeeCircleJSON.makeEncoder().encode(payload)
        try data.write(
            to: try messagesCacheURL(),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func trips() throws -> [CachedMessagesTripV1] {
        let url = try messagesCacheURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let payload = try TeeCircleJSON.makeDecoder().decode(
            MessagesTripCacheV1.self,
            from: Data(contentsOf: url)
        )
        guard payload.schemaVersion == 1 else { throw SecureStoreError.invalidStoredData }
        return payload.trips.filter { $0.schemaVersion == 1 }
    }

    func removeMessagesCache() throws {
        let url = try messagesCacheURL()
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func storedSessionIDs() throws -> [String: String] {
        guard let defaults else { throw SecureStoreError.appGroupUnavailable }
        guard let data = defaults.data(forKey: Self.sessionIDsKey) else { return [:] }
        return try TeeCircleJSON.makeDecoder().decode([String: String].self, from: data)
    }

    private func persistSessionIDs(_ values: [String: String]) throws {
        guard let defaults else { throw SecureStoreError.appGroupUnavailable }
        if values.isEmpty {
            defaults.removeObject(forKey: Self.sessionIDsKey)
        } else {
            defaults.set(try TeeCircleJSON.makeEncoder().encode(values), forKey: Self.sessionIDsKey)
        }
    }

    private func messagesCacheURL() throws -> URL {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw SecureStoreError.appGroupUnavailable }
        return container.appendingPathComponent(
            TeeCircleSharedSecurity.messagesCacheFileName,
            isDirectory: false
        )
    }
}
