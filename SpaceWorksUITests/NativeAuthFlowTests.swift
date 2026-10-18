import XCTest

/// Live native sign-in journeys against the Debug-only URLProtocol fixture server.
final class NativeAuthFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launchForDeviceProfile()
        let server = app.textFields["server-url"]
        XCTAssertTrue(server.waitForExistence(timeout: 10))
        NativeUIActions.tap(server, in: app)
        server.typeText("https://ui-test.spaceworks.invalid\n")
        return app
    }
    private func attach(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func signIn(_ app: XCUIApplication) {
        let username = app.textFields["username"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
        NativeUIActions.tap(username, in: app); username.typeText("maker\n")
        app.secureTextFields["password"].typeText("fixture-password\n")
        NativeUIActions.tap(app.buttons["sign-in"], in: app)
    }

    func testServerMinimumVersionBlocksSignInAndOffersARecheck() {
        let app = launch(["--native-min-version"])
        XCTAssertTrue(app.staticTexts["Update required"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["minimum-version"].exists)
        XCTAssertFalse(app.textFields["username"].exists, "Sign-in stays unavailable below the minimum")
        attach("Update required")
        NativeUIActions.tap(app.buttons["check-update"], in: app)
        XCTAssertTrue(app.staticTexts["Update required"].waitForExistence(timeout: 10))
    }

    func testPhoneSignInReachesMakerspaceSelection() {
        let app = launch(["--native-providers"])
        let phoneButton = app.buttons["provider-phone"]
        XCTAssertTrue(phoneButton.waitForExistence(timeout: 10))
        attach("Native sign-in methods")
        NativeUIActions.tap(phoneButton, in: app)
        let number = app.textFields["phone-number"]
        XCTAssertTrue(number.waitForExistence(timeout: 10))
        NativeUIActions.tap(number, in: app)
        number.typeText("+15551234567")
        NativeUIActions.tap(app.buttons["phone-send"], in: app)
        let code = app.textFields["phone-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        NativeUIActions.tap(code, in: app)
        code.typeText("123456")
        attach("Phone verification code")
        NativeUIActions.tap(app.buttons["phone-verify"], in: app)
        XCTAssertTrue(app.buttons["makerspace-7"].waitForExistence(timeout: 10))
    }

    func testSuperadminAccountIsSentToTheWebConsole() {
        let app = launch(["--superadmin"])
        signIn(app)
        XCTAssertTrue(app.staticTexts["Use the web console"].waitForExistence(timeout: 10))
        attach("Superadmin refusal")
        NativeUIActions.tap(app.buttons["web-console-back"], in: app)
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 10))
    }

    private func openProfile(_ app: XCUIApplication) {
        let space = app.buttons["makerspace-7"]
        XCTAssertTrue(space.waitForExistence(timeout: 10)); NativeUIActions.tap(space, in: app)
        XCTAssertTrue(app.staticTexts["Welcome back, Maker."].waitForExistence(timeout: 10))
        if app.tabBars.buttons["Profile"].exists { app.tabBars.buttons["Profile"].tap(); return }
        let item = app.buttons["nav-Profile"]
        let readiness = NativeUIActions.readiness(in: app)
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: readiness, object: item)], timeout: 3) != .completed {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Show Sidebar", "Toggle Sidebar")).firstMatch
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: readiness, object: sidebar)], timeout: 10), .completed)
            sidebar.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: readiness, object: item)], timeout: 10), .completed)
        }
        NativeUIActions.tap(item, in: app)
    }

    func testNativeStaffSessionOpensTheLiveStaffQueue() {
        let app = launch(["--native-staff"])
        signIn(app); openProfile(app)
        let tools = app.buttons["staff-tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        NativeUIActions.tap(tools, in: app)
        let requests = app.buttons["staff-requests"]
        XCTAssertTrue(requests.waitForExistence(timeout: 10)); NativeUIActions.tap(requests, in: app)
        XCTAssertTrue(app.buttons["staff-request-601"].waitForExistence(timeout: 10), "The live pending queue comes from the generated admin operation")
        attach("Live staff queue")
    }

    func testMemberSessionHasNoStaffTools() {
        let app = launch([])
        signIn(app); openProfile(app)
        XCTAssertTrue(app.buttons["sign-out-everywhere"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["staff-tools"].exists)
    }

    func testSignOutEverywhereReturnsToSignIn() {
        let app = launch([])
        signIn(app); openProfile(app)
        let everywhere = app.buttons["sign-out-everywhere"]
        XCTAssertTrue(everywhere.waitForExistence(timeout: 10))
        NativeUIActions.tap(everywhere, in: app)
        let confirmation = app.buttons.matching(identifier: "Sign out everywhere").allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "sign-out-everywhere" }
            ?? app.sheets.buttons["Sign out everywhere"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap()
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Signed out on every device and browser."].exists)
    }
}
