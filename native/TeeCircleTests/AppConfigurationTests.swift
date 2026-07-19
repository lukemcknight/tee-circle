import XCTest
@testable import TeeCircle

final class AppConfigurationTests: XCTestCase {
    func testNormalDebugLaunchUsesLiveBackendByDefault() {
        XCTAssertFalse(
            AppConfiguration.shouldUseMockData(
                configuredValue: "NO",
                arguments: ["TeeCircle"]
            )
        )
    }

    func testUITestLaunchArgumentOptsIntoFixtures() {
        XCTAssertTrue(
            AppConfiguration.shouldUseMockData(
                configuredValue: "NO",
                arguments: ["TeeCircle", "-ui-testing"]
            )
        )
    }
}
