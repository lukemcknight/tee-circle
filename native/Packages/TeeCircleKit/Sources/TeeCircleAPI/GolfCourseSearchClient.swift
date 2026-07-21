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
