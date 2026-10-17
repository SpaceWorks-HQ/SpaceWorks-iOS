import XCTest

final class NotificationsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, _ app: XCUIApplication) { NativeUIActions.tap(element, in: app) }
    private func tab(_ app: XCUIApplication, _ name: String) {
        if app.tabBars.buttons[name].exists { tap(app.tabBars.buttons[name], app); return }
        let item = app.descendants(matching: .any)["nav-\(name)"].firstMatch
        let ready = NSPredicate(format: "exists == true AND isHittable == true")
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: item)], timeout: 3) != .completed {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        tap(item, app)
    }
    private func notifications() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launchForDeviceProfile()
        tap(app.buttons["explore-demo"], app); tap(app.buttons["Continue as member"], app)
        let username = app.textFields["demo-username"]; tap(username, app); username.typeText("meera\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
        tap(app.buttons["demo-sign-in"], app); tap(app.buttons["demo-space-0"], app)
        XCTAssertTrue(app.staticTexts["Welcome back, Meera Nair."].waitForExistence(timeout: 10))
        tab(app, "Profile"); tap(app.descendants(matching: .any)["notifications-entry"].firstMatch, app)
        return app
    }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testPermissionDeniedAndUnauthorizedTapHaveRecoverableInAppStates() {
        let app = notifications(); tap(app.switches["Preview permission denied"], app)
        XCTAssertTrue(app.staticTexts["Notifications are off for this device."].exists)
        tap(app.buttons["Open system settings"], app)
        XCTAssertTrue(app.staticTexts["notification-preview-feedback"].exists); XCTAssertEqual(app.state, .runningForeground)
        tap(app.switches["Preview permission denied"], app); tap(app.buttons["enable-demo-notifications"], app)
        tap(app.buttons["demo-push-denied"], app)
        XCTAssertTrue(app.staticTexts["mobile-link-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mobile-link-error"].label, "This makerspace isn't available to your account.")
        capture("Notification permission and authorization refusal")
        tap(app.buttons["Dismiss"], app)
        XCTAssertTrue(app.buttons["demo-push-product"].exists)
    }
    func testNotificationRefetchOpensProductAndAnotherAuthorizedMakerspaceInboxAcrossRotation() {
        let app = notifications(); tap(app.buttons["enable-demo-notifications"], app)
        tap(app.buttons["demo-push-product"], app)
        XCTAssertTrue(app.staticTexts["Digital multimeter"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Add to request"].exists); capture("Authorized notification opens fresh inventory detail")
        tab(app, "Profile")
        if !app.buttons["demo-push-other-space"].exists { tap(app.descendants(matching: .any)["notifications-entry"].firstMatch, app) }
        tap(app.buttons["demo-push-other-space"], app)
        XCTAssertTrue(app.buttons["Mark all as read"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Maker Space Bengaluru"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: app)], timeout: 5), .completed)
        capture("Notification switches authorized makerspace then opens Inbox landscape")
    }
}
