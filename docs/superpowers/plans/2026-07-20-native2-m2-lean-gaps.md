# TeeCircle 2.0 Milestone 2 — Lean-Scope Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four remaining lean-debut gaps — golf-course search (ported from the v1 Places integration), real server-side account deletion (the App Review blocker), RSVP decline, and two small cleanups — with every task gated by agent-runnable tests.

**Architecture:** Course search lands as a pure Foundation client in TeeCircleKit's `TeeCircleAPI` target (URLProtocol-tested) with a thin app-side controller that disappears gracefully when no API key is configured. Account deletion is a three-layer change: a SQL finalizer that clears every FK that would block deleting `auth.users`, a `delete-account-v1` edge function that runs the finalizer as the user then deletes the auth user with the service role, and client wiring that removes `.deleteAccount` from the unsupported-capability list. Decline is one new versioned RPC (`decline_trip_seat_v1`, release-claim + `rsvp='no'`) plus a roster affordance. Production application (migrations, function deploy, API key) is batched into a deferred owner checklist — nothing mid-plan blocks on the owner.

**Tech Stack:** Swift 6 / SwiftUI (iOS 16.4+), TeeCircleKit SwiftPM package, XCTest/XCUITest, Supabase Postgres (plpgsql, disposable-fixture SQL suite), Supabase Edge Functions (Deno), XcodeGen.

## Global Constraints

- **Copy rule (owner directive, spec §5):** no user-facing copy may reference internal versioning ("TeeCircle 1.0", "2.0", "legacy") — one continuous app. (Accessibility identifiers and internal symbol names may keep `legacy`.)
- **Kill switches:** `purchases_required` **false** and `live_activity_pushes_enabled` **false** stay as-is; nothing in M2 touches `tee_internal.runtime_flags` (the SQL tests may flip flags inside their own `begin…rollback` transaction only — that is the existing suite convention, not a flag change).
- **Public repo — never commit secrets.** New config keys go in `native/Config/Secrets.xcconfig` (git-ignored via `native/.gitignore`) with matching empty entries in `native/Config/Secrets.example.xcconfig` (tracked).
- All commits on `native-2`. Simulator command pin: `-destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -derivedDataPath native/DerivedData`. Full app-suite command: `xcodebuild -project native/TeeCircle.xcodeproj -scheme TeeCircle -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -derivedDataPath native/DerivedData test` (append `-only-testing:TeeCircleTests` for unit-only runs mid-task).
- **Protected baselines:** app suite 55/55 (42 unit + 13 UI) green; TeeCircleKit `swift test` 32/32; SQL suite `supabase/tests/run-local-v2.sh` green. Any regression blocks the task. (Tasks add tests, so expected counts grow: package 38 after Task 1; unit 44 after Task 2; unit 45 after Task 5; unit 46 after Task 7.)
- The checked-in `native/TeeCircle.xcodeproj` is XcodeGen-generated: any new Swift file in an app target requires `xcodegen generate` (run from `native/`) and committing the regenerated `project.pbxproj`; verify the pbxproj diff is purely additive (`git diff native/TeeCircle.xcodeproj/project.pbxproj | grep -c '^-[^-]'` → `0`). Exception: Task 8 intentionally removes the `GoogleSignInSwift` product, so its diff removes only lines mentioning `GoogleSignInSwift`. Package files under `native/Packages/TeeCircleKit/` do NOT require xcodegen.
- Migrations in this plan are applied to production only by the owner (SQL editor paste — see Deferred Owner Steps). The local suite applies them automatically because `run-local-v2.sh` globs `supabase/migrations/*.sql`.

---

### Task 1: Golf-course search client in TeeCircleKit (Places API New port)

Port of `/Users/lukemck/Development/tee-circle/src/lib/placesApi.ts` (the v1 Expo client): `POST https://places.googleapis.com/v1/places:autocomplete` with `includedPrimaryTypes: ["golf_course"]`, a per-search session token, an optional 50 km location-bias circle, field masks, then a place-details fetch that terminates the billing session. Swift `Task` cancellation replaces `AbortSignal` (URLSession's `URLError.cancelled` is normalized to `CancellationError`).

**Files:**
- Create: `native/Packages/TeeCircleKit/Sources/TeeCircleAPI/GolfCourseSearchClient.swift`
- Test: `native/Packages/TeeCircleKit/Tests/TeeCircleAPITests/GolfCourseSearchClientTests.swift`

**Interfaces:**
- Consumes: `TeeCircleAPIClient.makeEphemeralSession()` (existing `public static` in the same module).
- Produces (Task 2 depends on these exact signatures):
  - `public struct GolfCoursePrediction: Codable, Equatable, Hashable, Identifiable, Sendable { public let placeId: String; public let mainText: String; public let secondaryText: String }` (`id == placeId`)
  - `public struct GolfCoursePlaceDetails: Codable, Equatable, Hashable, Sendable { public let placeId: String; public let name: String; public let address: String; public let latitude: Double; public let longitude: Double }`
  - `public struct PlacesLocationBias: Equatable, Hashable, Sendable { public let latitude: Double; public let longitude: Double }`
  - `public enum GolfCourseSearchError: Error, Equatable, Sendable { case invalidURL, nonHTTPResponse, server(statusCode: Int), decoding(String) }`
  - `public actor GolfCourseSearchClient { public init(apiKey: String, session: URLSession = ...); public static func makeSessionToken() -> String; public func autocomplete(input: String, sessionToken: String, bias: PlacesLocationBias? = nil) async throws -> [GolfCoursePrediction]; public func placeDetails(placeId: String, sessionToken: String) async throws -> GolfCoursePlaceDetails }`

- [ ] **Step 1: Write the failing tests**

Create `native/Packages/TeeCircleKit/Tests/TeeCircleAPITests/GolfCourseSearchClientTests.swift` (its own URLProtocol mock — the one in `APIClientTests.swift` is file-private):

```swift
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
```

- [ ] **Step 2: Run the package tests to verify they fail**

Run: `cd native/Packages/TeeCircleKit && swift test`
Expected: FAIL to compile — `cannot find 'GolfCourseSearchClient' in scope` (and the other new types).

- [ ] **Step 3: Implement the client**

Create `native/Packages/TeeCircleKit/Sources/TeeCircleAPI/GolfCourseSearchClient.swift`:

```swift
import Foundation

public struct GolfCoursePrediction: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { placeId }
    public let placeId: String
    public let mainText: String
    public let secondaryText: String

    public init(placeId: String, mainText: String, secondaryText: String) {
        self.placeId = placeId
        self.mainText = mainText
        self.secondaryText = secondaryText
    }
}

public struct GolfCoursePlaceDetails: Codable, Equatable, Hashable, Sendable {
    public let placeId: String
    public let name: String
    public let address: String
    public let latitude: Double
    public let longitude: Double

    public init(placeId: String, name: String, address: String, latitude: Double, longitude: Double) {
        self.placeId = placeId
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct PlacesLocationBias: Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum GolfCourseSearchError: Error, Equatable, Sendable {
    case invalidURL
    case nonHTTPResponse
    case server(statusCode: Int)
    case decoding(String)
}

/// Foundation-only port of the v1 Expo `src/lib/placesApi.ts` Google Places
/// API (New) client. A session token ties autocomplete keystrokes and the
/// terminating place-details call into one billed session; Swift `Task`
/// cancellation replaces the v1 AbortSignal (URLSession's `.cancelled` is
/// normalized to `CancellationError`).
public actor GolfCourseSearchClient {
    public static let autocompleteURL = URL(string: "https://places.googleapis.com/v1/places:autocomplete")!
    public static let placeDetailsBaseURL = URL(string: "https://places.googleapis.com/v1/places")!

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = TeeCircleAPIClient.makeEphemeralSession()) {
        self.apiKey = apiKey
        self.session = session
    }

    public static func makeSessionToken() -> String {
        UUID().uuidString.lowercased()
    }

    public func autocomplete(
        input: String,
        sessionToken: String,
        bias: PlacesLocationBias? = nil
    ) async throws -> [GolfCoursePrediction] {
        var request = URLRequest(url: Self.autocompleteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.httpBody = try JSONEncoder().encode(AutocompleteRequestBody(
            input: input,
            includedPrimaryTypes: ["golf_course"],
            sessionToken: sessionToken,
            locationBias: bias.map {
                .init(circle: .init(
                    center: .init(latitude: $0.latitude, longitude: $0.longitude),
                    radius: 50_000
                ))
            }
        ))

        let payload: AutocompleteResponseBody = try await send(request)
        return (payload.suggestions ?? []).compactMap { suggestion in
            guard let prediction = suggestion.placePrediction else { return nil }
            return GolfCoursePrediction(
                placeId: prediction.placeId,
                mainText: prediction.structuredFormat?.mainText?.text ?? prediction.text?.text ?? "",
                secondaryText: prediction.structuredFormat?.secondaryText?.text ?? ""
            )
        }
    }

    public func placeDetails(
        placeId: String,
        sessionToken: String
    ) async throws -> GolfCoursePlaceDetails {
        let url = Self.placeDetailsBaseURL.appendingPathComponent(placeId)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GolfCourseSearchError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "sessionToken", value: sessionToken)]
        guard let finalURL = components.url else {
            throw GolfCourseSearchError.invalidURL
        }
        var request = URLRequest(url: finalURL)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("id,displayName,formattedAddress,location", forHTTPHeaderField: "X-Goog-FieldMask")

        let payload: DetailsResponseBody = try await send(request)
        return GolfCoursePlaceDetails(
            placeId: payload.id,
            name: payload.displayName?.text ?? "",
            address: payload.formattedAddress ?? "",
            latitude: payload.location?.latitude ?? 0,
            longitude: payload.location?.longitude ?? 0
        )
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        try Task.checkCancellation()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw GolfCourseSearchError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GolfCourseSearchError.server(statusCode: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GolfCourseSearchError.decoding(String(describing: error))
        }
    }

    private struct AutocompleteRequestBody: Encodable {
        struct Center: Encodable {
            let latitude: Double
            let longitude: Double
        }
        struct Circle: Encodable {
            let center: Center
            let radius: Double
        }
        struct LocationBias: Encodable {
            let circle: Circle
        }
        let input: String
        let includedPrimaryTypes: [String]
        let sessionToken: String
        let locationBias: LocationBias?
    }

    private struct AutocompleteResponseBody: Decodable {
        struct LocalizedText: Decodable { let text: String }
        struct StructuredFormat: Decodable {
            let mainText: LocalizedText?
            let secondaryText: LocalizedText?
        }
        struct PlacePrediction: Decodable {
            let placeId: String
            let text: LocalizedText?
            let structuredFormat: StructuredFormat?
        }
        struct Suggestion: Decodable { let placePrediction: PlacePrediction? }
        let suggestions: [Suggestion]?
    }

    private struct DetailsResponseBody: Decodable {
        struct LocalizedText: Decodable { let text: String }
        struct Location: Decodable {
            let latitude: Double?
            let longitude: Double?
        }
        let id: String
        let displayName: LocalizedText?
        let formattedAddress: String?
        let location: Location?
    }
}
```

- [ ] **Step 4: Run the package tests to verify they pass**

Run: `cd native/Packages/TeeCircleKit && swift test`
Expected: all pass — `Executed 38 tests` (32 baseline + 6 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add native/Packages/TeeCircleKit/Sources/TeeCircleAPI/GolfCourseSearchClient.swift native/Packages/TeeCircleKit/Tests/TeeCircleAPITests/GolfCourseSearchClientTests.swift
git commit -m "Add TeeCircleKit golf-course search client (Places API New port)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Course-search config key + autocomplete UI in both create flows

The app-side adapter. The key rides the existing xcconfig → Info.plist → `AppConfiguration` pattern (`value("TEE…")`). With no key, `CourseSearchController.isEnabled == false` and both create screens keep today's plain free-text behavior — no crash, no error copy, no network. Coordinates are deliberately dropped: the native round-creation RPC (`create_trip_round_v1` — input is `courseCardId`/`teeTime`/`walkRide`) stores no lat/lng, so selecting a suggestion fills the course name only (YAGNI).

**Files:**
- Create: `native/TeeCircle/Features/Shared/CourseSearch.swift`
- Modify: `native/TeeCircle/App/AppConfiguration.swift`
- Modify: `native/project.yml` (Info.plist property)
- Modify: `native/Config/Secrets.example.xcconfig`
- Modify: `native/TeeCircle/Features/Rounds/CreateRoundView.swift`
- Modify: `native/TeeCircle/Features/Trips/CreateTripView.swift`
- Modify: `native/TeeCircleTests/TeeCircleStoreTests.swift` (its `makeStore()` uses `AppConfiguration`'s memberwise init and MUST gain the new field or it stops compiling)
- Test: `native/TeeCircleTests/CourseSearchControllerTests.swift`
- Regenerate: `native/TeeCircle.xcodeproj/project.pbxproj` (xcodegen)

**Interfaces:**
- Consumes (from Task 1): `GolfCourseSearchClient(apiKey:)`, `GolfCourseSearchClient.makeSessionToken()`, `autocomplete(input:sessionToken:bias:)`, `placeDetails(placeId:sessionToken:)`, `GolfCoursePrediction` (`placeId`/`mainText`/`secondaryText`).
- Produces:
  - `AppConfiguration.googlePlacesAPIKey: String` (empty when unconfigured).
  - `@MainActor final class CourseSearchController: ObservableObject` with `var isEnabled: Bool`, `@Published private(set) var suggestions: [GolfCoursePrediction]`, `init(apiKey: String)`, `func update(query: String)`, `func select(_ prediction: GolfCoursePrediction) async -> String`, `func dismiss()`.
  - `struct CourseSearchSuggestionList: View` with `init(controller: CourseSearchController, onSelect: @escaping (GolfCoursePrediction) -> Void)`.

- [ ] **Step 1: Write the failing controller tests**

Create `native/TeeCircleTests/CourseSearchControllerTests.swift`:

```swift
import XCTest
@testable import TeeCircle

@MainActor
final class CourseSearchControllerTests: XCTestCase {
    func testMissingKeyDisablesSearchAndNeverSuggests() {
        let controller = CourseSearchController(apiKey: "   ")

        XCTAssertFalse(controller.isEnabled)
        controller.update(query: "Bethpage Black")
        XCTAssertTrue(controller.suggestions.isEmpty)
    }

    func testShortQueryClearsSuggestionsWithoutSearching() {
        let controller = CourseSearchController(apiKey: "fixture-key")

        XCTAssertTrue(controller.isEnabled)
        controller.update(query: "Be")
        XCTAssertTrue(controller.suggestions.isEmpty)
    }
}
```

- [ ] **Step 2: Config plumbing (key + memberwise-init call sites)**

a) In `native/TeeCircle/App/AppConfiguration.swift` add the stored property after `revenueCatTripProductID`:

```swift
    let revenueCatPublicKey: String
    let revenueCatTripProductID: String
    let googlePlacesAPIKey: String
    let useMockData: Bool
```

and in `load(bundle:)` add the matching argument in the same position:

```swift
            revenueCatPublicKey: value("TEERevenueCatPublicSDKKey"),
            revenueCatTripProductID: value("TEERevenueCatTripProductID"),
            googlePlacesAPIKey: value("TEEGooglePlacesAPIKey"),
            useMockData: shouldUseMockData(configuredValue: value("TEEUseMockData"))
```

b) In `native/TeeCircleTests/TeeCircleStoreTests.swift`, inside `makeStore()`, add the new argument in the same position:

```swift
                revenueCatPublicKey: "",
                revenueCatTripProductID: "com.teecircle.app.trip_unlock_2999",
                googlePlacesAPIKey: "",
                useMockData: true
```

c) In `native/project.yml`, in the `TeeCircle` target's `info.properties`, add directly under `TEERevenueCatTripProductID: $(TEE_REVENUECAT_PRODUCT_ID)`:

