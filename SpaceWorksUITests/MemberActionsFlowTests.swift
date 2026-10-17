import XCTest

final class MemberActionsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func activate(_ element: XCUIElement) {
        if element.identifier == "submit-request" { capture("Request review before submission") }
        element.tap()
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        var reviewDown = false
        var previousReviewFrame: CGRect?
        var capturedReviewStall = false
        for attempt in 0..<24 {
            let scroll = containingScroll(element, app)
            if element.exists {
                let insideScroll = contains(element, scroll)
                if element.isHittable && !insideScroll { activate(element); return }
                let frame = element.frame
                let viewport = visibleContent(scroll, app)
                let visible = frame.intersection(viewport)
                if scroll.identifier == "request-review-scroll" {
                    if !capturedReviewStall, previousReviewFrame == frame {
                        capture("Review scroll stalled before " + element.identifier)
                        capturedReviewStall = true
                    }
                    previousReviewFrame = frame
                }
                print("Native action \(element.identifier.isEmpty ? element.label : element.identifier), attempt \(attempt), frame \(frame), viewport \(viewport), hittable \(element.isHittable)")
                // A SwiftUI Toggle can expose a label rectangle that differs from its
                // native UISwitch activation point. Let XCTest activate a visible switch.
                if element.elementType == .switch, element.isHittable,
                   !visible.isNull, visible.width > 4, visible.height > 4 { activate(element); return }
                // A fitting review button must reveal its entire label before activation.
                // Its midpoint can be hittable while the second line is below the screen.
                let fullReviewButton = scroll.identifier == "request-review-scroll" && element.elementType == .button
                    && frame.height > 0 && frame.height <= viewport.height - 4
                let positioned = fullReviewButton ? viewport.insetBy(dx: 2, dy: 2).contains(frame)
                    : viewport.insetBy(dx: 2, dy: 2).contains(CGPoint(x: frame.midX, y: frame.midY))
                if element.isHittable, !visible.isNull, visible.width > 4, visible.height > 4, positioned {
                    // Use the native activation point. A wide Toggle's label centre is not
                    // its switch thumb; coordinates are only needed for clipped text fields.
                    activate(element); return
                }
                if (element.elementType == .textField || element.elementType == .secureTextField),
                   element.isHittable, !visible.isNull, visible.width > 8, visible.height > 8 {
                    element.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX - frame.minX, dy: visible.midY - frame.minY)).tap(); return
                }
                // Off-screen accessibility frames can jump across the viewport after
                // rotation. Reversing on their midpoint oscillated around hidden controls.
                // Sweep consistently in each direction; activation still requires a real
                // visible, hittable target. New screens normally start near their top.
                if scroll.identifier == "request-review-scroll" {
                    // Native geometry proves this target remains in the same modal.
                    // Some drags can make no progress; do not reverse a resumed
                    // search merely because half the gesture budget elapsed.
                    if frame.minY.isFinite, frame.maxY.isFinite, frame.height > 0 {
                        if frame.maxY <= viewport.minY { reviewDown = true }
                        else if frame.minY >= viewport.maxY { reviewDown = false }
                        else if frame.minY < viewport.minY { reviewDown = true }
                        else if frame.maxY > viewport.maxY { reviewDown = false }
                    }
                    drag(scroll, app, target: element, down: reviewDown)
                } else { drag(scroll, app, target: element, down: attempt >= 12) }
            } else {
                drag(scroll, app, target: element, down: scroll.identifier == "request-review-scroll" ? reviewDown : attempt >= 12)
            }
        }
        let target = element.exists ? (element.identifier.isEmpty ? element.label : element.identifier) : "missing control"
        capture("Unreachable action " + target)
        XCTFail("Action must be reachable: \(target)")
    }
    private func contains(_ element: XCUIElement, _ scroll: XCUIElement) -> Bool {
        guard element.exists, scroll.exists else { return false }
        let descendants = scroll.descendants(matching: element.elementType)
        if !element.identifier.isEmpty { return descendants.matching(identifier: element.identifier).firstMatch.exists }
        guard !element.label.isEmpty else { return false }
        return descendants.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
    }
    private func containingScroll(_ element: XCUIElement, _ app: XCUIApplication) -> XCUIElement {
        let scrolls = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        // Presented SwiftUI sheets may appear in a backing view's AX descendants.
        // Its scroll cannot move the modal content. Prefer the actual review container.
        if let review = scrolls.first(where: { $0.identifier == "request-review-scroll" }) { return review }
        let containing = scrolls.filter { contains(element, $0) }
        return containing.min(by: { area($0.frame.intersection(app.frame)) < area($1.frame.intersection(app.frame)) })
            ?? scrolls.first ?? app.scrollViews.firstMatch
    }
    private func area(_ rect: CGRect) -> CGFloat { rect.isNull ? .greatestFiniteMagnitude : rect.width * rect.height }
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
        // A tab bar hidden behind a modal is not part of the modal viewport.
        let lowerBars = app.tabBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            + app.keyboards.allElementsBoundByIndex.filter { $0.exists }
        for bar in lowerBars {
            let frame = bar.frame
            if frame.intersects(viewport), frame.midY > viewport.minY { viewport.size.height = max(0, min(viewport.maxY, frame.minY) - viewport.minY) }
        }
        return viewport.insetBy(dx: 8, dy: 8)
    }
    private func drag(_ scroll: XCUIElement, _ app: XCUIApplication, target: XCUIElement, down: Bool) {
        let viewport = visibleContent(scroll, app)
        guard viewport.width > 20, viewport.height > 30 else { return }
        // Drag entirely inside the actual visible content, never across tab/navigation bars.
        // A fast released drag flung landscape content ~300pt across a 139pt
        // viewport. Hold at a slow, bounded endpoint so the next visible target is
        // examined before momentum can carry it under the navigation/tab bars.
        var distance = min(200, viewport.height * 0.4)
        if scroll.identifier == "request-review-scroll", target.exists {
            let frame = target.frame
            if frame.minY.isFinite, frame.maxY.isFinite, frame.height > 0, frame.height <= viewport.height - 4 {
                let inset = viewport.insetBy(dx: 2, dy: 2)
                let remaining = down ? inset.minY - frame.minY : frame.maxY - inset.maxY
                if remaining > 0 {
                    // Native traces move 190pt for a 200pt drag (10pt pan slop).
                    // Approach the exposed edge precisely in short landscape content.
                    distance = min(distance, max(12, remaining + 10))
                }
            }
        }
        // The modal's multiline purpose field owns an inner scroll; its gutter
        // moves the parent. A generic tablet viewport may include the sidebar, so
        // keep other gestures within the target's horizontal content column.
        var x = viewport.midX
        if scroll.identifier == "request-review-scroll", target.exists {
            // Stay inside the card's padding. The outer screen gutter can be
            // captured by the sheet's pan recognizer instead of its scroll view.
            // The purpose editor begins at the target's leading content edge.
            let leading = target.frame.minX
            if leading.isFinite {
                x = min(viewport.maxX - 12, max(viewport.minX + 12, leading - 12))
            }
        } else if target.exists {
            let frame = target.frame
            if frame.minX.isFinite, frame.maxX.isFinite, frame.width > 0 {
                let lower = max(viewport.minX, frame.minX), upper = min(viewport.maxX, frame.maxX)
                if upper - lower > 24 { x = (lower + upper) / 2 }
            }
        }
        let start = CGPoint(x: x, y: viewport.midY + (down ? -distance : distance) / 2)
        let end = CGPoint(x: x, y: viewport.midY + (down ? distance : -distance) / 2)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
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
