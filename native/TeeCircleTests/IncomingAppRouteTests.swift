import XCTest
@testable import TeeCircle

final class IncomingAppRouteTests: XCTestCase {
    func testParsesInternalLiveActivityTripRoute() throws {
        let url = try XCTUnwrap(URL(string: "teecircle://trip/92000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(
            IncomingAppRoute(url: url),
            .trip("92000000-0000-4000-8000-000000000001")
        )
    }

    func testParsesCurrentAndFutureUniversalInviteRoutes() throws {
        let token = String(repeating: "a", count: 48)
        XCTAssertEqual(
            IncomingAppRoute(url: try XCTUnwrap(URL(string: "https://teecircle.vercel.app/t/\(token)"))),
            .invite(token)
        )
        XCTAssertEqual(
            IncomingAppRoute(url: try XCTUnwrap(URL(string: "https://teecircle.app/t/\(token)"))),
            .invite(token)
        )
        XCTAssertNil(IncomingAppRoute(url: try XCTUnwrap(URL(string: "teecircle://login-callback/t/\(token)"))))
        XCTAssertNil(IncomingAppRoute(url: try XCTUnwrap(URL(string: "https://teecircle.app/privacy/t/\(token)"))))
    }
}
