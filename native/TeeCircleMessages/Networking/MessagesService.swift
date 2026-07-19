import Foundation
import TeeCircleAPI
import TeeCircleDomain

struct MessagesService: Sendable {
    private let baseURL: URL
    private let publishableKey: String?

    init?(configuration: MessagesConfiguration = .current) {
        guard let baseURL = configuration.functionsURL else { return nil }
        self.baseURL = baseURL
        self.publishableKey = configuration.supabasePublishableKey
    }

    func bootstrap(
        tripId: String,
        credential: ExtensionSessionCredentialV1
    ) async throws -> MessagesBootstrapPayloadV1 {
        let client = makeClient(token: credential.sessionToken)
        let request = try APIRequest<APIEnvelope<MessagesBootstrapPayloadV1>>.json(
            method: .post,
            path: "/messages-bootstrap-v1",
            headers: headers,
            body: MessagesBootstrapRequestV1(tripId: tripId)
        )
        return try await client.sendEnvelope(request)
    }

    func recordScore(
        _ command: ExtensionScoreCommandV1,
        credential: ExtensionSessionCredentialV1
    ) async throws -> ScoreHoleResultV1 {
        let client = makeClient(token: credential.sessionToken)
        let request = try APIRequest<APIEnvelope<ScoreHoleResultV1>>.json(
            method: .post,
            path: "/score-trip-hole-v1",
            headers: headers,
            body: command,
            idempotencyKey: command.idempotencyKey
        )
        return try await client.sendEnvelope(request)
    }

    private var headers: [String: String] {
        guard let publishableKey, !publishableKey.isEmpty else { return [:] }
        return ["apikey": publishableKey]
    }

    private func makeClient(token: String) -> TeeCircleAPIClient {
        TeeCircleAPIClient(
            baseURL: baseURL,
            tokenProvider: StaticBearerTokenProvider(token: token),
            configuration: APIClientConfiguration(timeout: 15, maxResponseBytes: 512_000)
        )
    }
}
