import XCTest
import Vision

final class PaymentsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) { NativeUIActions.tap(element, in: app) }
    private func member() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launchForDeviceProfile()
        tap(app.buttons["explore-demo"], in: app); tap(app.buttons["Continue as member"], in: app)
        let username = app.textFields["demo-username"]; tap(username, in: app); username.typeText("member\n")
        app.secureTextFields["demo-password"].typeText("sample\n")
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
        tap(app.buttons["payments-entry"], in: app)
        return app
    }
    private func demoOutcomeViewport(in app: XCUIApplication) -> CGRect {
        var viewport = app.scrollViews["demo-payment-outcome-scroll"].frame.intersection(app.frame)
        let bar = app.navigationBars["Demo checkout"]
        if bar.exists, bar.isHittable, bar.frame.intersects(viewport) {
            let bottom = viewport.maxY
            viewport.origin.y = max(viewport.minY, bar.frame.maxY)
            viewport.size.height = max(0, bottom - viewport.minY)
        }
        return viewport.insetBy(dx: 2, dy: 2)
    }
    private func revealDemoOutcome(_ action: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["demo-payment-outcome-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        attach("Demo checkout preview choices")
        for attempt in 0..<24 {
            let viewport = demoOutcomeViewport(in: app), frame = action.frame
            print("Demo outcome \(action.label), attempt \(attempt), frame \(frame), viewport \(viewport), hittable \(action.isHittable)")
            if action.isHittable, frame.width > 0, frame.height > 0, viewport.contains(frame) { return }
            guard viewport.width > 32, viewport.height > 64 else { break }
            let down = frame.minY < viewport.minY
            let distance = min(200, viewport.height * 0.45)
            let x = viewport.midX, y = down ? viewport.minY + 16 : viewport.maxY - 16
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - app.frame.minX, dy: y - app.frame.minY))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - app.frame.minX, dy: y + (down ? distance : -distance) - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: 0.3)
        }
        attach("Demo outcome action not fully visible")
        XCTFail("The complete native outcome action must be reachable inside its own sheet scroll view.")
    }
    private func chooseDemoOutcome(_ title: String, in app: XCUIApplication) {
        // Reveal only the identified native sheet content; never scroll its backing page.
        XCTAssertTrue(app.staticTexts["Demo checkout · no money moves"].waitForExistence(timeout: 5))
        let action = app.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        revealDemoOutcome(action, in: app)
        XCTAssertTrue(action.isHittable)
        let frame = action.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(frame))
        XCTAssertTrue(demoOutcomeViewport(in: app).contains(frame))
        attach("Native demo checkout outcome")
        action.tap()
    }
    private func waitForRenderedReceipt(in app: XCUIApplication) {
        var lastRecognizedText = ""
        var lastRecognitionError = "None."
        let visibleReceipt = NSPredicate { _, _ in
            guard let image = XCUIScreen.main.screenshot().image.cgImage else { return false }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            // The PDF body is small relative to the full-screen image; keep it in OCR coverage.
            request.minimumTextHeight = 0.005
            do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) }
            catch { lastRecognitionError = String(describing: error); return false }
            lastRecognizedText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            let text = lastRecognizedText.uppercased()
            // Both phrases occur in the actual PDF page, never in the backing document list.
            return text.contains("DEMO RECEIPT") && text.contains("NO MONEY MOVED")
        }
        let ready = XCTNSPredicateExpectation(predicate: visibleReceipt, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: 20)
        if result != .completed {
            attach("Native receipt rendering not ready")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Native receipt accessibility hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            let recognized = XCTAttachment(string: lastRecognizedText)
            recognized.name = "Native receipt visible text"; recognized.lifetime = .keepAlways; add(recognized)
            let recognition = XCTAttachment(string: "minimumTextHeight=0.005; last Vision error: \(lastRecognitionError)")
            recognition.name = "Native receipt recognition diagnostics"; recognition.lifetime = .keepAlways; add(recognition)
        }
        XCTAssertEqual(result, .completed, "The actual native PDF page must render its sample receipt before capture.")
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDelayedPaymentRemainsPendingUntilDemoServerConfirmationThenOpensReceipt() {
        let app = member(); tap(app.buttons["payment-501"], in: app)
        tap(app.buttons["payment-continue"], in: app); chooseDemoOutcome("Preview waiting for confirmation", in: app)
        let awaiting = app.descendants(matching: .any)["payment-awaiting"].firstMatch
        XCTAssertTrue(awaiting.waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["payment-continue"].exists)
        attach("Payment awaiting authoritative confirmation")
        tap(app.buttons["payment-demo-delayed-confirmation"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["payment-confirmed"].firstMatch.waitForExistence(timeout: 10))
        tap(app.buttons["Receipts and credit notes"], in: app); tap(app.buttons["document-901"], in: app)
        XCTAssertTrue(app.navigationBars["Payment document"].waitForExistence(timeout: 10))
        waitForRenderedReceipt(in: app)
        attach("Payment native PDF receipt")
        tap(app.buttons["Done"], in: app)
        XCTAssertTrue(app.buttons["document-901"].waitForExistence(timeout: 5))
    }
    func testCancelledDemoCheckoutKeepsChargePendingAndAllowsExplicitRetry() {
        let app = member(); tap(app.buttons["payment-501"], in: app)
        tap(app.buttons["payment-continue"], in: app); chooseDemoOutcome("Preview canceled checkout", in: app)
        XCTAssertTrue(app.buttons["payment-continue"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["payment-confirmed"].firstMatch.exists)
        attach("Payment cancelled with pending charge")
    }
}
