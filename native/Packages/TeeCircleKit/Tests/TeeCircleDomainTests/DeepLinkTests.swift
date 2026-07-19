import XCTest
import TeeCircleDomain

final class DeepLinkTests: XCTestCase {
    private let token = "abcdefghijklmnop_123456789-XYZ_abcdefghijklmnop"

    func testParsesCurrentAndFutureCustomDomainTripLinks() throws {
        let current = try XCTUnwrap(URL(string: "https://teecircle.vercel.app/t/\(token)"))
        let futureCustomDomain = try XCTUnwrap(
            URL(string: "https://teecircle.app/t/\(token)?utm_source=messages")
        )

        XCTAssertEqual(TeeCircleDeepLink(url: current), .tripInvite(token: token))
        XCTAssertEqual(TeeCircleDeepLink(url: futureCustomDomain), .tripInvite(token: token))
    }

    func testCanonicalURLUsesCurrentVercelHost() {
        XCTAssertEqual(
            TeeCircleDeepLink.tripInvite(token: token).canonicalURL.absoluteString,
            "https://teecircle.vercel.app/t/\(token)"
        )
    }

    func testRejectsUnsafeOrUnrelatedLinks() throws {
        let links = [
            "http://teecircle.app/t/\(token)",
            "https://attacker.example/t/\(token)",
            "https://teecircle.app/t/short",
            "https://teecircle.app/t/\(token)/extra",
            "https://teecircle.app/t/abcdefghijklmnop%2Fescape",
        ]

        for value in links {
            XCTAssertNil(TeeCircleDeepLink(url: try XCTUnwrap(URL(string: value))), value)
        }
    }
}
