import XCTest

final class MemberFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func demo(_ argument: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (argument.map { [$0] } ?? [])
        app.launch()
        app.buttons["explore-demo"].tap(); app.buttons["Continue as member"].tap()
        app.swipeUp(); app.textFields["demo-username"].tap(); app.textFields["demo-username"].typeText("meera\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
        app.swipeUp(); app.buttons["demo-sign-in"].tap(); app.buttons["demo-space-0"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back, Meera Nair."].waitForExistence(timeout: 10))
        return app
    }
    private func tab(_ app: XCUIApplication, _ name: String) {
        if app.tabBars.buttons[name].exists { app.tabBars.buttons[name].tap(); return }
        let item = app.descendants(matching: .any)["nav-\(name)"].firstMatch
        if !item.isHittable {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }
    func testMemberInventorySearchDetailAndInboxRead() {
        let app = demo()
        app.buttons["Browse inventory"].tap()
        let search = app.textFields["inventory-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); XCTAssertTrue(search.isHittable); search.tap(); search.typeText("multimeter\n")
        let product = app.buttons["product-1"].firstMatch
        let link = app.descendants(matching: .any)["product-1"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        if product.exists { product.tap() } else { link.tap() }
        XCTAssertTrue(app.staticTexts["About this item"].waitForExistence(timeout: 5))
        capture("Inventory item detail")
        if app.navigationBars.buttons["Inventory"].exists { app.navigationBars.buttons["Inventory"].tap() }
        tab(app, "Inbox")
        XCTAssertTrue(app.staticTexts["Your kit is ready"].waitForExistence(timeout: 5))
        let unread = app.segmentedControls.buttons["Unread"]
        XCTAssertTrue(unread.isHittable); unread.tap()
        app.buttons["Mark all as read"].tap()
        XCTAssertTrue(app.staticTexts["Nothing here yet."].waitForExistence(timeout: 5))
        capture("Inbox confirmed read state")
        app.buttons["Exit demo"].tap()
        XCTAssertTrue(app.textFields["server-url"].exists)
    }
    func testInventoryFilteredEmptyCanRecover() {
        let app = demo(); tab(app, "Inventory")
        let search = app.textFields["inventory-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); XCTAssertTrue(search.isHittable); search.tap(); search.typeText("nothing-matches\n")
        XCTAssertTrue(app.staticTexts["No items match these filters"].waitForExistence(timeout: 5))
        app.buttons["Clear filters"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["product-1"].firstMatch.waitForExistence(timeout: 5))
    }
    func testEmptyAndErrorDataDoNotBecomePopulatedSuccess() {
        let empty = demo("--demo-empty"); tab(empty, "Inventory")
        XCTAssertTrue(empty.staticTexts["No items yet"].waitForExistence(timeout: 5)); capture("Inventory empty")
        empty.terminate()
        let offline = demo("--demo-error"); tab(offline, "Inventory")
        XCTAssertTrue(offline.staticTexts["Couldn't connect. Try again."].waitForExistence(timeout: 5))
        XCTAssertFalse(offline.descendants(matching: .any)["product-1"].firstMatch.exists)
        XCTAssertTrue(offline.buttons["Try again"].exists); capture("Inventory retry error")
    }
    func testRevokedMembershipCardNeverShowsDemoQR() {
        let app = demo("--demo-revoked")
        let card = app.buttons["View membership card"]
        for _ in 0..<6 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        XCTAssertTrue(app.staticTexts["Your membership card isn't active. Ask the front desk for help."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["Simulated membership card QR code"].exists)
        capture("Revoked membership card")
        app.buttons["Done"].tap()
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
