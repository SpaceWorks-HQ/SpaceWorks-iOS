import XCTest

final class MemberActionsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? app.scrollViews.firstMatch
            if element.exists {
                let insideScroll = scroll.exists && !element.identifier.isEmpty && scroll.descendants(matching: .any).matching(identifier: element.identifier).firstMatch.exists
                if element.isHittable && !insideScroll { element.tap(); return }
                let frame = element.frame
                let viewport = visibleContent(scroll, app)
                let visible = frame.intersection(viewport)
                if element.isHittable, !visible.isNull, visible.width > 4, visible.height > 4,
                   viewport.insetBy(dx: 2, dy: 2).contains(CGPoint(x: frame.midX, y: frame.midY)) {
                    // Use the native activation point. A wide Toggle's label centre is not
                    // its switch thumb; coordinates are only needed for clipped text fields.
                    element.tap(); return
                }
                if (element.elementType == .textField || element.elementType == .secureTextField),
                   element.isHittable, !visible.isNull, visible.width > 8, visible.height > 8 {
                    element.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX - frame.minX, dy: visible.midY - frame.minY)).tap(); return
                }
                drag(scroll, app, down: frame.midY < viewport.midY)
            } else { drag(scroll, app, down: false) }
        }
        capture("Unreachable action " + element.identifier)
        XCTFail("Action must be reachable: \(element.identifier)")
    }
    private func visibleContent(_ scroll: XCUIElement, _ app: XCUIApplication) -> CGRect {
        var viewport = scroll.exists ? scroll.frame.intersection(app.frame) : app.frame
        // SwiftUI's accessibility ScrollView frame includes content UNDER native bars.
        // A target can be marked hittable there while its coordinate activates another tab.
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
            let frame = bar.frame
            if frame.intersects(viewport), frame.midY < viewport.midY {
                let bottom = viewport.maxY; viewport.origin.y = max(viewport.minY, frame.maxY); viewport.size.height = max(0, bottom - viewport.minY)
            }
        }
        for bar in app.tabBars.allElementsBoundByIndex + app.keyboards.allElementsBoundByIndex where bar.exists {
            let frame = bar.frame
            if frame.intersects(viewport), frame.midY > viewport.minY { viewport.size.height = max(0, min(viewport.maxY, frame.minY) - viewport.minY) }
        }
        return viewport.insetBy(dx: 8, dy: 8)
    }
    private func drag(_ scroll: XCUIElement, _ app: XCUIApplication, down: Bool) {
        let viewport = visibleContent(scroll, app)
        guard viewport.width > 20, viewport.height > 30 else { return }
        // Drag entirely inside the actual visible content, never across tab/navigation bars.
        let start = CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * (down ? 0.3 : 0.7))
        let end = CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * (down ? 0.7 : 0.3))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
    }
    private func demo(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + arguments; app.launch()
        tap(app.buttons["explore-demo"], in: app); tap(app.buttons["Continue as member"], in: app)
        let username = app.textFields["demo-username"]; tap(username, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); username.typeText("meera\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
        tap(app.buttons["demo-sign-in"], in: app); tap(app.buttons["demo-space-0"], in: app)
        XCTAssertTrue(app.staticTexts["Welcome back, Meera Nair."].waitForExistence(timeout: 10)); return app
    }
    private func tab(_ app: XCUIApplication, _ name: String) {
        if app.tabBars.buttons[name].exists { app.tabBars.buttons[name].tap(); return }
        let item = app.descendants(matching: .any)["nav-\(name)"].firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: item)
        if XCTWaiter.wait(for: [ready], timeout: 3) != .completed {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        tap(item, in: app)
    }
    private func capture(_ name: String) { let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
    func testReviewedRequestSubmissionAndExplicitLoanRenewal() {
        let app = demo(); tap(app.buttons["Browse inventory"], in: app)
        tap(app.descendants(matching: .any)["product-1"].firstMatch, in: app)
        tap(app.buttons["Add to request"], in: app); tap(app.buttons["review-request"], in: app)
        XCTAssertTrue(app.staticTexts["Review your request"].waitForExistence(timeout: 5)); capture("Reviewed hardware request")
        tap(app.buttons["submit-request"], in: app)
        XCTAssertTrue(app.staticTexts["Request received"].waitForExistence(timeout: 5)); capture("Server-status request receipt")
        tap(app.buttons["Done"], in: app); tab(app, "Activity")
        tap(app.buttons["Renew loan"], in: app); tap(app.buttons["Confirm renewal"], in: app)
        XCTAssertTrue(app.staticTexts["Loan renewed"].waitForExistence(timeout: 5)); capture("Confirmed loan renewal")
    }
    func testAvailabilityBookingPendingReceiptAndServerConfirmedCancellation() {
        let app = demo(["--demo-action-pending"]); tab(app, "Activity")
        tap(app.buttons["Find a space"], in: app)
        tap(app.descendants(matching: .any)["space-00000000-0000-0000-0000-000000000031"].firstMatch, in: app)
        tap(app.buttons["Check availability"], in: app)
        tap(app.buttons["Submit booking request"], in: app)
        XCTAssertTrue(app.staticTexts["Booking request received"].waitForExistence(timeout: 5)); capture("Space booking awaiting approval")
        tap(app.buttons["View bookings"], in: app)
        tap(app.buttons["Workshop bench"], in: app)
        tap(app.buttons["Cancel booking"], in: app)
        let confirm = app.buttons.matching(identifier: "Cancel booking").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirm); confirm?.tap()
        XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 5)); capture("Confirmed booking cancellation")
    }
    func testEventRegistrationRefetchesActualTicketThenClearsQRCodeOnCancel() {
        let app = demo(); tap(app.buttons["Make your first circuit"], in: app)
        tap(app.buttons["Confirm registration"], in: app)
        XCTAssertTrue(app.staticTexts["Registration confirmed"].waitForExistence(timeout: 5))
        tap(app.buttons["View registrations"], in: app)
        tap(app.descendants(matching: .any)["registration-777"].firstMatch, in: app)
        XCTAssertTrue(app.images["Simulated event ticket QR code"].waitForExistence(timeout: 5)); capture("Confirmed event ticket demo")
        tap(app.buttons["Cancel registration"], in: app)
        let confirm = app.buttons.matching(identifier: "Cancel registration").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirm); confirm?.tap()
        XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 5)); XCTAssertFalse(app.images["Simulated event ticket QR code"].exists)
    }
    func testProfileDraftSurvivesRotationAndOptionalPreferencesCanChange() {
        let app = demo(); tab(app, "Profile"); tap(app.buttons["Edit profile"], in: app)
        let name = app.textFields["profile-display-name"]; tap(name, in: app)
        let old = name.value as? String ?? ""; name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Meera Maker\n")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height); XCTAssertEqual(name.value as? String, "Meera Maker")
        tap(app.buttons["Save changes"], in: app); XCTAssertTrue(app.staticTexts["Profile saved."].waitForExistence(timeout: 5)); capture("Native profile saved landscape")
        let back = app.navigationBars.buttons["Profile"]; XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        tap(app.buttons["Communication preferences"], in: app)
        let email = app.switches["preference-hardware_requests-email"]; tap(email, in: app)
        // The displayed value changes only after the repository confirms the update.
        let confirmedOff = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: email)
        XCTAssertEqual(XCTWaiter.wait(for: [confirmedOff], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Always-on safety messages'")).firstMatch.exists)
        capture("Optional preference and required safety messages")
    }
    func testWaitlistedRegistrationNeverOffersConfirmedQRCode() {
        let app = demo(["--demo-action-waitlisted"]); tap(app.buttons["Make your first circuit"], in: app)
        tap(app.buttons["Confirm registration"], in: app); XCTAssertTrue(app.staticTexts["You're on the waitlist"].waitForExistence(timeout: 5))
        tap(app.buttons["View registrations"], in: app); tap(app.descendants(matching: .any)["registration-777"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["Waitlist position: 3"].waitForExistence(timeout: 5)); XCTAssertFalse(app.images["Simulated event ticket QR code"].exists)
        capture("Waitlisted event without a ticket")
    }
    func testLargestTextDarkRequestReviewPortraitAndLandscape() {
        let app = demo(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap(app.buttons["appearance"], in: app)
        tap(app.buttons["Browse inventory"], in: app)
        tap(app.descendants(matching: .any)["product-1"].firstMatch, in: app)
        tap(app.buttons["Add to request"], in: app); tap(app.buttons["review-request"], in: app)
        tap(app.buttons["submit-request"], in: app)
        XCTAssertTrue(app.staticTexts["Request received"].waitForExistence(timeout: 5)); capture("Request receipt largest text dark portrait")
        XCUIDevice.shared.orientation = .landscapeLeft; XCTAssertGreaterThan(app.frame.width, app.frame.height)
        tap(app.buttons["Done"], in: app); capture("Member item largest text dark landscape")
    }

}
