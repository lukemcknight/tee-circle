import Foundation
import TeeCircleDomain

public protocol BearerTokenProviding: Sendable {
    func bearerToken() async throws -> String?
}

public struct StaticBearerTokenProvider: BearerTokenProviding {
    private let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func bearerToken() async throws -> String? {
        token
    }
}

public struct APIClientConfiguration: Equatable, Hashable, Sendable {
    public let timeout: TimeInterval
    public let maxResponseBytes: Int
    public let allowsInsecureLocalhost: Bool

    public init(
        timeout: TimeInterval = 30,
        maxResponseBytes: Int = 2_000_000,
        allowsInsecureLocalhost: Bool = false
    ) {
        precondition(timeout > 0)
        precondition(maxResponseBytes > 0)
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
        self.allowsInsecureLocalhost = allowsInsecureLocalhost
    }
}

public enum TeeCircleAPIClientError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidPath
    case missingBearerToken
    case nonHTTPResponse
    case responseTooLarge(limit: Int)
    case unsupportedSchemaVersion(Int)
    case server(statusCode: Int, envelope: APIErrorEnvelope?)
    case decoding(String)
}

extension TeeCircleAPIClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The TeeCircle API base URL is invalid."
        case .invalidPath:
            "The TeeCircle API request path is invalid."
        case .missingBearerToken:
            "Sign in to continue."
        case .nonHTTPResponse:
            "The server returned an invalid response."
        case let .responseTooLarge(limit):
            "The server response exceeded the \(limit)-byte safety limit."
        case let .unsupportedSchemaVersion(version):
            "The server returned unsupported schema version \(version)."
        case let .server(_, envelope):
            envelope?.error.message ?? "The server could not complete the request."
        case let .decoding(message):
            "The server response could not be read: \(message)"
        }
    }
}

/// A small Foundation-only client that is safe to link into app extensions.
public actor TeeCircleAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: (any BearerTokenProviding)?
    private let configuration: APIClientConfiguration

    public init(
        baseURL: URL,
        session: URLSession = TeeCircleAPIClient.makeEphemeralSession(),
        tokenProvider: (any BearerTokenProviding)? = nil,
        configuration: APIClientConfiguration = .init()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.configuration = configuration
    }

    public func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        let url = try makeURL(path: request.path, queryItems: request.queryItems)
        var urlRequest = URLRequest(url: url, timeoutInterval: configuration.timeout)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (name, value) in request.headers {
            guard !Self.reservedHeaders.contains(name.lowercased()) else { continue }
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if request.body != nil, urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        urlRequest.setValue(request.requestId, forHTTPHeaderField: "X-Request-ID")
        if let idempotencyKey = request.idempotencyKey {
            urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        if request.requiresAuthentication {
            guard let token = try await tokenProvider?.bearerToken(), !token.isEmpty else {
                throw TeeCircleAPIClientError.missingBearerToken
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: urlRequest)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw TeeCircleAPIClientError.nonHTTPResponse
        }
        guard data.count <= configuration.maxResponseBytes else {
            throw TeeCircleAPIClientError.responseTooLarge(limit: configuration.maxResponseBytes)
        }

        let decoder = TeeCircleJSON.makeDecoder()
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw TeeCircleAPIClientError.server(statusCode: http.statusCode, envelope: envelope)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw TeeCircleAPIClientError.decoding(String(describing: error))
        }
    }

    public func sendEnvelope<Payload: Codable & Sendable>(
        _ request: APIRequest<APIEnvelope<Payload>>
    ) async throws -> Payload {
        let envelope = try await send(request)
        guard envelope.schemaVersion == APIEnvelope<Payload>.supportedSchemaVersion else {
            throw TeeCircleAPIClientError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return envelope.data
    }

    public static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard let scheme = baseURL.scheme?.lowercased(),
              let host = baseURL.host?.lowercased(),
              scheme == "https" || (
                configuration.allowsInsecureLocalhost
                    && scheme == "http"
                    && Self.localDevelopmentHosts.contains(host)
              )
        else {
            throw TeeCircleAPIClientError.invalidBaseURL
        }
        guard path.hasPrefix("/"),
              !path.contains("?"),
              !path.contains("#"),
              !path.split(separator: "/").contains("..")
        else {
            throw TeeCircleAPIClientError.invalidPath
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw TeeCircleAPIClientError.invalidBaseURL
        }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw TeeCircleAPIClientError.invalidPath
        }
        return url
    }

    private static let reservedHeaders: Set<String> = [
        "authorization",
        "content-length",
        "host",
        "idempotency-key",
        "x-request-id",
    ]

    private static let localDevelopmentHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
}
