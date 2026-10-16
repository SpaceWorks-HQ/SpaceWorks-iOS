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
        app.textFields["username"].tap(); app.textFields["username"].typeText("maker")
        app.secureTextFields["password"].tap(); app.secureTextFields["password"].typeText("fixture-password\n")
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
        for name in ["Inventory", "Activity", "Inbox", "Profile"] { tab(app, name) }
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        attach(app, "Profile landscape")
        app.buttons["Sign out"].tap()
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
        app.swipeDown(); XCTAssertTrue(app.textFields["username"].exists)
        app.swipeUp(); XCTAssertTrue(app.buttons["sign-in"].exists)
        attach(app, "Sign in largest text dark landscape")
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
