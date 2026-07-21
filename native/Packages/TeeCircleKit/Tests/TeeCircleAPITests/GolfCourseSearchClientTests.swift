import Foundation
import XCTest
import TeeCircleAPI

final class GolfCourseSearchClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlacesMockURLProtocol.store.reset()
    }

    func testAutocompleteSendsSessionRequestAndDecodesPredictions() async throws {
        PlacesMockURLProtocol.store.configure(statusCode: 200, data: Data("""
        {
          "suggestions": [
            {
              "placePrediction": {
                "placeId": "place-1",
                "text": { "text": "Bethpage Black Course" },
                "structuredFormat": {
                  "mainText": { "text": "Bethpage Black Course" },
                  "secondaryText": { "text": "Farmingdale, NY, USA" }
                }
              }
            },
            { "placePrediction": { "placeId": "place-2", "text": { "text": "Bethpage Red" } } },
            {}
          ]
        }
        """.utf8))
        let client = makeClient()

        let predictions = try await client.autocomplete(
            input: "Bethpage",
            sessionToken: "session-token-1"
        )

        XCTAssertEqual(predictions, [
            GolfCoursePrediction(
                placeId: "place-1",
                mainText: "Bethpage Black Course",
                secondaryText: "Farmingdale, NY, USA"
            ),
            GolfCoursePrediction(placeId: "place-2", mainText: "Bethpage Red", secondaryText: ""),
        ])
        let sent = try XCTUnwrap(PlacesMockURLProtocol.store.lastRequest())
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "https://places.googleapis.com/v1/places:autocomplete")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Goog-Api-Key"), "places-test-key")
        XCTAssertEqual(
            sent.value(forHTTPHeaderField: "X-Goog-FieldMask"),
            "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat"
        )
        let body = try XCTUnwrap(PlacesMockURLProtocol.store.lastRequestBody())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["input"] as? String, "Bethpage")
        XCTAssertEqual(object["includedPrimaryTypes"] as? [String], ["golf_course"])
        XCTAssertEqual(object["sessionToken"] as? String, "session-token-1")
        XCTAssertNil(object["locationBias"])
    }

    func testAutocompleteWithBiasEncodesFiftyKilometerCircle() async throws {
        PlacesMockURLProtocol.store.configure(statusCode: 200, data: Data("{}".utf8))
        let client = makeClient()

        _ = try await client.autocomplete(
            input: "Bethpage",
            sessionToken: "session-token-2",
            bias: PlacesLocationBias(latitude: 40.7449, longitude: -73.4515)
        )

        let body = try XCTUnwrap(PlacesMockURLProtocol.store.lastRequestBody())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let bias = try XCTUnwrap(object["locationBias"] as? [String: Any])
        let circle = try XCTUnwrap(bias["circle"] as? [String: Any])
        let center = try XCTUnwrap(circle["center"] as? [String: Any])
        XCTAssertEqual(circle["radius"] as? Double, 50_000)
        XCTAssertEqual(center["latitude"] as? Double, 40.7449)
        XCTAssertEqual(center["longitude"] as? Double, -73.4515)
    }

    func testEmptySuggestionsDecodeToEmptyList() async throws {
        PlacesMockURLProtocol.store.configure(statusCode: 200, data: Data("{}".utf8))
        let client = makeClient()

        let predictions = try await client.autocomplete(
            input: "Nowhere",
            sessionToken: "session-token-3"
        )

        XCTAssertEqual(predictions, [])
    }

    func testHTTPErrorSurfacesStatusCode() async {
        PlacesMockURLProtocol.store.configure(statusCode: 403, data: Data("denied".utf8))
        let client = makeClient()

        do {
            _ = try await client.autocomplete(input: "Bethpage", sessionToken: "session-token-4")
            XCTFail("Expected a server error")
        } catch let error as GolfCourseSearchError {
            XCTAssertEqual(error, .server(statusCode: 403))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledSearchThrowsCancellationError() async {
        PlacesMockURLProtocol.store.configure(
            statusCode: 200,
            data: Data("{}".utf8),
            stallForever: true
        )
        let client = makeClient()

        let task = Task {
            try await client.autocomplete(input: "Bethpage", sessionToken: "session-token-5")
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: the AbortSignal-equivalent contract.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPlaceDetailsSendsSessionAndDecodesCourse() async throws {
        PlacesMockURLProtocol.store.configure(statusCode: 200, data: Data("""
        {
          "id": "place-1",
          "displayName": { "text": "Bethpage Black Course" },
          "formattedAddress": "99 Quaker Meeting House Rd, Farmingdale, NY",
          "location": { "latitude": 40.7449, "longitude": -73.4515 }
        }
        """.utf8))
        let client = makeClient()

        let details = try await client.placeDetails(
            placeId: "place-1",
            sessionToken: "session-token-9"
        )

        XCTAssertEqual(details.placeId, "place-1")
        XCTAssertEqual(details.name, "Bethpage Black Course")
        XCTAssertEqual(details.address, "99 Quaker Meeting House Rd, Farmingdale, NY")
        XCTAssertEqual(details.latitude, 40.7449, accuracy: 0.0001)
        XCTAssertEqual(details.longitude, -73.4515, accuracy: 0.0001)
        let sent = try XCTUnwrap(PlacesMockURLProtocol.store.lastRequest())
        XCTAssertEqual(
            sent.url?.absoluteString,
            "https://places.googleapis.com/v1/places/place-1?sessionToken=session-token-9"
        )
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Goog-Api-Key"), "places-test-key")
        XCTAssertEqual(
            sent.value(forHTTPHeaderField: "X-Goog-FieldMask"),
            "id,displayName,formattedAddress,location"
        )
    }

    private func makeClient() -> GolfCourseSearchClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlacesMockURLProtocol.self]
        return GolfCourseSearchClient(
            apiKey: "places-test-key",
            session: URLSession(configuration: configuration)
        )
    }
}

private final class PlacesMockResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var statusCode = 200
    private var data = Data()
    private var stallForever = false
    private var capturedRequest: URLRequest?

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusCode = 200
        data = Data()
        stallForever = false
        capturedRequest = nil
    }

    func configure(statusCode: Int, data: Data, stallForever: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        self.data = data
        self.stallForever = stallForever
    }

    func response(for request: URLRequest) -> (HTTPURLResponse, Data)? {
        lock.lock()
        defer { lock.unlock() }
        capturedRequest = request
        guard !stallForever else { return nil }
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

    /// URLProtocol exposes bodies as a stream, not `httpBody`.
    func lastRequestBody() -> Data? {
        guard let request = lastRequest() else { return nil }
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class PlacesMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = PlacesMockResponseStore()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (response, data) = Self.store.response(for: request) else {
            return // stallForever: never completes; cancellation tears it down.
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
