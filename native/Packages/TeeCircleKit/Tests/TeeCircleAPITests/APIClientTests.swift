import Foundation
import XCTest
import TeeCircleAPI
import TeeCircleDomain

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.store.reset()
    }

    func testSendsAuthenticatedVersionedRequestAndDecodesEnvelope() async throws {
        let response = APIEnvelope(requestId: "server-request", data: Probe(value: "ok"))
        MockURLProtocol.store.configure(
            statusCode: 200,
            data: try TeeCircleJSON.makeEncoder().encode(response)
        )
        let client = makeClient(token: "secret-token")
        let request: APIRequest<APIEnvelope<Probe>> = try .json(
            method: .post,
            path: "/v1/trips/trip-1/score",
            queryItems: [URLQueryItem(name: "broadcast", value: "true")],
            body: Probe(value: "input"),
            requestId: "client-request",
            idempotencyKey: "idempotency-1"
        )

        let payload = try await client.sendEnvelope(request)

        XCTAssertEqual(payload, Probe(value: "ok"))
        let sent = try XCTUnwrap(MockURLProtocol.store.lastRequest())
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://api.teecircle.app/base/v1/trips/trip-1/score?broadcast=true")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Request-ID"), "client-request")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Idempotency-Key"), "idempotency-1")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testPublicRequestDoesNotRequireToken() async throws {
        MockURLProtocol.store.configure(statusCode: 200, data: Data(#"{"value":"public"}"#.utf8))
        let client = makeClient(token: nil)
        let request = APIRequest<Probe>(
            method: .get,
            path: "/v1/public/trips/token",
            requiresAuthentication: false
        )

        let response = try await client.send(request)
        XCTAssertEqual(response, Probe(value: "public"))
        XCTAssertNil(MockURLProtocol.store.lastRequest()?.value(forHTTPHeaderField: "Authorization"))
    }

    func testMissingTokenFailsBeforeNetworkRequest() async {
        let client = makeClient(token: nil)
        let request = APIRequest<Probe>(method: .get, path: "/v1/trips")

        do {
            _ = try await client.send(request)
            XCTFail("Expected an authentication failure")
        } catch let error as TeeCircleAPIClientError {
            XCTAssertEqual(error, .missingBearerToken)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertNil(MockURLProtocol.store.lastRequest())
    }

    func testServerConflictPreservesRevisionAndRetryability() async throws {
        let envelope = APIErrorEnvelope(
            requestId: "request-409",
            error: APIErrorPayload(
                code: "score_conflict",
                message: "The score changed on another device.",
                retryable: true,
                currentRevision: 18
            )
        )
        MockURLProtocol.store.configure(
            statusCode: 409,
            data: try JSONEncoder().encode(envelope)
        )
        let client = makeClient(token: "token")

        do {
            _ = try await client.send(APIRequest<Probe>(method: .post, path: "/v1/score"))
            XCTFail("Expected a conflict")
        } catch let error as TeeCircleAPIClientError {
            guard case let .server(statusCode, received) = error else {
                return XCTFail("Unexpected API error: \(error)")
            }
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(received, envelope)
            XCTAssertEqual(received?.error.currentRevision, 18)
            XCTAssertEqual(received?.error.retryable, true)
        }
    }

    func testRejectsUnsafePathAndOversizedResponse() async throws {
        let client = makeClient(token: "token", maxResponseBytes: 4)
        do {
            _ = try await client.send(APIRequest<Probe>(method: .get, path: "/v1/../admin"))
            XCTFail("Expected invalid path")
        } catch let error as TeeCircleAPIClientError {
            XCTAssertEqual(error, .invalidPath)
        }

        MockURLProtocol.store.configure(statusCode: 200, data: Data(#"{"value":"large"}"#.utf8))
        do {
            _ = try await client.send(APIRequest<Probe>(method: .get, path: "/v1/probe"))
            XCTFail("Expected size limit")
        } catch let error as TeeCircleAPIClientError {
            XCTAssertEqual(error, .responseTooLarge(limit: 4))
        }
    }

    func testReservedHeadersCannotBeOverridden() async throws {
        MockURLProtocol.store.configure(statusCode: 200, data: Data(#"{"value":"ok"}"#.utf8))
        let client = makeClient(token: "real")
        let request = APIRequest<Probe>(
            method: .get,
            path: "/v1/probe",
            headers: [
                "Authorization": "Bearer attacker",
                "X-Request-ID": "attacker-request",
            ],
            requestId: "trusted-request"
        )
        _ = try await client.send(request)

        XCTAssertEqual(MockURLProtocol.store.lastRequest()?.value(forHTTPHeaderField: "Authorization"), "Bearer real")
        XCTAssertEqual(MockURLProtocol.store.lastRequest()?.value(forHTTPHeaderField: "X-Request-ID"), "trusted-request")
    }

    func testEnvelopeRejectsUnsupportedSchemaVersion() async throws {
        let response = APIEnvelope(schemaVersion: 2, requestId: "future", data: Probe(value: "ok"))
        MockURLProtocol.store.configure(statusCode: 200, data: try JSONEncoder().encode(response))
        let client = makeClient(token: "token")
        let request = APIRequest<APIEnvelope<Probe>>(method: .get, path: "/v1/probe")

        do {
            _ = try await client.sendEnvelope(request)
            XCTFail("Expected unsupported version")
        } catch let error as TeeCircleAPIClientError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(2))
        }
    }

    func testHTTPIsOnlyAllowedForExplicitLocalDevelopment() async throws {
        MockURLProtocol.store.configure(statusCode: 200, data: Data(#"{"value":"local"}"#.utf8))
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let client = TeeCircleAPIClient(
            baseURL: URL(string: "http://127.0.0.1:54321/functions/v1")!,
            session: URLSession(configuration: sessionConfiguration),
            tokenProvider: StaticBearerTokenProvider(token: "token"),
            configuration: APIClientConfiguration(allowsInsecureLocalhost: true)
        )

        let response = try await client.send(APIRequest<Probe>(method: .get, path: "/trip-bootstrap"))
        XCTAssertEqual(response.value, "local")
    }

    private func makeClient(token: String?, maxResponseBytes: Int = 2_000_000) -> TeeCircleAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return TeeCircleAPIClient(
            baseURL: URL(string: "https://api.teecircle.app/base/")!,
            session: session,
            tokenProvider: StaticBearerTokenProvider(token: token),
            configuration: APIClientConfiguration(maxResponseBytes: maxResponseBytes)
        )
    }
}

private struct Probe: Codable, Equatable, Sendable {
    let value: String
}

private final class MockResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var statusCode = 200
    private var data = Data()
    private var capturedRequest: URLRequest?

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusCode = 200
        data = Data()
        capturedRequest = nil
    }

    func configure(statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        self.data = data
    }

    func response(for request: URLRequest) -> (HTTPURLResponse, Data) {
        lock.lock()
        defer { lock.unlock() }
        capturedRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    func lastRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = MockResponseStore()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (response, data) = Self.store.response(for: request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
