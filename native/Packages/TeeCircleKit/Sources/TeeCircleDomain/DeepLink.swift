import Foundation

public enum TeeCircleDeepLink: Equatable, Hashable, Sendable {
    case tripInvite(token: String)

    /// The host emitted by TeeCircle until the custom domain is connected.
    public static let canonicalHost = "teecircle.vercel.app"

    /// Reserved for the custom-domain cutover; links already remain routable.
    public static let futureCustomDomainHost = "teecircle.app"

    public static let supportedHosts: Set<String> = [
        canonicalHost,
        futureCustomDomainHost,
        "www.teecircle.app",
    ]

    public init?(url: URL, supportedHosts: Set<String> = Self.supportedHosts) {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              supportedHosts.contains(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let encodedSegments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard encodedSegments.count == 2,
              encodedSegments[0] == "t",
              let token = String(encodedSegments[1]).removingPercentEncoding,
              Self.isValidInviteToken(token)
        else {
            return nil
        }

        self = .tripInvite(token: token)
    }

    public var canonicalURL: URL {
        switch self {
        case let .tripInvite(token):
            var components = URLComponents()
            components.scheme = "https"
            components.host = Self.canonicalHost
            components.path = "/t/\(token)"
            // `token` has already passed the strict URL-safe character check.
            return components.url!
        }
    }

    private static func isValidInviteToken(_ token: String) -> Bool {
        guard token.count >= 40, token.count <= 128 else { return false }
        return token.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
