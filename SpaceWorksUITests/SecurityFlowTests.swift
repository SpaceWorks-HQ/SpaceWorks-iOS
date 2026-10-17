import XCTest

final class SecurityFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    func testIsolatedEmailVerificationPreviewContinuesToMakerspaceSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launchForDeviceProfile()
        NativeUIActions.tap(app.buttons["explore-demo"], in: app); NativeUIActions.tap(app.buttons["Continue as member"], in: app)
        let username = app.textFields["demo-username"]; NativeUIActions.tap(username, in: app); username.typeText("unverified\n")
        app.secureTextFields["demo-password"].typeText("sample\n"); NativeUIActions.tap(app.buttons["demo-sign-in"], in: app)
        XCTAssertTrue(app.staticTexts["Confirm your email"].waitForExistence(timeout: 10))
        let guidance = app.staticTexts["No message is sent in this demo. Use the sample verification code 123456."]
        for _ in 0..<3 where !guidance.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        XCTAssertTrue(guidance.isHittable, "Sample instructions must be visible before using the code")
        NativeUIActions.tap(app.buttons["Send another code"], in: app)
        XCTAssertTrue(app.staticTexts["Demo code ready. Use 123456. No email was sent."].waitForExistence(timeout: 5))
        let code = app.textFields["account-code"]; NativeUIActions.tap(code, in: app); code.typeText("123456")
        NativeUIActions.tap(app.buttons["Confirm email"], in: app)
        XCTAssertTrue(app.staticTexts["Email confirmed."].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Isolated email verification preview"; attachment.lifetime = .keepAlways; add(attachment)
        NativeUIActions.tap(app.buttons["Done"], in: app)
        XCTAssertTrue(app.buttons["demo-space-0"].waitForExistence(timeout: 10))
    }
    func testRequiredPasswordUpdateReturnsToFreshSignIn() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--temporary-password"]; app.launchForDeviceProfile()
        let server = app.textFields["server-url"]; NativeUIActions.tap(server, in: app); server.typeText("https://ui-test.spaceworks.invalid\n")
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 10))
        NativeUIActions.tap(app.textFields["username"], in: app); app.textFields["username"].typeText("maker\n")
        app.secureTextFields["password"].typeText("temporary\n"); NativeUIActions.tap(app.buttons["sign-in"], in: app)
        XCTAssertTrue(app.secureTextFields["current-password"].waitForExistence(timeout: 10))
        for (identifier, value) in [("current-password", "temporary"), ("new-password", "ReplacementPass!123"), ("confirm-password", "ReplacementPass!123")] {
            let field = app.secureTextFields[identifier]; NativeUIActions.tap(field, in: app); field.typeText(value + "\n")
        }
        NativeUIActions.tap(app.buttons["Update password"], in: app)
        XCTAssertTrue(app.textFields["username"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Password updated. Sign in again."].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Required password update requires fresh native authentication"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
