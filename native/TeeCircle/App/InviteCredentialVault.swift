import Foundation

/// Plain invite tokens are only returned once by the server. The captain keeps
/// that one-time credential in the device Keychain so links can be re-shared or
/// revoked after an app relaunch without asking the backend to reveal a token.
actor InviteCredentialVault {
    private let keychain = SecureKeychainStore(
        service: "com.teecircle.app.invite-credentials.v1",
        accessGroup: nil
    )
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func save(_ credential: TripInviteCredentialV1, tripID: String) throws {
        try keychain.set(encoder.encode(credential), account: tripID)
    }

    func credential(for tripID: String) throws -> TripInviteCredentialV1? {
        guard let data = try keychain.data(account: tripID) else { return nil }
        return try decoder.decode(TripInviteCredentialV1.self, from: data)
    }

    func remove(tripID: String) throws {
        try keychain.remove(account: tripID)
    }
}
