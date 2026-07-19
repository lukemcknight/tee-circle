import Foundation

enum ProfileSaveOutcome: Equatable, Sendable {
    case saved
    case failed(code: String?, message: String)

    /// Lets a form put the message under the handle field rather than at the top.
    var isUsernameProblem: Bool {
        guard case let .failed(code, _) = self else { return false }
        return code == "username_taken" || code == "invalid_username"
    }
}

/// Client-side mirror of `tee_internal.normalize_username` and USERNAME_REGEX in
/// `src/utils/username.ts`. The server revalidates everything; this exists so the
/// form can disable its own submit button without a round trip.
enum Username {
    static func normalize(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") {
            trimmed.removeFirst()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValid(_ value: String) -> Bool {
        let normalized = normalize(value)
        guard (3...20).contains(normalized.count) else { return false }
        return normalized.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "_" || character == "-")
        }
    }

    /// Nil once the handle is acceptable, so a form can show guidance while typing.
    static func validationMessage(for value: String) -> String? {
        let normalized = normalize(value)
        if normalized.isEmpty { return "Pick a username so friends can find you." }
        if normalized.count < 3 { return "Usernames are at least 3 characters." }
        if normalized.count > 20 { return "Usernames are 20 characters or fewer." }
        if !isValid(normalized) { return "Use letters, numbers, underscores, or hyphens." }
        return nil
    }

    static func display(_ username: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        return "@\(username)"
    }
}

enum PlayerName {
    static let maxLength = 80

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ value: String) -> Bool {
        let normalized = normalize(value)
        return !normalized.isEmpty && normalized.count <= maxLength
    }

    /// Apple supplies name components only on the first authorization for an
    /// account, so this runs at most once per user and never again.
    static func fromAppleComponents(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        let trimmed = normalize(formatted)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }
}
