import XCTest

final class MainFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launch()
        return app
    }
    func testConnectToShellAndAllMemberTabs() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Connect to your Space Works server"].waitForExistence(timeout: 10))
        app.textFields["server-url"].tap()
        app.textFields["server-url"].typeText("https://ui-test.spaceworks.invalid")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.staticTexts["Sign-in will be available in the next phase."].waitForExistence(timeout: 10))
        attach(app, "Home sign-in placeholder")
        for name in ["Home", "Inventory", "Activity", "Inbox", "Profile"] {
            app.tabBars.buttons[name].tap()
            XCTAssertTrue(app.staticTexts["Nothing here yet."].exists)
        }
        XCTAssertFalse(app.tabBars.buttons["Staff"].exists)
        attach(app, "Profile and member tabs")
        app.buttons["Change server"].tap()
        XCTAssertTrue(app.textFields["server-url"].exists)
        attach(app, "Server settings")
    }
    func testInvalidURLAndServerFailureRemainReviewable() {
        let app = launch(extra: ["--health-unavailable"])
        app.textFields["server-url"].tap()
        app.textFields["server-url"].typeText("https://ui-test.spaceworks.invalid")
        app.buttons["connect"].tap()
        XCTAssertTrue(app.staticTexts["Try again later."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["server-url"].exists)
        XCTAssertFalse(app.tabBars.buttons["Staff"].exists)
        attach(app, "Server failure")
    }
    func testDarkModeAndLargestDynamicType() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["appearance"].tap()
        XCTAssertTrue(app.buttons["Light mode"].exists)
        XCTAssertTrue(app.textFields["server-url"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["connect"].isHittable)
        attach(app, "Dark mode and large text")
        app.textFields["server-url"].tap()
        app.textFields["server-url"].typeText("https://ui-test.spaceworks.invalid\n")
        XCTAssertTrue(app.staticTexts["Sign in"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Nothing here yet."].isHittable)
        attach(app, "Home with largest text")
        for name in ["Inventory", "Activity", "Inbox", "Profile"] {
            app.tabBars.buttons[name].tap()
            XCTAssertTrue(app.staticTexts["Nothing here yet."].isHittable)
        }
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = name
        item.lifetime = .keepAlways
        add(item)
    }
}
