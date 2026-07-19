import XCTest

@MainActor
final class TeeCircleUITests: XCTestCase {
    private enum SwipeDirection {
        case up
        case down
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProfileSetupGateBlocksTheAppUntilNameAndUsernameExist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-needs-profile"]
        app.launch()

        // The gate replaces the whole app shell, so no tab bar and no home.
        let submit = element("profileSetup.submit", in: app)
        let appeared = submit.waitForExistence(timeout: 8)
        capture(app, named: "gate-as-test-sees-it")
        XCTAssertTrue(appeared)
        XCTAssertFalse(app.tabBars.buttons["Golfers"].exists)
        XCTAssertFalse(element("home.wordmark", in: app).exists)
        capture(app, named: "profile-setup-empty")

        enter("Jordan Bell", into: element("profileSetup.name", in: app), in: app)

        // A handle below the shared minimum keeps the gate closed.
        let usernameField = element("profileSetup.username", in: app)
        enter("ab", into: usernameField, in: app)
        XCTAssertFalse(submit.isEnabled)

        usernameField.typeText("cdef")
        dismissKeyboard(in: app)
        capture(app, named: "profile-setup-filled")
        XCTAssertTrue(submit.isEnabled)

        tap(submit, in: app)

        // Saving releases the gate and lands on the normal app shell.
        XCTAssertTrue(element("home.wordmark", in: app).waitForExistence(timeout: 6))
        XCTAssertTrue(app.tabBars.buttons["Golfers"].exists)
        XCTAssertTrue(app.staticTexts["Good morning, Jordan Bell."].exists
            || app.staticTexts["Good afternoon, Jordan Bell."].exists
            || app.staticTexts["Good evening, Jordan Bell."].exists)

        // The saved identity is what Account now shows.
        openAccountTab(in: app)
        XCTAssertTrue(app.staticTexts["Jordan Bell"].exists)
        XCTAssertTrue(app.staticTexts["@abcdef"].exists)
        capture(app, named: "profile-account")
    }

