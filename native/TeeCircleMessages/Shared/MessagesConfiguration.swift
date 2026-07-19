import Foundation

struct MessagesConfiguration: Sendable {
    let appGroupIdentifier: String
    let keychainAccessGroup: String?
    let supabaseHost: String
    let supabasePublishableKey: String?
    let webHost: String

    static let current = MessagesConfiguration(bundle: .main)

    init(bundle: Bundle) {
        appGroupIdentifier = bundle.string(forInfoKey: "TeeCircleAppGroupIdentifier")
            ?? "group.com.teecircle.app.shared"
        keychainAccessGroup = bundle.nonemptyString(forInfoKey: "TeeCircleKeychainAccessGroup")
        supabaseHost = bundle.string(forInfoKey: "TeeCircleSupabaseHost")
            ?? "zgrbwhnfuxgvkwtgrncu.supabase.co"
        supabasePublishableKey = bundle.nonemptyString(forInfoKey: "TeeCircleSupabasePublishableKey")
        webHost = bundle.string(forInfoKey: "TeeCircleWebHost") ?? "teecircle.vercel.app"
    }

    var functionsURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = supabaseHost
        components.path = "/functions/v1"
        return components.url
    }

    func inviteURL(token: String) -> URL? {
        guard token.range(
            of: #"^[A-Za-z0-9_-]{40,128}$"#,
            options: .regularExpression
        ) != nil else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = webHost
        components.path = "/t/\(token)"
        return components.url
    }
}

private extension Bundle {
    func string(forInfoKey key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }

    func nonemptyString(forInfoKey key: String) -> String? {
        guard let value = string(forInfoKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("$(")
        else { return nil }
        return value
    }
}
