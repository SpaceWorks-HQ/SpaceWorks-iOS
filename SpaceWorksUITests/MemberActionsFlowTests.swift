import XCTest

final class MemberActionsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func activate(_ element: XCUIElement) {
        if element.identifier == "submit-request" { capture("Request review before submission") }
        if element.label == "Confirm renewal" { capture("Loan renewal before confirmation") }
        element.tap()
    }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        var reviewDown = false
        var previousReviewFrame: CGRect?
        var capturedReviewStall = false
        var capturedNativeAlternate = false
        for attempt in 0..<24 {
            let scroll = containingScroll(element, app)
            if element.exists {
                let insideScroll = contains(element, scroll)
                if element.isHittable && !insideScroll { activate(element); return }
                let frame = element.frame
                let viewport = visibleContent(scroll, app)
                let visible = frame.intersection(viewport)
                let reviewStalled = scroll.identifier == "request-review-scroll" && previousReviewFrame == frame
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
                let isReviewButton = scroll.identifier == "request-review-scroll" && element.elementType == .button
                let reviewViewport = isReviewButton ? visibleContent(scroll, app, gestureInset: 0) : viewport
                let fullReviewButton = isReviewButton && frame.height > 0 && frame.height <= reviewViewport.height - 4
                // Gesture margins keep drags away from chrome; they are not clipping.
                // Check the complete review control against the actual bar-adjusted
                // viewport, with a 2pt safety margin, rather than its 8pt drag inset.
                let positioned = fullReviewButton ? reviewViewport.insetBy(dx: 2, dy: 2).contains(frame)
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
                // Follow observed target geometry while it remains available. A fixed
                // half-budget reversal can move a still-offscreen control away again.
                // Missing or unusable targets retain the bounded two-direction sweep.
                if scroll.identifier == "request-review-scroll" {
                    // An unchanged far-offscreen target demonstrates a no-op coordinate
                    // pan. Exercise a native scroll gesture within this same search budget.
                    // Near the target, retain the bounded drag and whole-button checks.
                    if isReviewButton, reviewStalled, frame.minY.isFinite, frame.height > 0, frame.minY >= reviewViewport.maxY {
                        let captureAlternate = !capturedNativeAlternate
                        capturedNativeAlternate = true
                        if captureAlternate { capture("Native review scroll alternate before") }
                        print("Native review swipeUp alternate, attempt \(attempt), target before \(frame)")
                        scroll.swipeUp(velocity: .slow)
                        if element.exists { print("Native review swipeUp target after \(element.frame)") }
                        if captureAlternate { capture("Native review scroll alternate after") }
                        continue
                    }
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
                } else {
                    var down = attempt >= 12
                    if frame.minY.isFinite, frame.maxY.isFinite, frame.height > 0 {
                        if frame.maxY <= viewport.minY || frame.minY < viewport.minY { down = true }
                        else if frame.minY >= viewport.maxY || frame.maxY > viewport.maxY { down = false }
                    }
                    drag(scroll, app, target: element, down: down)
                }
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
        let scrolls = app.scrollViews.allElementsBoundByIndex.filter { scroll in
            guard scroll.exists else { return false }
            let frame = scroll.frame
            guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0 else { return false }
            let visible = frame.intersection(app.frame)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else { return false }
            return scroll.isHittable
        }
        // Presented SwiftUI sheets may appear in a backing view's AX descendants.
        // Its scroll cannot move the modal content. Prefer the actual review container.
        if let review = scrolls.first(where: { $0.identifier == "request-review-scroll" }) { return review }
        let containing = scrolls.filter { contains(element, $0) }
        return containing.min(by: { area($0.frame.intersection(app.frame)) < area($1.frame.intersection(app.frame)) })
            ?? scrolls.first ?? app.scrollViews.firstMatch
    }
    private func area(_ rect: CGRect) -> CGFloat { rect.isNull ? .greatestFiniteMagnitude : rect.width * rect.height }
    private func visibleContent(_ scroll: XCUIElement, _ app: XCUIApplication, gestureInset: CGFloat = 8) -> CGRect {
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
        return viewport.insetBy(dx: gestureInset, dy: gestureInset)
    }
    /// This landscape proof requires the whole primary label, without activating it.
    private func revealFully(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let scroll = containingScroll(element, app)
            let viewport = visibleContent(scroll, app, gestureInset: 0).insetBy(dx: 2, dy: 2)
            if element.exists {
                let frame = element.frame
                if frame.minX.isFinite, frame.minY.isFinite, frame.maxX.isFinite, frame.maxY.isFinite,
                   frame.width > 0, frame.height > 0, viewport.contains(frame),
                   element.isEnabled, element.isHittable { return }
                drag(scroll, app, target: element, down: frame.minY < viewport.minY, approachTargetEdge: true)
            } else {
                drag(scroll, app, target: element, down: false, approachTargetEdge: true)
            }
        }
        capture("Primary action not fully visible in largest text landscape")
        XCTFail("The complete enabled primary action must fit inside the usable landscape viewport.")
    }
    private func drag(_ scroll: XCUIElement, _ app: XCUIApplication, target: XCUIElement, down: Bool,
                      approachTargetEdge: Bool = false) {
        let viewport = visibleContent(scroll, app)
        guard viewport.width > 20, viewport.height > 30 else { return }
        // Drag entirely inside the actual visible content, never across tab/navigation bars.
        // A fast released drag flung landscape content ~300pt across a 139pt
        // viewport. Hold at a slow, bounded endpoint so the next visible target is
        // examined before momentum can carry it under the navigation/tab bars.
        var distance = min(200, viewport.height * 0.4)
        if (scroll.identifier == "request-review-scroll" || approachTargetEdge), target.exists {
            let frame = target.frame
            if frame.minY.isFinite, frame.maxY.isFinite, frame.height > 0, frame.height <= viewport.height - 4 {
                let inset = viewport.insetBy(dx: 2, dy: 2)
                let remaining = down ? inset.minY - frame.minY : frame.maxY - inset.maxY
                if remaining > 0 {
                    // Native traces move 190pt for a 200pt drag (10pt pan slop).
                    // Approach the exposed edge precisely for review and reveal-only landscape proof.
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
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + arguments; app.launchForDeviceProfile()
        tap(app.buttons["explore-demo"], in: app)
        let member = app.buttons["Continue as member"]
        XCTAssertTrue(member.waitForExistence(timeout: 5)); tap(member, in: app)
        let username = app.textFields["demo-username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5)); tap(username, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); username.typeText("meera\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
        tap(app.buttons["demo-sign-in"], in: app); tap(app.buttons["demo-space-0"], in: app)
        XCTAssertTrue(app.staticTexts["Welcome back, Meera Nair."].waitForExistence(timeout: 10)); return app
    }
    private func tab(_ app: XCUIApplication, _ name: String) {
        if app.tabBars.buttons[name].exists { app.tabBars.buttons[name].tap(); return }
        let item = app.buttons["nav-\(name)"]
        let readiness = NSPredicate(format: "exists == true AND isEnabled == true AND isHittable == true")
        let ready = XCTNSPredicateExpectation(predicate: readiness, object: item)
        if XCTWaiter.wait(for: [ready], timeout: 3) != .completed {
            let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Show Sidebar", "Toggle Sidebar")).firstMatch
            let sidebarReady = XCTNSPredicateExpectation(predicate: readiness, object: sidebar)
            XCTAssertEqual(XCTWaiter.wait(for: [sidebarReady], timeout: 10), .completed)
            sidebar.tap()
            let opened = XCTNSPredicateExpectation(predicate: readiness, object: item)
            XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 10), .completed)
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
        let space = app.descendants(matching: .any)["space-00000000-0000-0000-0000-000000000031"].firstMatch
        tap(space, in: app)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: space)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["Book a space"].waitForExistence(timeout: 5))
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
        let name = app.textFields["profile-display-name"]
        NativeUIActions.tap(name, in: app, requireWholeFrame: true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let done = app.navigationBars.buttons["profile-keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let original = "Meera Nair"
        XCTAssertEqual(name.value as? String, original)
        let frame = name.frame
        XCTAssertTrue(name.isHittable)
        XCTAssertTrue(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite)
        XCTAssertGreaterThan(frame.width, 44); XCTAssertGreaterThan(frame.height, 0)
        // The field has 14-point content padding; activate its trailing editing interior.
        let insertionPoint = CGPoint(x: frame.maxX - 22, y: frame.midY)
        let viewport = visibleContent(containingScroll(name, app), app, gestureInset: 0).insetBy(dx: 2, dy: 2)
        XCTAssertTrue(viewport.contains(insertionPoint))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: insertionPoint.x - app.frame.minX, dy: insertionPoint.y - app.frame.minY)).tap()
        // A native text interaction may select the final word. Clear the bounded
        // original length, then require the complete intended replacement.
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count))
        name.typeText("Meera Maker")
        XCTAssertEqual(name.value as? String, "Meera Maker", "Verify the replacement before testing rotation preservation.")
        XCTAssertTrue(done.isEnabled && done.isHittable)
        XCTAssertGreaterThan(done.frame.width, 0); XCTAssertGreaterThan(done.frame.height, 0)
        XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(done.frame))
        capture("Native profile keyboard action")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Meera Maker")
        app.rotateToLandscapeAndWait()
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
        let app = demo(["--ui-start-light", "--ui-start-portrait", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tap(app.buttons["appearance"], in: app)
        tap(app.buttons["Browse inventory"], in: app)
        tap(app.descendants(matching: .any)["product-1"].firstMatch, in: app)
        tap(app.buttons["Add to request"], in: app); tap(app.buttons["review-request"], in: app)
        tap(app.buttons["submit-request"], in: app)
        XCTAssertTrue(app.staticTexts["Request received"].waitForExistence(timeout: 5)); capture("Request receipt largest text dark portrait")
        app.rotateToLandscapeAndWait(); XCTAssertGreaterThan(app.frame.width, app.frame.height)
        tap(app.buttons["Done"], in: app)
        let add = app.buttons["Add to request"]
        revealFully(add, in: app)
        XCTAssertGreaterThanOrEqual(add.frame.height, 48)
        capture("Member item primary action fully visible largest text dark landscape")
    }

}
