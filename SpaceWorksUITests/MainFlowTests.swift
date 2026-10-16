import XCTest

final class MainFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launch()
        return app
    }
    private func connect(_ app: XCUIApplication) {
        XCTAssertTrue(app.textFields["server-url"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.textFields["server-url"].tap()
        app.textFields["server-url"].typeText("https://ui-test.spaceworks.invalid\n")
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 10))
    }
    private func credentials(_ app: XCUIApplication) {
        app.textFields["username"].tap(); app.textFields["username"].typeText("maker\n")
        app.secureTextFields["password"].typeText("fixture-password\n")
        app.swipeUp()
        app.buttons["sign-in"].tap()
    }
    private func selectSpace(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["makerspace-7"].waitForExistence(timeout: 10))
        app.buttons["makerspace-7"].tap()
    }
    private func tab(_ app: XCUIApplication, _ title: String) {
        if app.tabBars.buttons[title].exists { app.tabBars.buttons[title].tap(); return }
        let item = app.descendants(matching: .any)["nav-\(title)"].firstMatch
        if !item.isHittable {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }
    func testPasswordMakerspaceSwitchProfileAndSignOut() {
        let app = launch(); connect(app); attach(app, "Sign in portrait")
        credentials(app); selectSpace(app)
        XCTAssertTrue(app.staticTexts["Welcome back, Maker."].waitForExistence(timeout: 10))
        attach(app, "Home member portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        for name in ["Inventory", "Activity", "Inbox", "Profile"] { tab(app, name) }
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        attach(app, "Profile landscape")
        app.buttons["Sign out"].tap()
        let confirmation = app.buttons.matching(identifier: "Sign out").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirmation); confirmation?.tap()
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 10))
    }
    func testMFAContinuesToMakerspaceSelection() {
        let app = launch(extra: ["--mfa"]); connect(app); credentials(app)
        XCTAssertTrue(app.textFields["mfa-code"].waitForExistence(timeout: 10))
        app.textFields["mfa-code"].tap(); app.textFields["mfa-code"].typeText("123456\n")
        app.buttons["verify"].tap(); selectSpace(app)
        XCTAssertTrue(app.staticTexts["Welcome back, Maker."].waitForExistence(timeout: 10))
    }
    func testServerFailureRemainsReviewable() {
        let app = launch(extra: ["--health-unavailable"])
        app.textFields["server-url"].tap(); app.textFields["server-url"].typeText("https://ui-test.spaceworks.invalid\n")
        XCTAssertTrue(app.staticTexts["Try again later."].waitForExistence(timeout: 10))
        attach(app, "Server failure")
    }
    func testDarkModeLargestTextPortraitAndLandscape() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["appearance"].tap(); connect(app)
        app.swipeUp(); attach(app, "Sign in largest text dark portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        app.swipeDown(); XCTAssertTrue(app.textFields["username"].exists)
        app.swipeUp(); XCTAssertTrue(app.buttons["sign-in"].exists)
        attach(app, "Sign in largest text dark landscape")
    }
    func testExploreDemoIsIsolatedAndExitsToServerSetup() {
        let app = launch(); app.buttons["explore-demo"].tap()
        XCTAssertTrue(app.staticTexts["Demo mode · sample data"].exists)
        app.buttons["Continue as member"].tap()
        app.swipeUp()
        app.textFields["demo-username"].tap(); app.textFields["demo-username"].typeText("meera\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
        app.swipeUp(); app.buttons["demo-sign-in"].tap()
        app.buttons["demo-space-0"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back, Meera Nair."].waitForExistence(timeout: 5))
        attach(app, "Isolated member demo")
        app.buttons["Exit demo"].tap()
        XCTAssertTrue(app.textFields["server-url"].exists)
        let value = app.textFields["server-url"].value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == "https://spaceworks.example")
    }
    func testOptionalIntroductionCompletesAndStaysDismissed() {
        let app = launch(extra: ["--introduction", "--reset-introduction"])
        XCTAssertTrue(app.staticTexts["Make room."].waitForExistence(timeout: 10))
        attach(app, "Introduction first page")
        app.buttons["intro-next"].tap()
        XCTAssertTrue(app.staticTexts["Borrow with confidence."].exists)
        app.buttons["intro-next"].tap(); app.buttons["intro-next"].tap()
        XCTAssertTrue(app.textFields["server-url"].exists)
        app.terminate(); app.launchArguments = ["--ui-testing", "--introduction"]; app.launch()
        XCTAssertTrue(app.textFields["server-url"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Skip introduction"].exists)
    }
    func testRecoveryUsesGeneratedRequestAndReturnsToNativeSignIn() {
        let app = launch(); connect(app)
        app.swipeUp(); app.buttons["Forgot password?"].tap()
        let email = app.textFields["account-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5)); email.tap(); email.typeText("meera@example.test")
        app.swipeUp(); app.buttons["Request recovery code"].tap()
        let code = app.textFields["account-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText("123456")
        let password = app.secureTextFields["account-password"]
        password.tap(); password.typeText("new password\n")
        let confirmation = app.secureTextFields["account-confirm-password"]
        app.swipeUp(); confirmation.tap(); confirmation.typeText("new password\n")
        app.swipeUp(); attach(app, "Password recovery review")
        app.buttons["Update password"].tap()
        XCTAssertTrue(app.staticTexts["Password updated"].waitForExistence(timeout: 5))
        app.buttons["Go to sign in"].tap()
        XCTAssertTrue(app.textFields["username"].exists)
    }
    func testPasswordVisibilityPreservesTextAndKeyboardFocus() {
        let app = launch(); connect(app)
        XCTAssertLessThanOrEqual(app.secureTextFields["password"].frame.height, 80, "A single-line password field must not consume spare tablet height")
        app.textFields["username"].tap(); app.textFields["username"].typeText("maker\n")
        app.secureTextFields["password"].typeText("sample password")
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["password"].value as? String, "sample password")
        app.textFields["password"].typeText("!")
        app.buttons["Hide password"].tap(); app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["password"].value as? String, "sample password!")
        XCTAssertTrue(app.textFields["username"].exists, "Visibility never submits sign-in")
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