```yaml
        TEEGooglePlacesAPIKey: $(TEE_GOOGLE_PLACES_API_KEY)
```

d) In `native/Config/Secrets.example.xcconfig` append:

```
TEE_GOOGLE_PLACES_API_KEY =
```

e) Append the same empty line `TEE_GOOGLE_PLACES_API_KEY =` to the local, untracked `native/Config/Secrets.xcconfig` (owner fills the real key later). Verify `git status --short native/Config/` shows only `Secrets.example.xcconfig` as modified — `Secrets.xcconfig` must NOT appear (it is ignored).

- [ ] **Step 3: Implement the controller + suggestion list**

Create `native/TeeCircle/Features/Shared/CourseSearch.swift`:

```swift
import Foundation
import SwiftUI
import TeeCircleAPI

/// Debounced golf-course autocomplete for course-name fields. When no Places
/// API key is configured the controller stays disabled and the fields keep
/// their plain free-text behavior — no error copy, no network.
@MainActor
final class CourseSearchController: ObservableObject {
    @Published private(set) var suggestions: [GolfCoursePrediction] = []

    private let client: GolfCourseSearchClient?
    private var sessionToken = GolfCourseSearchClient.makeSessionToken()
    private var searchTask: Task<Void, Never>?

    var isEnabled: Bool { client != nil }

    init(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        client = trimmed.isEmpty ? nil : GolfCourseSearchClient(apiKey: trimmed)
    }

    func update(query: String) {
        searchTask?.cancel()
        guard let client else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            suggestions = []
            return
        }
        let token = sessionToken
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let results = (try? await client.autocomplete(input: trimmed, sessionToken: token)) ?? []
            guard !Task.isCancelled else { return }
            self?.suggestions = results
        }
    }

    /// Ends the billing session with the place-details call (the v1 session
    /// economics) and returns the canonical course name for the field.
    func select(_ prediction: GolfCoursePrediction) async -> String {
        searchTask?.cancel()
        suggestions = []
        defer { sessionToken = GolfCourseSearchClient.makeSessionToken() }
        guard let client else { return prediction.mainText }
        let details = try? await client.placeDetails(
            placeId: prediction.placeId,
            sessionToken: sessionToken
        )
        if let name = details?.name, !name.isEmpty { return name }
        return prediction.mainText
    }

    func dismiss() {
        searchTask?.cancel()
        suggestions = []
    }
}

struct CourseSearchSuggestionList: View {
    @ObservedObject var controller: CourseSearchController
    let onSelect: (GolfCoursePrediction) -> Void

    var body: some View {
        if !controller.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(controller.suggestions) { prediction in
                    Button {
                        onSelect(prediction)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prediction.mainText)
                                .font(.subheadline.weight(.bold))
                            if !prediction.secondaryText.isEmpty {
                                Text(prediction.secondaryText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("course.suggestion.\(prediction.placeId)")
                    if prediction.id != controller.suggestions.last?.id { Divider() }
                }
            }
            .background(TeeCircleBrand.raisedCard, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(TeeCircleBrand.hairline)
            }
        }
    }
}
```

- [ ] **Step 4: Regenerate the project and verify the diff is additive**

Run: `cd native && xcodegen generate`
Then: `git diff native/TeeCircle.xcodeproj/project.pbxproj | grep -c '^-[^-]'`
Expected: `0` (purely additive: the two new Swift files only).

- [ ] **Step 5: Run unit tests to verify green**

Run the Global Constraints xcodebuild command with `-only-testing:TeeCircleTests`.
Expected: 44/44 unit tests pass (42 baseline + 2 new).

- [ ] **Step 6: Wire CreateRoundView**

In `native/TeeCircle/Features/Rounds/CreateRoundView.swift`:

a) Add `import TeeCircleAPI` under `import TeeCircleDomain`.

b) Add two properties under `@State private var isCreating = false`:

```swift
    @StateObject private var courseSearch = CourseSearchController(
        apiKey: AppConfiguration.load().googlePlacesAPIKey
    )
    @State private var suppressCourseSearch = false
```

c) In `body`, directly after the existing `.onChange(of: holeCount) { … }` modifier, add:

```swift
        .onChange(of: courseName) { newValue in
            if suppressCourseSearch {
                suppressCourseSearch = false
                return
            }
            guard courseIsFocused else { return }
            courseSearch.update(query: newValue)
        }
        .onChange(of: courseIsFocused) { focused in
            if !focused { courseSearch.dismiss() }
        }
```

d) In `courseSection`, directly after the course-field `HStack`'s closing `.overlay { … }` block (before the `if !store.courseCards.isEmpty {` saved-cards block), add:

```swift
            if courseSearch.isEnabled {
                CourseSearchSuggestionList(controller: courseSearch) { prediction in
                    Task {
                        suppressCourseSearch = true
                        courseName = await courseSearch.select(prediction)
                        selectedCourseCardID = nil
                        courseIsFocused = false
                    }
                }
            }
```

- [ ] **Step 7: Wire CreateTripView**

In `native/TeeCircle/Features/Trips/CreateTripView.swift`:

a) Add `import TeeCircleAPI` under `import TeeCircleDomain`.

b) Add under `@State private var didSeedCaptain = false`:

```swift
    @StateObject private var courseSearch = CourseSearchController(
        apiKey: AppConfiguration.load().googlePlacesAPIKey
    )
    @FocusState private var focusedCourseRoundID: UUID?
```

c) In the `rounds` step's `ForEach($draft.rounds)`, replace:

```swift
                    TextField("Course name", text: $round.courseName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("create.courseName")
```

with:

```swift
                    TextField("Course name", text: $round.courseName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedCourseRoundID, equals: round.id)
                        .accessibilityIdentifier("create.courseName")
                        .onChange(of: round.courseName) { newValue in
                            guard focusedCourseRoundID == round.id else { return }
                            courseSearch.update(query: newValue)
                        }
                    if courseSearch.isEnabled, focusedCourseRoundID == round.id {
                        CourseSearchSuggestionList(controller: courseSearch) { prediction in
                            let roundID = round.id
                            Task {
                                focusedCourseRoundID = nil
                                let name = await courseSearch.select(prediction)
                                if let index = draft.rounds.firstIndex(where: { $0.id == roundID }) {
                                    draft.rounds[index].courseName = name
                                }
                            }
                        }
                    }
```

(Clearing focus before writing the name means the `.onChange` guard blocks a redundant re-search; no suppress flag needed here.)

- [ ] **Step 8: Run the full app suite**

Run the Global Constraints xcodebuild `test` command (full suite).
Expected: 57/57 (44 unit + 13 UI). Fixture/UI-test builds have no Places key, so the search UI never appears and the existing create-flow UI tests are untouched.

