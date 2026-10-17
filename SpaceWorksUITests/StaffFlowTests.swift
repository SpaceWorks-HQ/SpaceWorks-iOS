import XCTest

final class StaffFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) { NativeUIActions.tap(element, in: app) }
    private func staff(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + extra; app.launch()
        tap(app.buttons["explore-demo"], in: app)
        tap(app.segmentedControls["demo-role"].buttons["Staff"], in: app)
        tap(app.buttons["Continue as staff"], in: app)
        let username = app.textFields["demo-username"]
        tap(username, in: app); username.typeText("staff\n")
        let password = app.secureTextFields["demo-password"]; XCTAssertTrue(password.waitForExistence(timeout: 5)); password.typeText("sample\n")
        tap(app.buttons["demo-sign-in"], in: app); tap(app.buttons["demo-space-0"], in: app)
        if app.tabBars.buttons["Profile"].exists { tap(app.tabBars.buttons["Profile"], in: app) }
        else {
            let profile = app.descendants(matching: .any)["nav-Profile"].firstMatch
            if !profile.isHittable {
                let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
                if sidebar.exists { sidebar.tap() }
            }
            tap(profile, in: app)
        }
        tap(app.buttons["staff-tools"], in: app)
        return app
    }
    private func scan(_ payload: String, app: XCUIApplication) {
        let field = app.textFields["scanner-manual-code"]
        tap(field, in: app); field.typeText(payload + "\n")
    }
    private func recordHandover(in app: XCUIApplication) {
        // Native confirmation dialogs have separate title/action scroll regions.
        XCTAssertTrue(app.staticTexts["Record this handout?"].waitForExistence(timeout: 5))
        let action = app.buttons["Record handover"]
        XCTAssertTrue(action.waitForExistence(timeout: 5)); XCTAssertTrue(action.isHittable)
        let frame = action.frame
        XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite))
        XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(frame))
        attach("Native staff handover confirmation")
        action.tap()
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testGuidedIssueRequiresBorrowerEvidenceAndFinalConfirmation() {
        let app = staff()
        tap(app.buttons["staff-requests"], in: app); tap(app.buttons["staff-request-queue"], in: app)
        tap(app.buttons["Ready for issue"], in: app); tap(app.buttons["staff-request-602"], in: app)
        tap(app.buttons["Start guided issue"], in: app); tap(app.buttons["Scan handover code"], in: app)
        scan("DEMO-BOX", app: app); tap(app.buttons["staff-handover-next"], in: app)
        XCTAssertFalse(app.buttons["staff-handover-next"].isEnabled)
        tap(app.switches["staff-borrower-checked"], in: app); tap(app.buttons["staff-handover-next"], in: app)
        tap(app.buttons["staff-handover-next"], in: app)
        tap(app.buttons["staff-sample-photo"], in: app); tap(app.buttons["staff-upload-photo"], in: app)
        for button in app.buttons.matching(identifier: "Start count").allElementsBoundByIndex { tap(button, in: app) }
        XCTAssertTrue(app.buttons["staff-handover-confirm"].waitForExistence(timeout: 5)); attach("Staff issue evidence and review")
        tap(app.buttons["staff-handover-confirm"], in: app)
        XCTAssertFalse(app.descendants(matching: .any)["staff-handover-recorded"].firstMatch.exists)
        recordHandover(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["staff-handover-recorded"].firstMatch.waitForExistence(timeout: 10)); attach("Staff handover recorded")
    }
    func testEventScanShowsPersonBeforeAttendanceConfirmation() {
        let app = staff(); tap(app.buttons["staff-events"], in: app)
        tap(app.staticTexts["Sample repair workshop"].firstMatch, in: app)
        tap(app.buttons["Scan check-in code"], in: app); scan("DEMO-EVENT", app: app)
        XCTAssertTrue(app.buttons["staff-confirm-attendance"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["staff-attendance-recorded"].firstMatch.exists); attach("Staff check-in review person")
        tap(app.buttons["staff-confirm-attendance"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["staff-attendance-recorded"].firstMatch.waitForExistence(timeout: 10)); attach("Staff attendance recorded")
    }
}
