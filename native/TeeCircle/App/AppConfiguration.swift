import Foundation

struct AppConfiguration: Sendable {
    let supabaseURL: URL?
    let supabasePublishableKey: String
    let webBaseURL: URL
    let keychainAccessGroup: String?
    let postHogHost: URL?
    let postHogToken: String
    let googleIOSClientID: String
    let googleServerClientID: String
    let revenueCatPublicKey: String
    let revenueCatTripProductID: String
    let useMockData: Bool

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let value: (String) -> String = { key in
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let supabaseHost = value("TEESupabaseHost")
        let webHost = value("TEEWebHost").isEmpty ? "teecircle.vercel.app" : value("TEEWebHost")

        return AppConfiguration(
            supabaseURL: supabaseHost.isEmpty ? nil : URL(string: "https://\(supabaseHost)"),
            supabasePublishableKey: value("TEESupabasePublishableKey"),
            webBaseURL: URL(string: "https://\(webHost)")!,
            keychainAccessGroup: value("TeeCircleKeychainAccessGroup").nilIfEmpty,
            postHogHost: URL(string: "https://\(value("TEEPostHogHost"))"),
            postHogToken: value("TEEPostHogProjectToken"),
            googleIOSClientID: value("TEEGoogleIOSClientID"),
            googleServerClientID: value("TEEGoogleServerClientID"),
            revenueCatPublicKey: value("TEERevenueCatPublicSDKKey"),
            revenueCatTripProductID: value("TEERevenueCatTripProductID"),
            useMockData: shouldUseMockData(configuredValue: value("TEEUseMockData"))
        )
    }

    static func shouldUseMockData(
        configuredValue: String,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
#if DEBUG
        configuredValue.uppercased() == "YES" || arguments.contains("-ui-testing")
#else
        false
#endif
    }

    var isSupabaseConfigured: Bool {
        supabaseURL != nil && !supabasePublishableKey.isEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
