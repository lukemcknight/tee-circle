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