    func testGolfersTabAggregatesPartnersAcrossTripsAndOpensSharedTrip() throws {
        let app = launchFixture()

        capture(app, named: "01-home")

        let golfersTab = app.tabBars.buttons["Golfers"]
        XCTAssertTrue(golfersTab.waitForExistence(timeout: 4))
        golfersTab.tap()
        XCTAssertTrue(app.navigationBars["My Golfers"].waitForExistence(timeout: 4))
        capture(app, named: "02-golfers")

        // Sean plays both seed trips: 2 Pinehurst rounds + 1 Bandon round.
        XCTAssertTrue(app.staticTexts["Sean"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Chris"].exists)
        // An unclaimed seat still counts as someone you played with.
        XCTAssertTrue(app.staticTexts["Mike"].exists)
        XCTAssertTrue(app.staticTexts["Not on TeeCircle"].exists)
        // Luke is the signed-in fixture user and must never list himself.
        XCTAssertFalse(app.staticTexts["Luke"].exists)

        app.staticTexts["Sean"].tap()
        XCTAssertTrue(app.navigationBars["Sean"].waitForExistence(timeout: 4))
        capture(app, named: "03-golfer-detail")

        XCTAssertTrue(app.staticTexts["3"].exists, "Sean should aggregate 3 rounds across both trips")
        XCTAssertTrue(app.staticTexts["2"].exists, "Sean should aggregate 2 shared trips")
        XCTAssertTrue(app.staticTexts["Pinehurst Cup"].exists)
        XCTAssertTrue(app.staticTexts["Bandon Weekend"].exists)

        // Trip detail lives in the Rounds stack, so this must switch tabs.
        app.staticTexts["Pinehurst Cup"].tap()
        XCTAssertTrue(app.staticTexts["ROSTER"].waitForExistence(timeout: 5))
        capture(app, named: "04-trip-from-golfer")
    }

    func testAppUsesModernFullScreenViewport() throws {
        let app = launchFixture()
        let window = app.windows.firstMatch

        XCTAssertTrue(window.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            window.frame.height,
            480,
            "A 480-point window means iOS launched TeeCircle in legacy compatibility mode. Check UILaunchScreen in the built app Info.plist."
        )
    }

    func testHomeContentStaysInsideThePhoneViewport() throws {
        let app = launchFixture()
        let window = app.windows.firstMatch
        let wordmark = element("home.wordmark", in: app)
        let primaryAction = element("home.createRound", in: app)

        XCTAssertTrue(window.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(wordmark.frame.minX, window.frame.minX)
        XCTAssertLessThanOrEqual(wordmark.frame.maxX, window.frame.maxX)
        XCTAssertGreaterThanOrEqual(primaryAction.frame.minX, window.frame.minX)
        XCTAssertLessThanOrEqual(primaryAction.frame.maxX, window.frame.maxX)
    }

    func testEmailSignInProgressivelyRevealsInputsAndModes() throws {
        let app = launchFixture()

        openAccountTab(in: app)
        tap(element("account.signOut", in: app), in: app)

        let emailToggle = element("auth.email.toggle", in: app)
        XCTAssertTrue(emailToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(element("auth.email", in: app).exists)
        XCTAssertFalse(element("auth.password", in: app).exists)

        tap(emailToggle, in: app)
        XCTAssertTrue(element("auth.email", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("auth.mode.code", in: app).exists)
        XCTAssertFalse(element("auth.password", in: app).exists)

        tap(element("auth.mode.password", in: app), in: app)
        XCTAssertTrue(element("auth.password", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("auth.submit", in: app).exists)

        tap(element("auth.email.hide", in: app), in: app, direction: .down)
        XCTAssertTrue(emailToggle.waitForExistence(timeout: 3))
        XCTAssertFalse(element("auth.email", in: app).exists)
    }

    func testSignOutAndFixtureSignInRestoresHome() throws {
        let app = launchFixture()

        openAccountTab(in: app)

        tap(element("account.signOut", in: app), in: app)
        let fixtureSignIn = element("auth.fixtureClubhouse", in: app)
        XCTAssertTrue(fixtureSignIn.waitForExistence(timeout: 5))

        tap(fixtureSignIn, in: app)
        XCTAssertTrue(element("home.wordmark", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pinehurst Cup"].exists)
    }

    func testCaptainCreatesGrossTripWithSavedCardRosterAndUnlocksIt() throws {
        let app = launchFixture()
        let tripName = "UI Gross Cup"

        createReadyGrossTrip(named: tripName, in: app)

        XCTAssertTrue(app.staticTexts[tripName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["READY"].exists)
        XCTAssertTrue(app.staticTexts["GROSS"].exists)
        XCTAssertTrue(app.staticTexts["1 round · 2 players · Stableford + Skins"].exists)
        XCTAssertTrue(app.staticTexts["Pinehurst No. 2"].exists)
        XCTAssertTrue(app.staticTexts["Sean"].exists)

        tap(element("trip.openPaywall", in: app), in: app)
        let unlock = element("paywall.unlock", in: app)
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        tap(unlock, in: app)

        let start = element("trip.startTournament", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 5), "A successful fixture purchase should dismiss the paywall and entitle the trip")
        XCTAssertFalse(unlock.exists)
    }

    func testPrimaryFlowCreatesOneRoundAndPreparesAnInvite() throws {
        let app = launchFixture()

        tap(element("home.createRound", in: app), in: app)
        XCTAssertTrue(app.navigationBars["New round"].waitForExistence(timeout: 4))

        enter("UI Walking Nine", into: element("round.course", in: app), in: app)
        dismissKeyboard(in: app)
        tap(element("round.length.9", in: app), in: app)
        tap(element("round.transport.walk", in: app), in: app)
        tap(element("round.submit", in: app), in: app)

        XCTAssertTrue(app.staticTexts["UI Walking Nine"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 round · 1 player · Stableford + Skins"].exists)
        XCTAssertTrue(element("trip.invite", in: app).exists)
    }

    func testInviteeClaimsOpenRosterSeat() throws {
        let app = launchFixture(arguments: ["-ui-invitee"])

        openFixtureLiveTrip(in: app)
        let claimMike = element("trip.claim.mike", in: app)
        tap(claimMike, in: app)

        XCTAssertTrue(waitUntil(timeout: 3) { !claimMike.exists })
        XCTAssertTrue(app.staticTexts["Mike"].exists)
        XCTAssertTrue(app.staticTexts["Claimed"].firstMatch.exists)
    }

    func testLiveScoreSaveRefreshesLeaderboardRevision() throws {
        let app = launchFixture()

        openFixtureLiveTrip(in: app)
        tap(element("trip.score.round-1", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Score hole"].waitForExistence(timeout: 4))

        tap(element("score.saveHole", in: app), in: app)
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 4))

        let scoreNavigationBar = app.navigationBars["Score hole"]
        XCTAssertTrue(scoreNavigationBar.buttons.firstMatch.exists)
        scoreNavigationBar.buttons.firstMatch.tap()

        tap(element("trip.standings", in: app), in: app, direction: .down)
        XCTAssertTrue(app.navigationBars["Live standings"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["REVISION 25"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Canonical server snapshot"].exists)
    }

    func testTripUnlockCancellationKeepsPaywallAndDraft() throws {
        let app = launchFixture(arguments: ["-ui-purchase-cancel"])
        let tripName = "UI Cancelled Cup"

        createReadyGrossTrip(named: tripName, in: app)
        tap(element("trip.openPaywall", in: app), in: app)

        let unlock = element("paywall.unlock", in: app)
        XCTAssertTrue(unlock.waitForExistence(timeout: 4))
        tap(unlock, in: app)

        XCTAssertTrue(
            waitUntil(timeout: 3) { unlock.exists && unlock.isEnabled },
            "Cancelling StoreKit must leave the captain on the intact draft paywall"
        )
        XCTAssertTrue(
            app.staticTexts[
                "One-time trip purchase. No subscription. Purchase cancellation leaves your complete trip setup intact."
            ].exists
        )
        XCTAssertFalse(element("trip.startTournament", in: app).exists)
    }

    func testConvertedLegacyRoundCanRecoverCourseCardAndHandicaps() throws {
        let app = launchFixture(arguments: ["-ui-legacy-needs-setup"])

        tap(app.buttons["See all"], in: app)
        XCTAssertTrue(app.navigationBars["Previous rounds"].waitForExistence(timeout: 4))
        tap(element("legacy.convert.legacy-1", in: app), in: app)
        tap(dialogAction(identifier: "legacy.confirmCopy", label: "Create copy", in: app), in: app)

        XCTAssertTrue(app.staticTexts["Bethpage Black Trip"].waitForExistence(timeout: 5))
        tap(element("trip.continueSetup", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Converted round"].waitForExistence(timeout: 4))

        tap(element("legacy.courseCardPicker", in: app), in: app)
        tap(labeledControl("Pinehurst No. 2 · Blue", in: app), in: app)

        let handicapFields = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "legacy.handicap.")
        )
        XCTAssertTrue(waitUntil(timeout: 3) { handicapFields.count == 3 })
        for field in handicapFields.allElementsBoundByIndex {
            tap(field, in: app)
            field.typeText("10.0")
        }
        dismissKeyboard(in: app)

        let finish = element("legacy.finishSetup", in: app)
        tap(finish, in: app)
        XCTAssertTrue(app.staticTexts["Bethpage Black Trip"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.navigationBars["Converted round"].exists)
    }

    func testAccountDeletionRequiresOwnershipResolution() throws {
        let app = launchFixture()

        openAccountTab(in: app)
        tap(element("account.delete", in: app), in: app)
        tap(dialogAction(identifier: "account.confirmDelete", label: "Request deletion", in: app), in: app)

        let alert = app.alerts["TeeCircle"]
        XCTAssertTrue(alert.waitForExistence(timeout: 4))
        XCTAssertTrue(
            alert.staticTexts[
                "Fixture mode cannot delete an account. Production first checks ownership transfer and archival constraints."
            ].exists
        )
        XCTAssertTrue(alert.buttons["OK"].exists)
    }

    // MARK: - Fixtures

    private func launchFixture(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        XCTAssertTrue(element("home.wordmark", in: app).waitForExistence(timeout: 8))
        return app
    }

    /// Writes a screenshot to TEE_UI_SCREENSHOT_DIR when set, so a run can be
    /// eyeballed outside Xcode. No-op in normal CI runs.
    private func capture(_ app: XCUIApplication, named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        // Attachments default to deleteOnSuccess, which throws away exactly the
        // passing run you want to look at.
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["TEE_UI_SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    /// The account avatar moved off the Home header when the tab bar landed.
    private func openAccountTab(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Account"]
        XCTAssertTrue(tab.waitForExistence(timeout: 4))
        tab.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 3))
    }

    private func openFixtureLiveTrip(in app: XCUIApplication) {
        let title = app.staticTexts["Pinehurst Cup"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        XCTAssertTrue(app.staticTexts["ROSTER"].waitForExistence(timeout: 4))
    }

    private func createReadyGrossTrip(named tripName: String, in app: XCUIApplication) {
        tap(element("home.createTrip", in: app), in: app)
        XCTAssertTrue(app.navigationBars["The trip"].waitForExistence(timeout: 4))

        enter(tripName, into: element("create.tripName", in: app), in: app)
        dismissKeyboard(in: app)
        continueCreation(to: "The rounds", in: app)

        enter("Pinehurst No. 2", into: element("create.courseName", in: app), in: app)
        dismissKeyboard(in: app)
        continueCreation(to: "Course cards", in: app)

        tap(app.buttons["Use saved card"], in: app)
        tap(labeledControl("Pinehurst No. 2 · Blue", in: app), in: app)
        continueCreation(to: "The roster", in: app)

        tap(element("create.addRosterSeat", in: app), in: app)
        enter("Sean", into: app.textFields["Player name"], in: app)
        dismissKeyboard(in: app)
        continueCreation(to: "The competition", in: app)

        let gross = element("create.scoring.gross", in: app)
        tap(gross, in: app)
        XCTAssertTrue(waitUntil(timeout: 2) { self.element("create.continue", in: app).isEnabled })
        continueCreation(to: "Ready room", in: app)

        XCTAssertTrue(app.staticTexts[tripName].exists)
        tap(element("create.submit", in: app), in: app)
        XCTAssertTrue(app.staticTexts[tripName].waitForExistence(timeout: 5))
        XCTAssertTrue(element("trip.openPaywall", in: app).waitForExistence(timeout: 5))
    }

    private func continueCreation(to navigationTitle: String, in app: XCUIApplication) {
        tap(element("create.continue", in: app), in: app)
        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 4))
    }

    // MARK: - UI helpers

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func labeledControl(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    private func dialogAction(identifier: String, label: String, in app: XCUIApplication) -> XCUIElement {
        let identified = element(identifier, in: app)
        if identified.waitForExistence(timeout: 2) {
            return identified
        }
        let fallback = app.buttons[label]
        XCTAssertTrue(fallback.waitForExistence(timeout: 2))
        return fallback
    }

    private func enter(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        tap(field, in: app)
        field.typeText(text)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let returnKeys = ["done", "Done", "Return"]
        if let returnKey = returnKeys
            .map({ app.keyboards.buttons[$0] })
            .first(where: \.exists)
        {
            returnKey.tap()
        } else if app.navigationBars.firstMatch.exists {
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
    }

    private func tap(
        _ target: XCUIElement,
        in app: XCUIApplication,
        direction: SwipeDirection = .up,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if target.waitForExistence(timeout: 1), target.isHittable {
            target.tap()
            return
        }
        for _ in 0..<10 {
            if target.exists, target.isHittable {
                target.tap()
                return
            }
            let identifiedForm = element("round.formScroll", in: app)
            let scrollView = identifiedForm.exists ? identifiedForm : app.scrollViews.firstMatch
            switch direction {
            case .up:
                if scrollView.exists { scrollView.swipeUp() } else { app.swipeUp() }
            case .down:
                if scrollView.exists { scrollView.swipeDown() } else { app.swipeDown() }
            }
        }
        XCTFail("Could not reveal UI element '\(target)'", file: file, line: line)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }
}