- [ ] **Step 9: Commit**

```bash
git add native/TeeCircle/Features/Shared/CourseSearch.swift native/TeeCircle/App/AppConfiguration.swift native/project.yml native/Config/Secrets.example.xcconfig native/TeeCircle/Features/Rounds/CreateRoundView.swift native/TeeCircle/Features/Trips/CreateTripView.swift native/TeeCircleTests/TeeCircleStoreTests.swift native/TeeCircleTests/CourseSearchControllerTests.swift native/TeeCircle.xcodeproj/project.pbxproj
git commit -m "Wire golf-course autocomplete into round and trip course fields

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Owner follow-up (deferred, see Deferred Owner Steps): mint and restrict the iOS Places key, put it in `Secrets.xcconfig`.

---

### Task 3: `finalize_account_deletion_v1` migration + SQL behavior suite

The SQL half of real account deletion. The finalizer re-checks the exact blocker rule `get_account_deletion_blockers_v1` reports (owned trips in `draft`/`ready`/`live` — last live definition in `supabase/migrations/20260718183948_tee_circle_v2_edit_delete_commands.sql:537`), then removes or detaches every row referencing the caller so a follow-up service-role deletion of `auth.users` cannot hit a FK wall. It deliberately does NOT touch `auth.users` — SQL can't; that is Task 4's edge function.

FK reality this ordering answers (verified in `20260718173955_tee_circle_v2_schema.sql` and the legacy baseline contract `20260718173654`):
- RESTRICT to `auth.users`: `trips.owner_id`, `trip_hole_scores.recorded_by_user_id`, `trip_score_audit.actor_user_id`, `trip_invites.created_by`, `trip_purchase_intents.user_id`, `course_cards.owner_id`.
- `rounds.trip_id → trips` is RESTRICT (rounds must be deleted before their trips); `trip_entitlements.purchase_intent_id → trip_purchase_intents` is RESTRICT (entitlements before intents).
- `trip_hole_scores → trip_round_players` is RESTRICT (since 20260718183948), so scores are deleted before rounds cascade participation away.
- `public.rounds.created_by → profiles` is NO ACTION and **nullable**, so surviving native rounds get `created_by = null`; leaving it set would block the `profiles` delete that the auth cascade performs.
- Surviving-group data is reattributed to the trip's current owner (scores a departing scorer typed, invites, purchase intents behind a surviving entitlement) with fresh idempotency keys to dodge the `(user, idempotency_key)` uniques.
- `trip_players.claimed_user_id` is `on delete set null`; the finalizer nulls it explicitly (release semantics — seat, display name, and scores remain the group's data).

**Files:**
- Create: `supabase/migrations/20260720130000_tee_circle_v2_account_deletion_finalizer.sql`
- Test: `supabase/tests/tee_circle_v2_account_finalize_behavior.sql`
- Modify: `supabase/tests/run-local-v2.sh` (register the new test file)
- Modify: `supabase/tests/tee_circle_v2_function_acl_contract.sql` (add the new function to the authenticated ACL list)

**Interfaces:**
- Consumes: `tee_internal.api_success/api_error`, `tee_internal.native_writes_enabled()` (envelope helpers from `20260718183842`).
- Produces: `public.finalize_account_deletion_v1() returns jsonb` — success `data = {"finalized": true, "deletedOwnedTrips": <int>}`; error codes `unauthenticated`, `native_writes_disabled` (retryable), `account_deletion_blocked`. Task 4's edge function calls it as the user.

- [ ] **Step 1: Write the failing behavior test and register it**

Create `supabase/tests/tee_circle_v2_account_finalize_behavior.sql`:

```sql
-- finalize_account_deletion_v1 regression: active ownership fails closed,
-- owned finished trips are fully erased, surviving groups keep their seats,
-- scores, invites and entitlements, and the auth.users row is deletable
-- afterward with no FK wall. Run only against the disposable fixture through
-- run-local-v2.sh.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

insert into auth.users (id) values
  ('81000000-0000-4000-8000-000000000001'),
  ('81000000-0000-4000-8000-000000000002');

insert into public.profiles (id, full_name) values
  ('81000000-0000-4000-8000-000000000001', 'Deleting User'),
  ('81000000-0000-4000-8000-000000000002', 'Surviving Owner');

-- Trip 1: owned + completed (erased entirely). Trip 2: owned by the survivor;
-- the deleting user claimed a seat, created its round (pre-ownership-transfer
-- shape), typed a score, minted the invite, and bought the unlock. Trip 3:
-- owned + live (the active-ownership blocker).
insert into public.trips (id, public_id, owner_id, name, starts_on, ends_on, status) values
  ('82000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000011',
   '81000000-0000-4000-8000-000000000001', 'Finished Owned Trip', '2026-06-01', '2026-06-02', 'completed'),
  ('82000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000012',
   '81000000-0000-4000-8000-000000000002', 'Surviving Trip', '2026-08-01', '2026-08-02', 'live'),
  ('82000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000013',
   '81000000-0000-4000-8000-000000000001', 'Blocking Live Trip', '2026-09-01', '2026-09-02', 'live');

