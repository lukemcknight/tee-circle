import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct APIRequest<Response: Decodable & Sendable>: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let queryItems: [URLQueryItem]
    public let headers: [String: String]
    public let body: Data?
    public let requiresAuthentication: Bool
    public let requestId: String
    public let idempotencyKey: String?

    public init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        requestId: String = UUID().uuidString,
        idempotencyKey: String? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.requestId = requestId
        self.idempotencyKey = idempotencyKey
    }

    public static func json<Body: Encodable & Sendable>(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Body,
        requiresAuthentication: Bool = true,
        requestId: String = UUID().uuidString,
        idempotencyKey: String? = nil
    ) throws -> Self {
        try Self.init(
            method: method,
            path: path,
            queryItems: queryItems,
            headers: headers.merging(["Content-Type": "application/json"], uniquingKeysWith: { current, _ in current }),
            body: TeeCircleJSON.makeEncoder().encode(body),
            requiresAuthentication: requiresAuthentication,
            requestId: requestId,
            idempotencyKey: idempotencyKey
        )
    }
}
