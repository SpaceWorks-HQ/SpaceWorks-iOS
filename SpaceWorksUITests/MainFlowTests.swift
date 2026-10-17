import XCTest

final class MainFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launchForDeviceProfile()
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
        let item = app.buttons["nav-\(title)"]
        let readiness = NSPredicate(format: "exists == true AND isEnabled == true AND isHittable == true")
        let ready = XCTNSPredicateExpectation(predicate: readiness, object: item)
        if XCTWaiter.wait(for: [ready], timeout: 3) != .completed {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Show Sidebar", "Toggle Sidebar")).firstMatch
            let sidebarReady = XCTNSPredicateExpectation(predicate: readiness, object: sidebar)
            XCTAssertEqual(XCTWaiter.wait(for: [sidebarReady], timeout: 3), .completed)
            sidebar.tap()
            let opened = XCTNSPredicateExpectation(predicate: readiness, object: item)
            XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 3), .completed)
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }
    func testPasswordMakerspaceSwitchProfileAndSignOut() {
        let app = launch(); connect(app); attach(app, "Sign in initial device layout")
        credentials(app); selectSpace(app)
        XCTAssertTrue(app.staticTexts["Welcome back, Maker."].waitForExistence(timeout: 10))
        attach(app, "Home member portrait")
        app.rotateToLandscapeAndWait()
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
        let code = app.textFields["mfa-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        NativeUIActions.tap(code, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attach(app, "MFA authentication code ready")
        code.typeText("123456\n")
        XCTAssertEqual(code.value as? String, "123456")
        NativeUIActions.tap(app.buttons["verify"], in: app); selectSpace(app)
        XCTAssertTrue(app.staticTexts["Welcome back, Maker."].waitForExistence(timeout: 10))
    }
    func testServerFailureRemainsReviewable() {
        let app = launch(extra: ["--health-unavailable"])
        app.textFields["server-url"].tap(); app.textFields["server-url"].typeText("https://ui-test.spaceworks.invalid\n")
        XCTAssertTrue(app.staticTexts["Try again later."].waitForExistence(timeout: 10))
        attach(app, "Server failure")
    }
    func testDarkModeLargestTextPortraitAndLandscape() {
        let app = launch(extra: ["--ui-start-light", "--ui-start-portrait", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["appearance"].tap(); connect(app)
        let scroll = app.scrollViews["sign-in-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        func revealActions() {
            let signIn = app.buttons["sign-in"]
            let create = app.buttons["create-account"]
            XCTAssertTrue(signIn.waitForExistence(timeout: 5))
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            for attempt in 0..<24 {
                let applicationFrame = app.frame
                let scrollFrame = scroll.frame.intersection(applicationFrame)
                let appearance = app.buttons["appearance"]
                XCTAssertTrue(appearance.exists)
                let headerFrame = appearance.frame
                let signInFrame = signIn.frame
                let createFrame = create.frame
                let frames = [applicationFrame, scrollFrame, headerFrame, signInFrame, createFrame]
                XCTAssertTrue(frames.allSatisfy { [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) && $0.width > 0 && $0.height > 0 })
                XCTAssertTrue(appearance.isHittable)
                let visibleTop = max(scrollFrame.minY, headerFrame.maxY)
                let viewport = CGRect(x: scrollFrame.minX + 2, y: visibleTop + 2,
                                      width: scrollFrame.width - 4, height: scrollFrame.maxY - visibleTop - 4)
                XCTAssertGreaterThan(viewport.width, 0)
                XCTAssertGreaterThan(viewport.height, 0)
                print("Sign-in actions attempt=\(attempt) signIn=\(signInFrame) create=\(createFrame) viewport=\(viewport)")
                if viewport.contains(signInFrame), viewport.contains(createFrame) {
                    XCTAssertTrue(signIn.isEnabled && signIn.isHittable)
                    XCTAssertTrue(create.isEnabled && create.isHittable)
                    XCTAssertEqual(app.state, .runningForeground)
                    return
                }
                XCTAssertTrue(scroll.isHittable)
                let actionsFrame = signInFrame.union(createFrame)
                // Center the two controls within real slack instead of repeatedly aligning a clipped edge.
                let translation = viewport.midY - actionsFrame.midY
                let adjustmentLimit = min(120, viewport.height * 0.4)
                if abs(translation) <= adjustmentLimit {
                    let movement = (translation < 0 ? -1.0 : 1.0) * min(max(abs(translation), 12), adjustmentLimit)
                    let x = viewport.minX + 12
                    let startY = viewport.midY - movement / 2
                    let endY = viewport.midY + movement / 2
                    let dragFrame = CGRect(x: x - 2, y: min(startY, endY) - 2, width: 4, height: abs(movement) + 4)
                    XCTAssertTrue(viewport.contains(dragFrame) && scrollFrame.contains(dragFrame))
                    let controls = app.buttons.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex
                        + app.secureTextFields.allElementsBoundByIndex + app.textViews.allElementsBoundByIndex
                    for control in controls where control.exists {
                        let frame = control.frame
                        if [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite), frame.width > 0, frame.height > 0 {
                            XCTAssertFalse(frame.intersects(dragFrame), "The reveal gutter must not intersect an interactive control")
                        }
                    }
                    print("Sign-in short reveal path=\(dragFrame) visibleViewport=\(viewport)")
                    let origin = app.coordinate(withNormalizedOffset: .zero)
                    origin.withOffset(CGVector(dx: x - applicationFrame.minX, dy: startY - applicationFrame.minY)).press(forDuration: 0.05,
                        thenDragTo: origin.withOffset(CGVector(dx: x - applicationFrame.minX, dy: endY - applicationFrame.minY)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
                } else if translation > 0 { scroll.swipeDown(velocity: .slow) }
                else { scroll.swipeUp(velocity: .slow) }
            }
            XCTFail("Sign-in and Create account actions must both fit the visible sign-in scroll viewport")
        }
        revealActions(); attach(app, "Sign in largest text dark portrait")
        app.rotateToLandscapeAndWait()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        scroll.swipeDown(velocity: .slow); XCTAssertTrue(app.textFields["username"].exists)
        revealActions(); XCTAssertTrue(app.buttons["sign-in"].exists)
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
        app.terminate(); app.launchArguments = ["--ui-testing", "--introduction"]; app.launchForDeviceProfile()
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