insert into public.trip_players (id, trip_id, claimed_user_id, display_name, role, rsvp) values
  ('83000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'Old Captain', 'captain', 'yes'),
  ('83000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000002', 'Old Guest', 'player', 'yes'),
  ('83000000-0000-4000-8000-000000000003', '82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000002', 'New Captain', 'captain', 'yes'),
  ('83000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', 'Departing Scorer', 'scorer', 'yes'),
  ('83000000-0000-4000-8000-000000000005', '82000000-0000-4000-8000-000000000003', '81000000-0000-4000-8000-000000000001', 'Blocking Captain', 'captain', 'yes');

insert into public.rounds (
  id, course_name, tee_time, holes, walk_ride, status, created_by,
  trip_id, trip_order, public_id, trip_round_status
) values
  ('84000000-0000-4000-8000-000000000001', 'Old Course', '2026-06-01T12:00:00Z', 9, 'ride', 'open',
   '81000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', 1,
   '84000000-0000-4000-8000-000000000011', 'completed'),
  ('84000000-0000-4000-8000-000000000002', 'Surviving Course', '2026-08-01T12:00:00Z', 9, 'ride', 'open',
   '81000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002', 1,
   '84000000-0000-4000-8000-000000000012', 'live');

insert into public.round_holes (round_id, hole_number, par, stroke_index, yards)
select round_id, hole, 4, hole, 300 + hole
from (
  values
    ('84000000-0000-4000-8000-000000000001'::uuid),
    ('84000000-0000-4000-8000-000000000002'::uuid)
) rounds(round_id)
cross join generate_series(1, 9) hole;

insert into public.trip_round_players (round_id, trip_player_id) values
  ('84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000001'),
  ('84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002'),
  ('84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003'),
  ('84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000004');

insert into public.trip_hole_scores (
  id, trip_id, round_id, trip_player_id, hole_number, strokes, penalties,
  recorded_by_user_id, revision, idempotency_key
) values
  ('85000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002',
   1, 5, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000011'),
  ('85000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002',
   '84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003',
   1, 4, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000012');

insert into public.trip_score_audit (
  score_id, trip_id, round_id, trip_player_id, hole_number, strokes,
  penalties, actor_user_id, revision, idempotency_key
) values
  ('85000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001',
   '84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002',
   1, 5, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000013'),
  ('85000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002',
   '84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003',
   1, 4, 0, '81000000-0000-4000-8000-000000000001', 1, '85000000-0000-4000-8000-000000000014');

insert into public.trip_invites (id, trip_id, token_hash, created_by) values
  ('86000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001',
   '\x01'::bytea, '81000000-0000-4000-8000-000000000001'),
  ('86000000-0000-4000-8000-000000000002', '82000000-0000-4000-8000-000000000002',
   '\x02'::bytea, '81000000-0000-4000-8000-000000000001');

insert into public.trip_purchase_intents (
  id, trip_id, user_id, status, revenuecat_transaction_id, verified_at
) values (
  '87000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000001', 'verified', 'txn-surviving-unlock', now()
);

insert into public.trip_entitlements (
  trip_id, purchase_intent_id, product_id, revenuecat_transaction_id, verified_at
) values (
  '82000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000001',
  'com.teecircle.app.trip_unlock_2999', 'txn-surviving-unlock', now()
);

insert into public.trip_leaderboard_snapshots (trip_id, revision, scoring_engine_version, payload)
values ('82000000-0000-4000-8000-000000000001', 1, 'test', '{"schemaVersion": 1}'::jsonb);

insert into public.extension_sessions (
  id, trip_id, user_id, trip_player_id, device_id, token_hash, expires_at
) values (
  '88000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000002',
  '81000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000004',
  'delete-device-1', '\x03'::bytea, now() + interval '1 hour'
);

insert into public.native_device_tokens (user_id, device_id, token, environment, bundle_id)
values ('81000000-0000-4000-8000-000000000001', 'delete-device-1', repeat('ab', 16), 'sandbox', 'com.teecircle.app');

insert into public.live_activity_subscriptions (trip_id, user_id, device_id, activity_id, push_token, environment)
values ('82000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001',
        'delete-device-1', 'activity-1', repeat('cd', 16), 'sandbox');

insert into tee_internal.command_idempotency (user_id, idempotency_key, operation, request_hash, response)
values ('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001',
        'create_trip_v1', '\x00'::bytea, '{}'::jsonb);

insert into public.course_cards (id, owner_id, name, course_name, hole_count)
values ('8a000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001',
        'My Card', 'My Course', 9);
insert into public.course_card_holes (course_card_id, hole_number, par)
select '8a000000-0000-4000-8000-000000000001', hole, 4 from generate_series(1, 9) hole;

insert into public.rounds (id, course_name, tee_time, holes, walk_ride, status, created_by)
values ('8b000000-0000-4000-8000-000000000001', 'Legacy Course', '2026-05-01T12:00:00Z',
        9, 'ride', 'open', '81000000-0000-4000-8000-000000000001');
insert into public.round_responses (round_id, user_id, response)
values ('8b000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'yes')
on conflict (round_id, user_id) do nothing;

select set_config('request.jwt.claim.sub', '81000000-0000-4000-8000-000000000001', true);

-- Active ownership fails closed before any mutation.
do $$
declare result jsonb;
begin
  result := public.finalize_account_deletion_v1();
  if result#>>'{error,code}' <> 'account_deletion_blocked' then
    raise exception 'active owned trip did not block deletion: %', result;
  end if;
  if not exists (select 1 from public.trips where id = '82000000-0000-4000-8000-000000000001')
     or exists (
       select 1 from public.trip_players
       where id = '83000000-0000-4000-8000-000000000004' and claimed_user_id is null
     ) then
    raise exception 'blocked finalize mutated data';
  end if;
end
$$;

update public.trips set status = 'completed'
where id = '82000000-0000-4000-8000-000000000003';

-- The full pass: erase owned trips, detach from the surviving group.
do $$
declare result jsonb;
begin
  result := public.finalize_account_deletion_v1();
  if result#>>'{data,finalized}' <> 'true'
     or (result#>>'{data,deletedOwnedTrips}')::int <> 2 then
    raise exception 'finalize did not succeed: %', result;
  end if;
  if exists (select 1 from public.trips where owner_id = '81000000-0000-4000-8000-000000000001')
     or not exists (select 1 from public.trips where id = '82000000-0000-4000-8000-000000000002') then
    raise exception 'owned-trip erasure/survival invariant failed';
  end if;
  if (select claimed_user_id from public.trip_players where id = '83000000-0000-4000-8000-000000000004') is not null
     or (select display_name from public.trip_players where id = '83000000-0000-4000-8000-000000000004') <> 'Departing Scorer'
     or (select rsvp from public.trip_players where id = '83000000-0000-4000-8000-000000000004') <> 'yes' then
    raise exception 'surviving seat was not released cleanly';
  end if;
  if (select recorded_by_user_id from public.trip_hole_scores where id = '85000000-0000-4000-8000-000000000002')
       <> '81000000-0000-4000-8000-000000000002'
     or (select actor_user_id from public.trip_score_audit where score_id = '85000000-0000-4000-8000-000000000002')
       <> '81000000-0000-4000-8000-000000000002' then
    raise exception 'surviving score/audit were not reattributed to the owner';
  end if;
  if (select created_by from public.rounds where id = '84000000-0000-4000-8000-000000000002') is not null then
    raise exception 'surviving native round kept a deleted author';
  end if;
  if (select created_by from public.trip_invites where id = '86000000-0000-4000-8000-000000000002')
       <> '81000000-0000-4000-8000-000000000002'
     or not exists (select 1 from public.trip_entitlements where trip_id = '82000000-0000-4000-8000-000000000002')
     or (select user_id from public.trip_purchase_intents where id = '87000000-0000-4000-8000-000000000001')
       <> '81000000-0000-4000-8000-000000000002' then
    raise exception 'surviving invite/purchase graph broke';
  end if;
  if exists (select 1 from public.course_cards where owner_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.native_device_tokens where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.extension_sessions where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.live_activity_subscriptions where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from tee_internal.command_idempotency where user_id = '81000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.rounds where id = '8b000000-0000-4000-8000-000000000001')
     or exists (select 1 from public.profiles where id = '81000000-0000-4000-8000-000000000001') then
    raise exception 'personal artifacts survived finalize';
  end if;
end
$$;

-- The whole point: after the SQL pass, the Auth Admin deletion (Task 4's
-- service-role step) cannot hit a foreign-key wall, and the surviving
-- group's data outlives it.
delete from auth.users where id = '81000000-0000-4000-8000-000000000001';

do $$
begin
  if exists (select 1 from auth.users where id = '81000000-0000-4000-8000-000000000001')
     or not exists (select 1 from public.trip_players where id = '83000000-0000-4000-8000-000000000004')
     or not exists (select 1 from public.trip_hole_scores where id = '85000000-0000-4000-8000-000000000002') then
    raise exception 'auth-user deletion failed or nuked surviving group data';
  end if;
end
$$;

rollback;
```

Register it in `supabase/tests/run-local-v2.sh` by adding this line directly after the `tee_circle_v2_edit_delete_behavior.sql` line:

```bash
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_account_finalize_behavior.sql"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `supabase/tests/run-local-v2.sh`
Expected: FAIL in the new file with `function public.finalize_account_deletion_v1() does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260720130000_tee_circle_v2_account_deletion_finalizer.sql`:

```sql
set lock_timeout = '10s';
set statement_timeout = '5min';

-- Native account deletion, SQL half. finalize_account_deletion_v1 re-checks
-- the same blockers get_account_deletion_blockers_v1 reports, then removes or
-- detaches every row that references the caller so a follow-up service-role
-- Auth Admin deletion of auth.users cannot hit a FK wall. It deliberately does
-- NOT touch auth.users: only the delete-account-v1 edge function's
-- service-role client may do that. The legacy public.delete_user_account()
-- keeps failing closed for native members and is not changed here.

create or replace function public.finalize_account_deletion_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_blocker_count integer;
  v_owned_trip_count integer;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;

  -- Serialize a double-tapped delete; the second call finds nothing to do.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':finalize_account_deletion_v1', 0));

  select count(*) into v_blocker_count
  from public.trips t
  where t.owner_id = v_user_id and t.status in ('draft', 'ready', 'live');
  if v_blocker_count > 0 then
    return tee_internal.api_error(
      v_request_id,
      'account_deletion_blocked',
      'Transfer or archive your active trips before deleting your account.'
    );
  end if;

  select count(*) into v_owned_trip_count
  from public.trips t where t.owner_id = v_user_id;

  -- 1) Owned completed/archived trips: clear restrict-protected satellites in
  --    dependency order, then the trips themselves.
  delete from public.trip_score_audit a
  using public.trips t
  where t.owner_id = v_user_id and a.trip_id = t.id;

  delete from public.trip_hole_scores s
  using public.trips t
  where t.owner_id = v_user_id and s.trip_id = t.id;

  delete from public.trip_entitlements te
  using public.trips t
  where t.owner_id = v_user_id and te.trip_id = t.id;

  delete from public.trip_purchase_intents pi
  using public.trips t
  where t.owner_id = v_user_id and pi.trip_id = t.id;

  delete from public.trip_invites i
  using public.trips t
  where t.owner_id = v_user_id and i.trip_id = t.id;

  delete from public.extension_sessions es
  using public.trips t
  where t.owner_id = v_user_id and es.trip_id = t.id;

  delete from public.live_activity_subscriptions las
  using public.trips t
  where t.owner_id = v_user_id and las.trip_id = t.id;

  delete from public.trip_leaderboard_snapshots snap
  using public.trips t
  where t.owner_id = v_user_id and snap.trip_id = t.id;

  delete from tee_internal.leaderboard_recompute_jobs j
  using public.trips t
  where t.owner_id = v_user_id and j.trip_id = t.id;

  delete from public.round_responses rr
  using public.rounds r, public.trips t
  where t.owner_id = v_user_id and r.trip_id = t.id and rr.round_id = r.id;

  -- rounds -> trips is on delete restrict; legacy scorecards cascade off
  -- rounds per the audited baseline contract.
  delete from public.rounds r
  using public.trips t
  where t.owner_id = v_user_id and r.trip_id = t.id;

  delete from public.trip_players tp
  using public.trips t
  where t.owner_id = v_user_id and tp.trip_id = t.id;

  delete from public.trips t where t.owner_id = v_user_id;

  -- 2) Seats claimed on surviving trips: release the claim exactly like
  --    release_trip_player_claim_v1. The seat, its display name, and its
  --    scores remain the group's data.
  update public.trip_players tp
  set claimed_user_id = null
  where tp.claimed_user_id = v_user_id;

  -- 3) Reattribute authorship a surviving group still needs (RESTRICT FKs to
  --    auth.users). Fresh idempotency keys dodge the (user, key) uniques.
  update public.trip_hole_scores s
  set recorded_by_user_id = t.owner_id, idempotency_key = gen_random_uuid()
  from public.trips t
  where s.trip_id = t.id and s.recorded_by_user_id = v_user_id;

  update public.trip_score_audit a
  set actor_user_id = t.owner_id, idempotency_key = gen_random_uuid()
  from public.trips t
  where a.trip_id = t.id and a.actor_user_id = v_user_id;

  update public.trip_invites i
  set created_by = t.owner_id
  from public.trips t
  where i.trip_id = t.id and i.created_by = v_user_id;

  update public.trip_purchase_intents pi
  set user_id = t.owner_id
  from public.trips t
  where pi.trip_id = t.id and pi.user_id = v_user_id;

  -- created_by is nullable and references profiles with NO ACTION; leaving it
  -- set would block the profiles delete below (and the auth cascade later).
  update public.rounds r
  set created_by = null
  where r.created_by = v_user_id and r.trip_id is not null;

  -- 4) Personal artifacts everywhere (course_card_holes cascade off cards).
  delete from public.extension_sessions where user_id = v_user_id;
  delete from public.native_device_tokens where user_id = v_user_id;
  delete from public.live_activity_subscriptions where user_id = v_user_id;
  delete from tee_internal.command_idempotency where user_id = v_user_id;
  delete from public.course_cards where owner_id = v_user_id;

  -- 5) Legacy cleanup: the same statements as public.delete_user_account,
  --    which fails closed for native members and therefore cannot be reused.
  delete from public.friendships where user_low = v_user_id or user_high = v_user_id;
  delete from public.group_members where user_id = v_user_id;
  delete from public.round_responses where user_id = v_user_id;
  if to_regclass('public.push_tokens') is not null then
    delete from public.push_tokens where user_id = v_user_id;
  end if;
  delete from public.rounds where created_by = v_user_id and trip_id is null;
  delete from public.groups where created_by = v_user_id;
  delete from public.profiles where id = v_user_id;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'finalized', true,
    'deletedOwnedTrips', v_owned_trip_count
  ));
end;
$$;

revoke all on function public.finalize_account_deletion_v1() from public;
grant execute on function public.finalize_account_deletion_v1() to authenticated;
```

- [ ] **Step 4: Add the function to the ACL contract**

In `supabase/tests/tee_circle_v2_function_acl_contract.sql`, in `v_expected_authenticated`, insert alphabetically between `'public.end_live_activity_v1(text)',` and `'public.get_account_deletion_blockers_v1()',`:

```sql
    'public.finalize_account_deletion_v1()',
```

- [ ] **Step 5: Run the suite to verify green**

Run: `supabase/tests/run-local-v2.sh`
Expected: every migration applies, every test file passes, final line `TeeCircle v2 local SQL suite passed.`

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260720130000_tee_circle_v2_account_deletion_finalizer.sql supabase/tests/tee_circle_v2_account_finalize_behavior.sql supabase/tests/run-local-v2.sh supabase/tests/tee_circle_v2_function_acl_contract.sql
git commit -m "Add finalize_account_deletion_v1 migration + SQL behavior suite

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Owner follow-up (deferred): apply this migration to production via SQL editor paste.

---

### Task 4: `delete-account-v1` edge function

The auth half. Verifies the caller's JWT (`requireUser`), runs `finalize_account_deletion_v1` **as the user** (user-scoped client so `auth.uid()` semantics match the SQL command's own checks), and only then uses the service-role Auth Admin API to delete the `auth.users` row. The `supabase/functions/delete-account-v1/` directory already exists but is empty (and untracked — git does not track empty directories). Pure logic goes in `_shared/` with a `_test.ts` next to it, per the existing convention (`revenuecat-platform-v1_test.ts` etc. define local `assertEquals` helpers and use `Deno.test`).

**Files:**
- Create: `supabase/functions/_shared/account-deletion-v1.ts`
- Test: `supabase/functions/_shared/account-deletion-v1_test.ts`
- Create: `supabase/functions/delete-account-v1/index.ts`
- Create: `supabase/functions/delete-account-v1/README.md`

**Interfaces:**
- Consumes: `finalize_account_deletion_v1()` envelope (Task 3); `_shared/auth.ts` (`requireUser`, `createUserClient`, `AuthError`); `_shared/admin.ts` (`createAdminClient`); `_shared/api-v1.ts` (`requestId`, `success`, `failure`, `response`, `isObject`, `isApiEnvelope`, `isErrorEnvelope`); `_shared/cors.ts` (`handleOptions`).
- Produces: `POST /functions/v1/delete-account-v1` with body `{"schemaVersion": 1}` → success envelope `data = {"deleted": true}`; SQL error envelopes pass through with mapped statuses; `auth_deletion_incomplete` (503, retryable) when the data pass succeeded but auth deletion failed. Task 5's client calls this. Also `accountDeletionStatusFor(code: string): number` for the handler.

- [ ] **Step 1: Write the failing shared-helper test**

Create `supabase/functions/_shared/account-deletion-v1_test.ts`:

```ts
import { accountDeletionStatusFor } from "./account-deletion-v1.ts";

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("blocked deletions surface as conflicts", () => {
  assertEquals(accountDeletionStatusFor("account_deletion_blocked"), 409);
});

Deno.test("auth and flag failures keep their transport semantics", () => {
  assertEquals(accountDeletionStatusFor("unauthenticated"), 401);
  assertEquals(accountDeletionStatusFor("forbidden"), 403);
  assertEquals(accountDeletionStatusFor("native_writes_disabled"), 503);
  assertEquals(accountDeletionStatusFor("anything_else"), 400);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `deno test supabase/functions/_shared/account-deletion-v1_test.ts`
Expected: FAIL — `Module not found … account-deletion-v1.ts`.

- [ ] **Step 3: Implement the shared helper**

Create `supabase/functions/_shared/account-deletion-v1.ts`:

```ts
// Status mapping for the delete-account-v1 edge command. Kept separate from
// the handler so the contract is unit-testable without Deno.serve.

export function accountDeletionStatusFor(code: string): number {
  if (code === "unauthenticated") return 401;
  if (code === "forbidden") return 403;
  if (code === "account_deletion_blocked") return 409;
  if (code === "native_writes_disabled") return 503;
  return 400;
}
```

- [ ] **Step 4: Run the deno test to verify it passes**

Run: `deno test supabase/functions/_shared/account-deletion-v1_test.ts`
Expected: `ok | 2 passed | 0 failed`.

- [ ] **Step 5: Write the function handler**

Create `supabase/functions/delete-account-v1/index.ts`:

```ts
import { createAdminClient } from "../_shared/admin.ts";
import { accountDeletionStatusFor } from "../_shared/account-deletion-v1.ts";
import {
  failure,
  isApiEnvelope,
  isErrorEnvelope,
  isObject,
  requestId,
  response,
  success,
} from "../_shared/api-v1.ts";
import { AuthError, createUserClient, requireUser } from "../_shared/auth.ts";
import { handleOptions } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  const id = requestId();
  if (req.method !== "POST") {
    return failure(id, 405, "method_not_allowed", "Use POST to delete an account.");
  }

  try {
    const user = await requireUser(req);
    const body: unknown = await req.json().catch(() => null);
    if (!isObject(body) || body.schemaVersion !== 1) {
      return failure(id, 400, "invalid_request", "A schemaVersion 1 body is required.");
    }

    // The destructive data pass runs as the caller so auth.uid() semantics
    // match the SQL command's own checks.
    const supabase = createUserClient(req);
    const { data, error } = await supabase.rpc("finalize_account_deletion_v1");
    if (error) {
      console.error("finalize_account_deletion_v1 failed", {
        requestId: id,
        error: error.message,
      });
      return failure(id, 503, "service_unavailable", "The account could not be deleted.", true);
    }
    if (!isApiEnvelope(data)) {
      return failure(
        id,
        503,
        "invalid_server_response",
        "The account could not be deleted.",
        true,
      );
    }
    if (isErrorEnvelope(data)) {
      return response(data, accountDeletionStatusFor(data.error.code));
    }

    // Only the service role can remove the auth user; SQL cannot.
    const admin = createAdminClient();
    const { error: authError } = await admin.auth.admin.deleteUser(user.id);
    if (authError) {
      console.error("auth user deletion failed", {
        requestId: id,
        error: authError.message,
      });
      return failure(
        id,
        503,
        "auth_deletion_incomplete",
        "Your data was removed, but sign-in cleanup is still finishing. Try again.",
        true,
      );
    }
    return success(id, { deleted: true });
  } catch (error) {
    if (error instanceof AuthError) {
      return failure(id, 401, "unauthenticated", "Sign in is required.");
    }
    console.error("delete-account-v1 failed", { requestId: id, error });
    return failure(id, 500, "internal_error", "The account could not be deleted.", true);
  }
});
```

- [ ] **Step 6: Write the README**

Create `supabase/functions/delete-account-v1/README.md`:

```markdown
# `delete-account-v1`

Authenticated full account deletion. The caller's JWT is verified, then
`finalize_account_deletion_v1()` runs as the user: it re-checks ownership
blockers (active owned trips fail closed with `account_deletion_blocked`),
erases the user's owned finished trips and every personal artifact, and
detaches their contributions from surviving groups (seats released,
scores/invites/purchase intents reattributed to the trip owner). Only after
the data pass succeeds does the service-role Auth Admin API delete the
`auth.users` row — SQL cannot.

If auth deletion fails after the data pass, the endpoint returns retryable
`auth_deletion_incomplete`; replaying the request is safe (the data pass
finds nothing left to do).
```

- [ ] **Step 7: Re-run the deno tests plus a type-check of the handler**

Run: `deno test supabase/functions/_shared/account-deletion-v1_test.ts`
Expected: `ok | 2 passed | 0 failed`.
Run: `deno check supabase/functions/delete-account-v1/index.ts`
Expected: no errors. (If `deno check` needs the network for `npm:@supabase/supabase-js` and the machine is offline, note it in your report and rely on the deployed-function verification in the owner checklist — do not weaken the test step.)

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/_shared/account-deletion-v1.ts supabase/functions/_shared/account-deletion-v1_test.ts supabase/functions/delete-account-v1/index.ts supabase/functions/delete-account-v1/README.md
git commit -m "Add delete-account-v1 edge function with shared status helper

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Owner follow-up (deferred): `supabase functions deploy delete-account-v1` (same routine as the existing functions; JWT verification stays on).

---

### Task 5: Client — real account deletion

Removes `.deleteAccount` from `unsupportedCapabilities`, adds the edge endpoint, and wires ProfileView's existing delete flow to actually delete, then reset all local state. Honest scope note: this closes the server half of v1 defect CODE-17 for ALL users — the old Expo binary still calls the legacy `delete_user_account()` RPC and is unchanged.

**Files:**
- Modify: `native/TeeCircle/Services/API/TeeCircleEndpointCatalog.swift`
- Modify: `native/TeeCircle/Services/API/TeeCircleServiceContracts.swift`
- Modify: `native/TeeCircle/Services/API/TeeCircleRepository.swift`
- Modify: `native/TeeCircle/App/TeeCircleStore+Production.swift`
- Modify: `native/TeeCircle/Features/Account/ProfileView.swift`
- Test: `native/TeeCircleTests/NativeServiceContractTests.swift` (modify existing catalog test + one new test)

**Interfaces:**
- Consumes: `POST /functions/v1/delete-account-v1` (Task 4), body `{"schemaVersion": 1}` → `{"deleted": true}`; existing `accountDeletionBlockers()` repository read and `AccountDeletionBlockersV1` (`canDelete`, `ownedTrips`).
- Produces:
  - `TeeCircleEndpointCatalog.deleteAccount == "/functions/v1/delete-account-v1"`; `unsupportedCapabilities` empty.
  - `struct AccountDeletionResultV1: Codable, Equatable, Hashable, Sendable { let deleted: Bool }`
  - `TeeCircleRepositoryProtocol.deleteAccount() async throws -> AccountDeletionResultV1`
  - `TeeCircleStore.deleteAccountProduction() async -> Bool`

- [ ] **Step 1: Make the contract test demand the new endpoint (RED)**

In `native/TeeCircleTests/NativeServiceContractTests.swift`, inside `testRepositoryCatalogUsesOnlyVersionedCommands`, replace:

```swift
        XCTAssertEqual(TeeCircleEndpointCatalog.unsupportedCapabilities, [.deleteAccount])
```

with:

```swift
        XCTAssertEqual(TeeCircleEndpointCatalog.deleteAccount, "/functions/v1/delete-account-v1")
        XCTAssertTrue(TeeCircleEndpointCatalog.unsupportedCapabilities.isEmpty)
```

and add this new test method directly after `testRepositoryCatalogUsesOnlyVersionedCommands`:

```swift
    func testAccountDeletionResultDecodesEdgePayload() throws {
        let result = try JSONDecoder().decode(
            AccountDeletionResultV1.self,
            from: Data(#"{"deleted":true}"#.utf8)
        )
        XCTAssertTrue(result.deleted)
    }
```

- [ ] **Step 2: Run unit tests to verify failure**

Run the Global Constraints xcodebuild command with `-only-testing:TeeCircleTests`.
Expected: FAIL to compile — `type 'TeeCircleEndpointCatalog' has no member 'deleteAccount'` and `cannot find 'AccountDeletionResultV1' in scope`.

- [ ] **Step 3: Catalog + contract + repository**

a) `TeeCircleEndpointCatalog.swift` — add after `static let claimPurchase = "/functions/v1/claim-trip-purchase-v1"`:

```swift
    static let deleteAccount = "/functions/v1/delete-account-v1"
```

and replace the populated set:

```swift
    static let unsupportedCapabilities: Set<UnsupportedServerCapability> = [
        .deleteAccount,
    ]
```

with (keep the enum and the doc comment above the property):

```swift
    static let unsupportedCapabilities: Set<UnsupportedServerCapability> = []
```

b) `TeeCircleServiceContracts.swift` — add after the closing brace of `struct AccountDeletionBlockersV1`:

```swift
struct AccountDeletionResultV1: Codable, Equatable, Hashable, Sendable {
    let deleted: Bool
}
```

c) `TeeCircleRepository.swift` — in `TeeCircleRepositoryProtocol`, add directly under `func accountDeletionBlockers() async throws -> AccountDeletionBlockersV1`:

```swift
    func deleteAccount() async throws -> AccountDeletionResultV1
```

In `actor TeeCircleRepository`, add after the `accountDeletionBlockers()` implementation:

```swift
    func deleteAccount() async throws -> AccountDeletionResultV1 {
        try await callEdgeFunction(
            path: TeeCircleEndpointCatalog.deleteAccount,
            body: DeleteAccountArguments(schemaVersion: 1)
        )
    }
```

And add with the other private argument structs near the bottom of the file:

```swift
private struct DeleteAccountArguments: Codable, Sendable {
    let schemaVersion: Int
}
```

- [ ] **Step 4: Store action**

In `native/TeeCircle/App/TeeCircleStore+Production.swift`, add directly after the `accountDeletionBlockers()` method:

```swift
    /// Runs the server-side deletion, then clears all local state. The server
    /// account no longer exists on success, so server-bound sign-out calls are
    /// best-effort only.
    func deleteAccountProduction() async -> Bool {
        guard let production else {
            reportConfigurationError()
            return false
        }
        do {
            let result = try await production.repository.deleteAccount()
            guard result.deleted else {
                errorMessage = "The account could not be deleted. Try again."
                return false
            }
        } catch {
            report(error)
            return false
        }
        await production.realtime.stopAll()
        try? await production.sharedStore.revokeAllLocally()
        await production.pendingScores.removeAll()
        await production.liveActivity.endAll()
        await production.purchases.clearRevenueCatUser()
        try? await production.auth.signOut()
        production.analytics.reset()
        isAuthenticated = false
        currentDisplayName = "Player"
        currentUsername = nil
        needsProfileSetup = nil
        trips = []
        legacyRounds = []
        courseCards = []
        pendingScoreKeys = []
        inviteCredentials = [:]
        inviteMetadataByTrip = [:]
        path.removeAll()
        golfersPath.removeAll()
        selectedTab = .rounds
        return true
    }
```

- [ ] **Step 5: Wire ProfileView**

In `native/TeeCircle/Features/Account/ProfileView.swift`:

a) Add under `@State private var isEditingIdentity = false`:

```swift
    @State private var isDeletingAccount = false
```

b) Replace:

```swift
                    Button("Delete account", role: .destructive) { showDeleteConfirmation = true }
                        .accessibilityIdentifier("account.delete")
```

with:

```swift
                    Button("Delete account", role: .destructive) { showDeleteConfirmation = true }
                        .disabled(isDeletingAccount)
                        .accessibilityIdentifier("account.delete")
```

c) Replace the whole `Button("Request deletion", role: .destructive) { … }` block (including its current dead-end "requires the server-side destructive command" branch) with:

```swift
            Button("Request deletion", role: .destructive) {
                if store.configuration.useMockData {
                    store.errorMessage = "Fixture mode cannot delete an account. Production first checks ownership transfer and archival constraints."
                } else {
                    Task {
                        guard let blockers = await store.accountDeletionBlockers() else { return }
                        if blockers.canDelete {
                            isDeletingAccount = true
                            _ = await store.deleteAccountProduction()
                            isDeletingAccount = false
                        } else {
                            let names = blockers.ownedTrips.map(\.name).joined(separator: ", ")
                            store.errorMessage = "Transfer or archive these trips first: \(names)."
                        }
                    }
                }
            }
            .accessibilityIdentifier("account.confirmDelete")
```

(Success needs no toast: the store resets to the signed-out state, which is the visible confirmation.)

- [ ] **Step 6: Run the full app suite**

Run the Global Constraints xcodebuild `test` command.
Expected: 58/58 (45 unit + 13 UI).

- [ ] **Step 7: Commit**

```bash
git add native/TeeCircle/Services/API/TeeCircleEndpointCatalog.swift native/TeeCircle/Services/API/TeeCircleServiceContracts.swift native/TeeCircle/Services/API/TeeCircleRepository.swift native/TeeCircle/App/TeeCircleStore+Production.swift native/TeeCircle/Features/Account/ProfileView.swift native/TeeCircleTests/NativeServiceContractTests.swift
git commit -m "Client: real account deletion via delete-account-v1

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `decline_trip_seat_v1` migration + SQL behavior coverage

Server half of RSVP decline. Verified data-model reality: `trip_players.rsvp` is DB-checked to `('pending','yes','no')`; the client maps `no → .declined`. A **pending invitee has no row of their own** — `accept_trip_invite_v1` (last live def in `20260718184030…release_integrity.sql:463`) only shows unclaimed open seats until a claim happens — so there is nothing in the data model for an un-claimed invitee to decline. Scope: decline is for the **claimed** player only, modeled as release-claim + `rsvp = 'no'` (mirrors `release_trip_player_claim_v1` in `20260718183934…gameplay.sql:133`, including extension-session revocation and Live Activity teardown). Because `tee_internal.is_trip_member` filters `rsvp <> 'no'`, a declined player intentionally loses trip access; the captain can re-open the seat with `update_trip_player_v1`.

**Files:**
- Create: `supabase/migrations/20260720140000_tee_circle_v2_decline_trip_seat.sql`
- Test: `supabase/tests/tee_circle_v2_decline_seat_behavior.sql`
- Modify: `supabase/tests/run-local-v2.sh` (register the new test file)
- Modify: `supabase/tests/tee_circle_v2_function_acl_contract.sql` (add the new function)

**Interfaces:**
- Consumes: `tee_internal.api_success/api_error`, `tee_internal.native_writes_enabled()`, `tee_internal.is_trip_member`.
- Produces: `public.decline_trip_seat_v1(p_trip_player_id uuid) returns jsonb` — success `data = {"tripId": uuid, "tripPlayerId": uuid, "rsvp": "no", "claimed": false}`; error codes `unauthenticated`, `native_writes_disabled` (retryable), `player_not_found`, `forbidden` (not the claimer — including a repeat decline after the claim is gone), `captain_claim_required`, `trip_archived`. Task 7's client calls it.

- [ ] **Step 1: Write the failing behavior test and register it**

Create `supabase/tests/tee_circle_v2_decline_seat_behavior.sql`:

```sql
-- decline_trip_seat_v1 regression: only the claimed player can decline, the
-- captain seat and archived trips are protected, and a decline releases the
-- claim, marks rsvp 'no', revokes extension sessions, and removes trip
-- membership. Run only against the disposable fixture through
-- run-local-v2.sh.

begin;

update tee_internal.runtime_flags set enabled = true
where key = 'native_writes_enabled';

insert into auth.users (id) values
  ('91000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002');

insert into public.profiles (id, full_name) values
  ('91000000-0000-4000-8000-000000000001', 'Decline Captain'),
  ('91000000-0000-4000-8000-000000000002', 'Decline Player');

insert into public.trips (id, public_id, owner_id, name, starts_on, ends_on, status) values
  ('92000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000011',
   '91000000-0000-4000-8000-000000000001', 'Decline Trip', '2026-08-01', '2026-08-02', 'ready'),
  ('92000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000012',
   '91000000-0000-4000-8000-000000000001', 'Archived Trip', '2026-05-01', '2026-05-02', 'archived');

insert into public.trip_players (id, trip_id, claimed_user_id, display_name, role, rsvp) values
  ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
   '91000000-0000-4000-8000-000000000001', 'Captain', 'captain', 'yes'),
  ('93000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000001',
   '91000000-0000-4000-8000-000000000002', 'Player', 'player', 'yes'),
  ('93000000-0000-4000-8000-000000000003', '92000000-0000-4000-8000-000000000002',
   '91000000-0000-4000-8000-000000000002', 'Archived Player', 'player', 'yes');

insert into public.extension_sessions (
  id, trip_id, user_id, trip_player_id, device_id, token_hash, expires_at
) values (
  '94000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001',
  '91000000-0000-4000-8000-000000000002', '93000000-0000-4000-8000-000000000002',
  'decline-device-1', '\x11'::bytea, now() + interval '1 hour'
);

-- Someone else's seat (even for the captain) is forbidden: decline is a
-- first-person action; captains keep release_trip_player_claim_v1.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
do $$
declare result jsonb; captain_result jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  captain_result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000001');
  if result#>>'{error,code}' <> 'forbidden'
     or captain_result#>>'{error,code}' <> 'captain_claim_required' then
    raise exception 'decline authorization guards failed: %, %', result, captain_result;
  end if;
end
$$;

-- Archived trips cannot change roster claims.
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000002', true);
do $$
declare result jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000003');
  if result#>>'{error,code}' <> 'trip_archived' then
    raise exception 'archived decline guard failed: %', result;
  end if;
end
$$;

-- The claimed player declines: claim released, rsvp 'no', sessions revoked,
-- membership gone. A repeat decline finds no claim and is forbidden.
do $$
declare result jsonb; replay jsonb;
begin
  result := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  if result#>>'{data,claimed}' <> 'false' or result#>>'{data,rsvp}' <> 'no' then
    raise exception 'decline did not succeed: %', result;
  end if;
  if (select claimed_user_id from public.trip_players where id = '93000000-0000-4000-8000-000000000002') is not null
     or (select rsvp from public.trip_players where id = '93000000-0000-4000-8000-000000000002') <> 'no'
     or (select display_name from public.trip_players where id = '93000000-0000-4000-8000-000000000002') <> 'Player' then
    raise exception 'decline row state is wrong';
  end if;
  if exists (
    select 1 from public.extension_sessions
    where trip_player_id = '93000000-0000-4000-8000-000000000002' and revoked_at is null
  ) then
    raise exception 'decline left an active extension session';
  end if;
  if tee_internal.is_trip_member(
    '92000000-0000-4000-8000-000000000001',
    '91000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'declined player is still a trip member';
  end if;
  replay := public.decline_trip_seat_v1('93000000-0000-4000-8000-000000000002');
  if replay#>>'{error,code}' <> 'forbidden' then
    raise exception 'repeat decline should be forbidden once the claim is gone: %', replay;
  end if;
end
$$;

rollback;
```

Register it in `supabase/tests/run-local-v2.sh` by adding this line directly after the `tee_circle_v2_account_finalize_behavior.sql` line added in Task 3:

```bash
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_decline_seat_behavior.sql"
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `supabase/tests/run-local-v2.sh`
Expected: FAIL in the new file with `function public.decline_trip_seat_v1(uuid) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260720140000_tee_circle_v2_decline_trip_seat.sql`:

```sql
set lock_timeout = '10s';
set statement_timeout = '5min';

-- RSVP decline for a claimed roster seat. The data model has no per-invitee
-- record before a claim (accept_trip_invite_v1 only lists open seats), so
-- decline is a first-person action by the claimed player: release the claim
-- and mark rsvp 'no', mirroring release_trip_player_claim_v1's locking and
-- session/activity teardown. is_trip_member filters rsvp <> 'no', so a
-- declined player intentionally loses trip access; the captain can re-open
-- the seat with update_trip_player_v1.

create or replace function public.decline_trip_seat_v1(p_trip_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, tee_internal
as $$
declare
  v_request_id uuid := gen_random_uuid();
  v_user_id uuid := auth.uid();
  v_trip_id uuid;
  v_trip public.trips%rowtype;
  v_player public.trip_players%rowtype;
begin
  if v_user_id is null then
    return tee_internal.api_error(v_request_id, 'unauthenticated', 'Sign in is required.');
  end if;
  if not tee_internal.native_writes_enabled() then
    return tee_internal.api_error(v_request_id, 'native_writes_disabled', 'Native trip changes are temporarily unavailable.', true);
  end if;
  -- Match release_trip_player_claim_v1: lock the trip before the roster seat.
  select tp.trip_id into v_trip_id from public.trip_players tp
  where tp.id = p_trip_player_id;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  select * into v_trip from public.trips t where t.id = v_trip_id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  select * into v_player from public.trip_players tp
  where tp.id = p_trip_player_id and tp.trip_id = v_trip.id for update;
  if not found then
    return tee_internal.api_error(v_request_id, 'player_not_found', 'Roster player not found.');
  end if;
  if v_player.role = 'captain' then
    return tee_internal.api_error(v_request_id, 'captain_claim_required', 'Transfer trip ownership before declining the captain seat.');
  end if;
  if v_player.claimed_user_id is distinct from v_user_id then
    return tee_internal.api_error(v_request_id, 'forbidden', 'Only the player who claimed this seat can decline it.');
  end if;
  if v_trip.status = 'archived' then
    return tee_internal.api_error(v_request_id, 'trip_archived', 'Archived trips cannot change roster claims.');
  end if;

  update public.trip_players
  set claimed_user_id = null, rsvp = 'no'
  where id = v_player.id;
  update public.extension_sessions set revoked_at = now()
  where trip_player_id = v_player.id and revoked_at is null;
  update public.live_activity_subscriptions set ended_at = coalesce(ended_at, now())
  where trip_id = v_player.trip_id
    and user_id = v_user_id
    and ended_at is null;

  return tee_internal.api_success(v_request_id, jsonb_build_object(
    'tripId', v_player.trip_id,
    'tripPlayerId', v_player.id,
    'rsvp', 'no',
    'claimed', false
  ));
end;
$$;

revoke all on function public.decline_trip_seat_v1(uuid) from public;
grant execute on function public.decline_trip_seat_v1(uuid) to authenticated;
```

Note the guard order: the captain check comes before the claimer check so a captain probing their own seat gets `captain_claim_required` (the test's second assertion relies on this).

- [ ] **Step 4: Add the function to the ACL contract**

In `supabase/tests/tee_circle_v2_function_acl_contract.sql`, in `v_expected_authenticated`, insert alphabetically between `'public.create_trip_v1(jsonb,uuid)',` and `'public.delete_round(uuid)',`:

```sql
    'public.decline_trip_seat_v1(uuid)',
```

- [ ] **Step 5: Run the suite to verify green**

Run: `supabase/tests/run-local-v2.sh`
Expected: final line `TeeCircle v2 local SQL suite passed.`

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260720140000_tee_circle_v2_decline_trip_seat.sql supabase/tests/tee_circle_v2_decline_seat_behavior.sql supabase/tests/run-local-v2.sh supabase/tests/tee_circle_v2_function_acl_contract.sql
git commit -m "Add decline_trip_seat_v1 migration + SQL behavior coverage

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Owner follow-up (deferred): apply this migration to production via SQL editor paste.

---

### Task 7: Client — decline your trip seat from the roster

The roster row for the current user's own claimed non-captain seat gains a "Can't make it" action. Server-side decline removes trip membership (`is_trip_member` filters `rsvp <> 'no'`), so on success the client drops the trip locally and returns home. `InviteClaimView` needs no server call: its "Not now" dismiss already matches the data model (no per-invitee record exists before a claim — see Task 6's scope note).

**Files:**
- Modify: `native/TeeCircle/Services/API/TeeCircleEndpointCatalog.swift`
- Modify: `native/TeeCircle/Services/API/TeeCircleServiceContracts.swift`
- Modify: `native/TeeCircle/Services/API/TeeCircleRepository.swift`
- Modify: `native/TeeCircle/App/TeeCircleStore.swift` (fixture-mode action)
- Modify: `native/TeeCircle/App/TeeCircleStore+Production.swift` (production action)
- Modify: `native/TeeCircle/Features/Trips/TripHubView.swift` (roster affordance)
- Test: `native/TeeCircleTests/NativeServiceContractTests.swift` + `native/TeeCircleTests/TeeCircleStoreTests.swift`

**Interfaces:**
- Consumes: `public.decline_trip_seat_v1(p_trip_player_id uuid)` (Task 6) with PostgREST argument `p_trip_player_id`; existing `NativeRSVPStatus` (`yes`/`no`/`pending`) and `RSVPStatus.declined` domain mapping.
- Produces:
  - `TeeCircleEndpointCatalog.declineTripSeat == "/rest/v1/rpc/decline_trip_seat_v1"`
  - `struct DeclineTripSeatResultV1: Codable, Equatable, Hashable, Sendable { let tripId: String; let tripPlayerId: String; let rsvp: NativeRSVPStatus; let claimed: Bool }`
  - `TeeCircleRepositoryProtocol.declineTripSeat(id: String) async throws -> DeclineTripSeatResultV1`
  - `TeeCircleStore.declineSeat(tripID:playerID:)` (fixture) and `TeeCircleStore.declineSeatProduction(tripID:playerID:)`.

- [ ] **Step 1: Write the failing tests**

a) In `native/TeeCircleTests/NativeServiceContractTests.swift`, inside `testRepositoryCatalogUsesOnlyVersionedCommands`, add after the `releaseTripPlayer`-adjacent assertions (e.g. directly under the `acceptTripInvite` line):

```swift
        XCTAssertTrue(TeeCircleEndpointCatalog.declineTripSeat.hasSuffix("/decline_trip_seat_v1"))
```

b) In `native/TeeCircleTests/TeeCircleStoreTests.swift`, add a new test method:

```swift
    func testDeclineSeatReleasesOwnPlayerSeat() throws {
        let store = makeStore()
        store.replaceTrip("pinehurst-2026") { experience in
            experience.players[1] = TripPlayer(
                id: "sean",
                tripId: "pinehurst-2026",
                claimedUserId: store.currentUserID,
                displayName: "Sean",
                role: .player,
                rsvp: .accepted,
                handicapSnapshot: 12.1,
                sortOrder: 1
            )
        }

        store.declineSeat(tripID: "pinehurst-2026", playerID: "sean")

        let seat = try XCTUnwrap(
            store.trip(id: "pinehurst-2026")?.players.first { $0.id == "sean" }
        )
        XCTAssertNil(seat.claimedUserId)
        XCTAssertEqual(seat.rsvp, .declined)
    }
```

- [ ] **Step 2: Run unit tests to verify failure**

Run the Global Constraints xcodebuild command with `-only-testing:TeeCircleTests`.
Expected: FAIL to compile — `has no member 'declineTripSeat'` / `has no member 'declineSeat'`.

- [ ] **Step 3: Catalog + contract + repository**

a) `TeeCircleEndpointCatalog.swift` — add directly under `static let releaseTripPlayer = rpc("release_trip_player_claim_v1")`:

```swift
    static let declineTripSeat = rpc("decline_trip_seat_v1")
```

b) `TeeCircleServiceContracts.swift` — add after the closing brace of `struct TripPlayerClaimResultV1`:

```swift
struct DeclineTripSeatResultV1: Codable, Equatable, Hashable, Sendable {
    let tripId: String
    let tripPlayerId: String
    let rsvp: NativeRSVPStatus
    let claimed: Bool
}
```

c) `TeeCircleRepository.swift` — in `TeeCircleRepositoryProtocol`, add directly under `func releaseTripPlayerClaim(id: String) async throws -> TripPlayerClaimResultV1`:

```swift
    func declineTripSeat(id: String) async throws -> DeclineTripSeatResultV1
```

In `actor TeeCircleRepository`, add after the `releaseTripPlayerClaim(id:)` implementation (reuses the existing private `TripPlayerIDArguments` which encodes `p_trip_player_id`):

```swift
    func declineTripSeat(id: String) async throws -> DeclineTripSeatResultV1 {
        try await callRPC(
            path: TeeCircleEndpointCatalog.declineTripSeat,
            body: TripPlayerIDArguments(pTripPlayerId: id)
        )
    }
```

- [ ] **Step 4: Store actions**

a) `native/TeeCircle/App/TeeCircleStore.swift` — add directly after `func revokePlayerClaim(tripID:playerID:)`:

```swift
    func declineSeat(tripID: String, playerID: String) {
        replaceTrip(tripID) { experience in
            guard let index = experience.players.firstIndex(where: { $0.id == playerID }),
                  experience.players[index].claimedUserId == currentUserID,
                  experience.players[index].role != .captain
            else { return }
            let player = experience.players[index]
            experience.players[index] = TripPlayer(
                id: player.id,
                tripId: player.tripId,
                claimedUserId: nil,
                displayName: player.displayName,
                role: player.role,
                rsvp: .declined,
                handicapSnapshot: player.handicapSnapshot,
                sortOrder: player.sortOrder
            )
        }
    }
```

b) `native/TeeCircle/App/TeeCircleStore+Production.swift` — add directly after `func revokePlayerClaimProduction(tripID:playerID:)`:

```swift
    func declineSeatProduction(tripID: String, playerID: String) async {
        guard !configuration.useMockData else {
            declineSeat(tripID: tripID, playerID: playerID)
            return
        }
        guard let production else { return }
        do {
            _ = try await production.repository.declineTripSeat(id: playerID)
            // Declining removes this user's trip membership server-side, so the
            // trip is no longer readable: drop it locally and return home.
            trips.removeAll { $0.id == tripID }
            inviteCredentials.removeValue(forKey: tripID)
            inviteMetadataByTrip.removeValue(forKey: tripID)
            try? await production.invites.remove(tripID: tripID)
            path.removeAll()
            try? await synchronizeMessagesBridge()
        } catch { report(error) }
    }
```

- [ ] **Step 5: Roster affordance in TripHubView**

In `native/TeeCircle/Features/Trips/TripHubView.swift`, inside `roster(_:)`, replace:

```swift
                        } else if player.claimedUserId == nil {
                            Text("Open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Claimed", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TeeCircleBrand.moss)
                        }
```

with:

```swift
                        } else if player.claimedUserId == nil {
                            Text("Open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if player.claimedUserId == store.currentUserID, player.role != .captain {
                            Menu {
                                Button("Can’t make it", role: .destructive) {
                                    Task { await store.declineSeatProduction(tripID: tripID, playerID: player.id) }
                                }
                            } label: {
                                Label("You", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TeeCircleBrand.moss)
                            }
                            .accessibilityIdentifier("trip.decline.\(player.id)")
                        } else {
                            Label("Claimed", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TeeCircleBrand.moss)
                        }
```

(A captain viewing their own captain seat still falls through to "Claimed" — the server refuses captain declines and the UI never offers one. Fixture seeds claim no non-captain seat for the current user, so the 13 UI tests are unaffected.)

- [ ] **Step 6: Run the full app suite**

Run the Global Constraints xcodebuild `test` command.
Expected: 59/59 (46 unit + 13 UI).

- [ ] **Step 7: Commit**

```bash
git add native/TeeCircle/Services/API/TeeCircleEndpointCatalog.swift native/TeeCircle/Services/API/TeeCircleServiceContracts.swift native/TeeCircle/Services/API/TeeCircleRepository.swift native/TeeCircle/App/TeeCircleStore.swift native/TeeCircle/App/TeeCircleStore+Production.swift native/TeeCircle/Features/Trips/TripHubView.swift native/TeeCircleTests/NativeServiceContractTests.swift native/TeeCircleTests/TeeCircleStoreTests.swift
git commit -m "Client: decline your trip seat from the roster

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Small cleanups — unlink GoogleSignInSwift, keyboard-driven inset

Two independent cleanups, one task. (1) The `GoogleSignInSwift` SwiftPM product is linked in `native/project.yml` but never imported — `grep -rn "import GoogleSignInSwift" native --include="*.swift"` returns nothing; only `import GoogleSignIn` (in `TeeCircleApp.swift` and `TeeCircleStore+Production.swift`) is real, so the `GoogleSignIn` product stays. (2) `LegacyTripSetupView.swift` reserves a hard-coded 320pt keyboard guess; replace it with keyboard-notification-driven height while keeping the top-anchor `scrollTo` strategy that made the UI test pass.

**Files:**
- Modify: `native/project.yml`
- Modify: `native/TeeCircle/Features/Legacy/LegacyTripSetupView.swift`
- Regenerate: `native/TeeCircle.xcodeproj/project.pbxproj` (xcodegen — this one intentionally REMOVES `GoogleSignInSwift` references)

**Interfaces:**
- Consumes: `UIResponder.keyboardWillChangeFrameNotification` / `keyboardWillHideNotification` (`UIKit` is already imported transitively via SwiftUI; no new import needed — SwiftUI on iOS re-exports UIKit symbols used here through `UIResponder`; if the compiler disagrees, add `import UIKit` at the top of the file).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Unlink the unused product**

In `native/project.yml`, under the `TeeCircle` target's `dependencies`, delete exactly these two lines (the `- package: GoogleSignIn` / `product: GoogleSignIn` pair above them stays):

```yaml
      - package: GoogleSignIn
        product: GoogleSignInSwift
```

- [ ] **Step 2: Regenerate and verify the diff removes only GoogleSignInSwift**

Run: `cd native && xcodegen generate`
Then: `git diff native/TeeCircle.xcodeproj/project.pbxproj | grep '^[+-]' | grep -v '^+++\|^---' | grep -vi 'GoogleSignInSwift'`
Expected: no output (every changed pbxproj line mentions GoogleSignInSwift).

- [ ] **Step 3: Replace the keyboard-height guess**

In `native/TeeCircle/Features/Legacy/LegacyTripSetupView.swift`:

a) Add a state property under `@State private var isSaving = false`:

```swift
    @State private var keyboardOverlapHeight: CGFloat = 0
```

b) Replace the guess block (keep a trimmed version of the explanatory comment):

```swift
                                // The handicap rows above fit on-screen with room
                                // to spare when the keyboard is dismissed, so the
                                // scroll view has no natural slack to scroll
                                // through. Once the keyboard covers roughly half
                                // the screen, any touch that starts near the
                                // bottom (where a swipe or a real drag-to-scroll
                                // would normally begin) lands on the keyboard
                                // itself and never reaches the scroll view, so no
                                // amount of swiping can reveal the later rows on
                                // its own. ScrollViewReader also has no notion of
                                // the keyboard overlay, so anchoring the
                                // bottom-most content at the visible "bottom" is
                                // unreliable (that "bottom" is the full screen,
                                // keyboard included). Instead, reserve
                                // keyboard-sized scroll room and pin the
                                // handicaps section's own top to the top of the
                                // viewport as soon as any handicap field is
                                // focused, pushing the whole (short)
                                // handicaps+button block safely above the
                                // keyboard regardless of its exact height, before
                                // the next field is tapped.
                                Color.clear
                                    .frame(height: focusedHandicapPlayerID != nil ? 320 : 0)
```

with:

```swift
                                // The handicap rows fit on-screen with the
                                // keyboard dismissed, so the scroll view has no
                                // natural slack; once the keyboard appears,
                                // touches near the bottom land on the keyboard
                                // and can never scroll the later rows into view.
                                // Reserve keyboard-sized scroll room (measured
                                // from the keyboard frame notifications, not
                                // guessed) and pin the handicaps section's top to
                                // the viewport top while any handicap field is
                                // focused.
                                Color.clear
                                    .frame(height: focusedHandicapPlayerID != nil ? keyboardOverlapHeight : 0)
```

c) Directly after the existing `.onChange(of: focusedHandicapPlayerID) { … }` modifier on the ScrollView, add (the height arrives after focus, so re-run the same top-anchor scroll once the room actually exists):

```swift
                        .onChange(of: keyboardOverlapHeight) { newValue in
                            guard newValue > 0, focusedHandicapPlayerID != nil else { return }
                            withAnimation { proxy.scrollTo("legacy.handicapsRevealAnchor", anchor: .top) }
                        }
                        .onReceive(NotificationCenter.default.publisher(
                            for: UIResponder.keyboardWillChangeFrameNotification
                        )) { notification in
                            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                            keyboardOverlapHeight = max(0, UIScreen.main.bounds.height - frame.origin.y)
                        }
                        .onReceive(NotificationCenter.default.publisher(
                            for: UIResponder.keyboardWillHideNotification
                        )) { _ in
                            keyboardOverlapHeight = 0
                        }
```

- [ ] **Step 4: Run the full app suite**

Run the Global Constraints xcodebuild `test` command.
Expected: 59/59 (46 unit + 13 UI) — in particular the legacy-conversion UI test that motivated the original 320pt reservation stays green. Any regression blocks this task.

- [ ] **Step 5: Run the package tests (regression check after project changes)**

Run: `cd native/Packages/TeeCircleKit && swift test`
Expected: `Executed 38 tests`, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add native/project.yml native/TeeCircle.xcodeproj/project.pbxproj native/TeeCircle/Features/Legacy/LegacyTripSetupView.swift
git commit -m "Unlink unused GoogleSignInSwift; keyboard-driven legacy setup inset

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Deferred Owner Steps (batched — nothing in Tasks 1–8 blocks on these)

The owner runs these in one later session. Until then, everything above is fully verified by local tests; production simply keeps its current behavior (course search stays hidden with no key, the app's delete flow keeps working once the migration + function land).

- [ ] **Google Places key (enables Task 1–2's search in real builds):**
  1. In Google Cloud Console, on the same project that owns the existing OAuth client IDs, enable **Places API (New)** (APIs & Services → Library).
  2. APIs & Services → Credentials → Create credentials → **API key**. Restrict it: Application restrictions → **iOS apps** → add bundle ID `com.teecircle.app`; API restrictions → **Places API (New)** only.
  3. Put it in `native/Config/Secrets.xcconfig` as `TEE_GOOGLE_PLACES_API_KEY = <key>` (git-ignored; never in eas.json, never committed — public repo).
  4. Build to a device/simulator, open New round, type 3+ letters of a real course, confirm suggestions appear and selecting one fills the field. Delete the key temporarily and confirm the field silently reverts to free text.
- [ ] **Apply migrations to production (SQL editor paste, same routine as before), in timestamp order:**
  0. `supabase/migrations/20260719120000_fix_bootstrap_roster_null_is_current_user.sql` — may already be applied during bring-up (2026-07-19 session) — it is create-or-replace idempotent, safe to re-run; verify with: `select proname from pg_proc join pg_namespace n on n.oid = pronamespace where proname in ('get_trip_bootstrap_unfiltered_v1');` returning a row whose body coalesces isCurrentUser (or simply re-run the file).
  1. `supabase/migrations/20260720130000_tee_circle_v2_account_deletion_finalizer.sql`
  2. `supabase/migrations/20260720140000_tee_circle_v2_decline_trip_seat.sql`
  - Leave `tee_internal.runtime_flags` alone: `purchases_required` false, `live_activity_pushes_enabled` false, `native_writes_enabled` true, `public_previews_enabled` as currently set.
- [ ] **Deploy the edge function:** `supabase functions deploy delete-account-v1` (JWT verification stays on, like the other functions).
- [ ] **End-to-end deletion check with a throwaway account:** sign up fresh, create a trip, complete/archive or transfer it, then Profile → Delete account. Expect: signed out locally; the account cannot sign back in; a second throwaway that shared a trip with it still sees the trip, the seat (unclaimed), and its scores.
- [ ] **End-to-end decline check:** with two accounts, claim a seat on account B, tap the roster row's "Can't make it" on B, confirm the trip disappears for B and the captain sees the seat freed with a declined status.

---

## Self-Review

Performed against the M2 dispatch after writing all eight tasks.

**1. Spec coverage.**
- *A. Golf course search:* Task 1 ports `src/lib/placesApi.ts` faithfully — same endpoints, `includedPrimaryTypes: ["golf_course"]`, field masks, 50 km bias circle, session tokens, and an AbortSignal-equivalent (URLError.cancelled → `CancellationError`, tested). Task 2 adds the `TEE_GOOGLE_PLACES_API_KEY` key (empty example entry, git-ignored real file), the graceful no-key fallback (controller disabled → plain free text, tested), suggestions under the course-name field in **both** CreateRoundView and CreateTripView (verified they are separate implementations, so both are wired), and the owner's Google Cloud key steps. Coordinates dropped with verification: `create_trip_round_v1` input carries no lat/lng (`CreateTripRoundInputV1` = courseCardId/teeTime/walkRide), so YAGNI per dispatch. The details fetch is still made on selection to preserve the v1 session-token economics.
- *B. RSVP decline:* Task 6 adds the command in exact house style (envelope, `native_writes_enabled()` gate, request-id, revoke/grant ACL, release-claim locking order) with RED-first SQL tests registered in `run-local-v2.sh` and the ACL contract updated. Scope decision (explicit in the plan): the data model has no per-invitee record before a claim, so token-based "pending invitee declines" has nothing to mark — decline is claimed-player-only, and InviteClaimView's local "Not now" already covers the pre-claim case. Task 7 adds catalog entry (contract-test enforced), repository method, store actions (fixture + production), and the roster affordance.
- *C. Account deletion:* Task 3 implements `finalize_account_deletion_v1()` against the verified FK graph (all RESTRICT/NO ACTION edges enumerated and handled; the SQL test proves `delete from auth.users` succeeds afterward), Task 4 the edge function (JWT verify → RPC as user → Auth Admin delete, `_test.ts` convention), Task 5 the client (removes `.deleteAccount` from `unsupportedCapabilities`, wires ProfileView, local state reset on success). Honest scope note included (CODE-17 server gap closed for all users; Expo binary unchanged). Owner steps deferred and batched.
- *D. Cleanups:* Task 8 — GoogleSignInSwift unlink (import-grep verified unused) + notification-driven keyboard inset preserving the top-anchor scroll strategy, gated on the full suite.
- Sizing/order: 8 tasks; course search first, deletion before decline (shared SQL-suite scaffolding conventions), cleanups last; every task ends in agent-runnable verification + its own commit; no mid-plan owner dependency. Global constraints carried verbatim (copy rule, kill switches, secrets, branch/simulator pin, baselines, xcodegen rule).

**2. Placeholder scan.** Searched the plan for "TBD", "TODO", "implement later", "add error handling", "similar to Task", and steps that describe code without showing it: none found. Every code step contains the complete file or the exact replace-this-with-that blocks; every run step has a command and expected output. The one intentionally judgment-shaped instruction (Task 4 Step 7's offline `deno check` note) states exactly what to do in either outcome.

**3. Type consistency.**
- `GolfCoursePrediction` (placeId/mainText/secondaryText) identical in Task 1's client, tests, and Task 2's controller/list; `select(_:)` returns `String` and both views assign it to a `String` binding.
- `AccountDeletionResultV1 { deleted: Bool }` matches the edge function's `success(id, { deleted: true })`; error code `account_deletion_blocked` is produced by Task 3, mapped by Task 4 (`accountDeletionStatusFor` → 409), and never re-spelled differently.
- `DeclineTripSeatResultV1.rsvp: NativeRSVPStatus` decodes the SQL `'no'` literal (`NativeRSVPStatus.no` exists; domain mapping `no → .declined` verified in `TeeCircleStore+Production.swift:1259`); the repository reuses the existing `TripPlayerIDArguments` (`p_trip_player_id`) which matches the SQL parameter name.
- Test-count arithmetic is consistent end-to-end: package 32→38 (Task 1); app 55 → 57 (Task 2, +2 unit) → 58 (Task 5, +1) → 59 (Task 7, +1); Task 8 changes no counts.
- One deliberate asymmetry, documented in Task 6: guard order puts `captain_claim_required` before the claimer check so a captain probing their own seat gets the actionable error; the SQL test pins this.

Verdict: no gaps found; two scope decisions (drop coordinates; claimed-player-only decline) are recorded inline with their evidence.
