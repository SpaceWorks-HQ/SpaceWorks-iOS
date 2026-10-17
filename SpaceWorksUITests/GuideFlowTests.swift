import XCTest

final class GuideFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) { NativeUIActions.tap(element, in: app) }
    private func demo(staff: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launchForDeviceProfile()
        tap(app.buttons["explore-demo"], in: app)
        if staff { tap(app.segmentedControls["demo-role"].buttons["Staff"], in: app) }
        tap(app.buttons[staff ? "Continue as staff" : "Continue as member"], in: app)
        let username = app.textFields["demo-username"]; tap(username, in: app); username.typeText(staff ? "staff\n" : "meera\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
        tap(app.buttons["demo-sign-in"], in: app); tap(app.buttons["demo-space-0"], in: app)
        XCTAssertTrue(app.staticTexts[staff ? "Welcome back, Arjun Rao." : "Welcome back, Meera Nair."].waitForExistence(timeout: 10))
        return app
    }
    private func tab(_ name: String, app: XCUIApplication) {
        if app.tabBars.buttons[name].exists { tap(app.tabBars.buttons[name], in: app); return }
        let target = app.descendants(matching: .any)["nav-\(name)"].firstMatch
        if !target.isHittable {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        tap(target, in: app)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func makerspace(_ name: String, app: XCUIApplication) {
        let switcher = app.buttons["demo-makerspace-switcher"]
        tap(switcher, in: app); tap(app.buttons[name], in: app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", name), object: switcher)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
    func testMemberGuideReplaysIntroductionAndRestoresDismissedTips() {
        let app = demo(); tap(app.buttons["guidance-dismiss"], in: app)
        XCTAssertFalse(app.buttons["guidance-dismiss"].exists)
        makerspace("Maker Space Bengaluru", app: app)
        tap(app.buttons["guidance-dismiss"], in: app)
        makerspace("Fab Lab Kochi", app: app)
        XCTAssertFalse(app.buttons["guidance-dismiss"].exists, "Returning to a makerspace must preserve its dismissed tip")
        tab("Profile", app: app); tap(app.buttons["app-guide"], in: app)
        XCTAssertFalse(app.descendants(matching: .any)["guide-staff"].firstMatch.exists)
        tap(app.descendants(matching: .any)["guide-borrow"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Open Inventory, search or filter, then choose an item. Add the items you need and review quantities before submitting your request. Staff confirm availability, collection and borrowing terms.")).firstMatch.exists)
        capture("Member app guide")
        tap(app.buttons["guide-reset-tips"], in: app)
        XCTAssertTrue(app.staticTexts["guide-tips-reset"].waitForExistence(timeout: 5))
        tap(app.buttons["guide-replay-introduction"], in: app)
        XCTAssertTrue(app.buttons["Skip introduction"].waitForExistence(timeout: 5)); capture("Introduction replay from app guide")
        tap(app.buttons["Skip introduction"], in: app)
        tap(app.buttons["guide-done"], in: app); tab("Home", app: app)
        XCTAssertTrue(app.buttons["guidance-dismiss"].waitForExistence(timeout: 5))
        tab("Activity", app: app); tap(app.buttons["Find a space"], in: app)
        tap(app.descendants(matching: .any)["space-00000000-0000-0000-0000-000000000031"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["Book a space"].waitForExistence(timeout: 5))
        tab("Home", app: app); tap(app.buttons["View bookings"], in: app)
        XCTAssertTrue(app.navigationBars["Bookings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Workshop bench"].exists)
        capture("Start here opens bookings above retained activity draft")
        tab("Home", app: app)
        makerspace("Maker Space Bengaluru", app: app)
        XCTAssertFalse(app.buttons["guidance-dismiss"].exists, "Replay affects only its owning makerspace")
    }
    func testStaffGuideExplainsEvidenceAndExplicitConfirmation() {
        let app = demo(staff: true); tab("Profile", app: app); tap(app.buttons["app-guide"], in: app)
        let section = app.descendants(matching: .any)["guide-staff"].firstMatch
        tap(section, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Scanning finds a record; it never confirms handover or attendance by itself. Check the resolved person, then choose Confirm check-in. If access changes or a conflict appears, refresh before continuing.")).firstMatch.exists)
        capture("Staff guide and camera explanation")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
