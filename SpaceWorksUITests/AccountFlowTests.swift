import XCTest

final class AccountFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, in app: XCUIApplication) { NativeUIActions.tap(element, in: app) }
    private func account(extra: [String] = [], withoutMakerspace: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + extra
        if ProcessInfo.processInfo.environment["SPACEWORKS_SETUP_DIAGNOSTIC"] == "true" {
            app.launchArguments.append("--ui-demo-entry-diagnostics")
        }
        app.launchForDeviceProfile()
        let explore = app.buttons["explore-demo"]
        recordDemoEntry("before native Explore", element: explore, in: app)
        tap(explore, in: app)
        recordDemoEntry("after native Explore", element: explore, in: app)
        tap(app.buttons["Continue as member"], in: app)
        let username = app.textFields["demo-username"]; tap(username, in: app); username.typeText("member\n")
        app.secureTextFields["demo-password"].typeText("sample\n"); tap(app.buttons["demo-sign-in"], in: app)
        if !withoutMakerspace {
        tap(app.buttons["demo-space-0"], in: app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        if app.tabBars.buttons["Profile"].exists { tap(app.tabBars.buttons["Profile"], in: app) }
        else {
            let profile = app.buttons["nav-Profile"]
            let readiness = NativeUIActions.readiness(in: app)
            let ready = XCTNSPredicateExpectation(predicate: readiness, object: profile)
            if XCTWaiter.wait(for: [ready], timeout: 3) != .completed {
                let sidebar = app.navigationBars.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Show Sidebar", "Toggle Sidebar")).firstMatch
                let sidebarReady = XCTNSPredicateExpectation(predicate: readiness, object: sidebar)
                XCTAssertEqual(XCTWaiter.wait(for: [sidebarReady], timeout: 3), .completed)
                sidebar.tap()
                let opened = XCTNSPredicateExpectation(predicate: readiness, object: profile)
                let openedResult = XCTWaiter.wait(for: [opened], timeout: 10)
                if openedResult != .completed {
                    let exists = profile.exists
                    print("Profile after native sidebar: exists=\(exists), enabled=\(exists && profile.isEnabled), ready=\(readiness.evaluate(with: profile)), frame=\(exists ? String(describing: profile.frame) : "unavailable")")
                }
                XCTAssertEqual(openedResult, .completed)
            }
            tap(profile, in: app)
        }
        }
        let entry = app.buttons["account-entry"]
        tap(entry, in: app)
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Account and security"].waitForExistence(timeout: 5))
        return app
    }
    private func recordDemoEntry(_ phase: String, element: XCUIElement, in app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["SPACEWORKS_SETUP_DIAGNOSTIC"] == "true" else { return }
        let exists = element.exists
        print("SpaceWorksDemoEntryTest \(phase) appFrame=\(app.frame) exploreExists=\(exists) exploreFrame=\(exists ? String(describing: element.frame) : "unavailable")")
        XCTContext.runActivity(named: "Demo entry " + phase) { activity in
            let pixels = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            pixels.name = "Demo entry " + phase; pixels.lifetime = .keepAlways
            activity.add(pixels)
        }
    }
    private func confirmNativeDialog(_ title: String, action label: String, in app: XCUIApplication) {
        if title == "Leave this makerspace?" || title == "Cancel membership renewal?" {
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.staticTexts[title].waitForExistence(timeout: 5))
            let primaryLabel = title == "Leave this makerspace?" ? "Leave" : "Stop renewal"
            for control in [alert.buttons[primaryLabel], alert.buttons["Cancel"]] {
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                XCTAssertTrue(control.isEnabled)
                XCTAssertTrue(control.isHittable)
                let frame = control.frame
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertTrue(alert.frame.insetBy(dx: 2, dy: 2).contains(frame))
                XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(frame))
            }
            attach("Native account confirmation")
            alert.buttons[label].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            return
        }
        // Native confirmation popovers own separate title/action scroll regions.
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        let action = app.buttons[label]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isHittable)
        let frame = action.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(frame))
        attach("Native account confirmation")
        action.tap()
    }
    private func openDataExports(in app: XCUIApplication, captureBeforeTap: Bool = false) {
        let entry = app.buttons["account-exports"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        for attempt in 0..<24 {
            let scrolls = app.scrollViews.allElementsBoundByIndex.filter {
                $0.exists && $0.isHittable && $0.buttons.matching(identifier: "account-exports").firstMatch.exists
            }
            guard let scroll = scrolls.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                XCTFail("The account menu must provide its real scroll container."); return
            }
            var viewport = scroll.frame.intersection(app.frame)
            for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
                let frame = bar.frame
                if frame.intersects(viewport), frame.midY < viewport.midY {
                    let bottom = viewport.maxY; viewport.origin.y = max(viewport.minY, frame.maxY); viewport.size.height = max(0, bottom - viewport.minY)
                }
            }
            let lowerBars = app.tabBars.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
                + app.keyboards.allElementsBoundByIndex.filter { $0.exists }
            for bar in lowerBars {
                let frame = bar.frame
                if frame.intersects(viewport), frame.midY > viewport.minY { viewport.size.height = max(0, min(viewport.maxY, frame.minY) - viewport.minY) }
            }
            viewport = viewport.insetBy(dx: 8, dy: 8)
            let frame = entry.frame, visible = frame.intersection(viewport)
            print("Account exports navigation, attempt \(attempt), frame \(frame), viewport \(viewport), hittable \(entry.isHittable)")
            guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0,
                  viewport.width > 32, viewport.height > 64 else { XCTFail("Account navigation requires valid visible geometry."); return }
            if entry.isHittable, !visible.isNull, visible.width > 4, visible.height > 4,
               viewport.insetBy(dx: 2, dy: 2).contains(CGPoint(x: frame.midX, y: frame.midY)) {
                if captureBeforeTap { attach("Account menu export navigation at largest text") }
                entry.tap(); return
            }
            // This long menu can exceed twelve short pans at full Dynamic Type.
            // Follow the actual row, with the same total bound and real content gestures.
            let down: Bool
            if frame.midY >= viewport.maxY - 2 { down = false }
            else if frame.midY <= viewport.minY + 2 { down = true }
            else { continue }
            let remaining = down ? viewport.minY + 8 - frame.midY : frame.midY - (viewport.maxY - 8)
            let distance = min(viewport.height - 32, max(12, remaining + 12))
            let x = min(viewport.maxX - 16, max(viewport.minX + 16, frame.midX))
            let y = down ? viewport.minY + 16 : viewport.maxY - 16
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - app.frame.minX, dy: y - app.frame.minY))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - app.frame.minX, dy: y + (down ? distance : -distance) - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: 0.3)
        }
        XCTFail("The actual data export row must be visible and hittable after bounded account-menu navigation.")
    }
    private func dismissAccountKeyboard(_ identifier: String, in app: XCUIApplication) {
        // Activate the real focus-bound navigation item, not the inaccessible accessory.
        let done = app.navigationBars.buttons[identifier]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        let frame = done.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(frame))
        attach("Native account keyboard action \(identifier)")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The keyboard must close before continuing the account flow.")
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPhoneVerificationThenCurrentSessionRevocationRequiresSignIn() {
        let app = account(); tap(app.buttons["account-phone"], in: app)
        let phone = app.textFields["account-phone-number"]
        NativeUIActions.tap(phone, in: app, requireWholeFrame: true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons["account-phone-keyboard-done"].waitForExistence(timeout: 5))
        var enteredPhone = ""
        for digit in "9876543210" {
            enteredPhone.append(digit)
            phone.typeText(String(digit))
            let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enteredPhone), object: phone)
            XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 5), .completed, "Each intended native phone digit must be accepted before entering the next.")
        }
        XCTAssertEqual(phone.value as? String, "9876543210")
        dismissAccountKeyboard("account-phone-keyboard-done", in: app); tap(app.buttons["account-phone-send"], in: app)
        let code = app.textFields["account-phone-code"]
        NativeUIActions.tap(code, in: app, requireWholeFrame: true)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons["account-phone-keyboard-done"].waitForExistence(timeout: 5))
        code.typeText("123456")
        XCTAssertEqual(code.value as? String, "123456")
        dismissAccountKeyboard("account-phone-keyboard-done", in: app); tap(app.buttons["account-phone-verify"], in: app)
        XCTAssertTrue(app.staticTexts["+919876543210"].waitForExistence(timeout: 10)); attach("Account verified phone sample")
        tap(app.navigationBars.buttons.element(boundBy: 0), in: app)
        tap(app.buttons["account-sessions"], in: app); tap(app.buttons["account-revoke-current-session"], in: app)
        confirmNativeDialog("Sign out this session?", action: "Sign out", in: app)
        if app.buttons["account-security-continue"].waitForExistence(timeout: 2) { tap(app.buttons["account-security-continue"], in: app) }
        XCTAssertTrue(app.textFields["demo-username"].waitForExistence(timeout: 10))
    }
    func testRecoveryCodesAreAcknowledgedBeforeReturningToSignIn() {
        let app = account(); tap(app.buttons["account-security"], in: app)
        let password = app.secureTextFields["account-current-password"]; tap(password, in: app); password.typeText("DemoPass!123\n")
        tap(app.buttons["account-regenerate-recovery"], in: app)
        confirmNativeDialog("Replace your recovery codes?", action: "Continue", in: app)
        XCTAssertTrue(app.staticTexts["Save your recovery codes"].waitForExistence(timeout: 10))
        let next = app.buttons["account-security-continue"]; XCTAssertFalse(next.isEnabled)
        let saved = app.switches["account-recovery-saved"]
        NativeUIActions.tap(saved, in: app, requireWholeFrame: true)
        XCTAssertEqual(saved.value as? String, "1")
        XCTAssertTrue(next.isEnabled)
        NativeUIActions.tap(next, in: app, requireWholeFrame: true)
        XCTAssertTrue(app.textFields["demo-username"].waitForExistence(timeout: 10))
    }
    func testExportRequestStatusAndNativeArchivePresentation() {
        let app = account(); openDataExports(in: app)
        tap(app.buttons["account-request-export"], in: app)
        XCTAssertTrue(app.buttons["account-check-export"].waitForExistence(timeout: 10))
        tap(app.buttons["account-check-export"], in: app); tap(app.buttons["account-download-export"], in: app)
        XCTAssertTrue(app.navigationBars["Data export"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["account-share-export"].exists); attach("Account native demo archive")
        tap(app.buttons["Done"], in: app); XCTAssertTrue(app.buttons["account-download-export"].waitForExistence(timeout: 5))
    }
    func testLargestTextLandscapeExportCanReachNativeShare() {
        let app = account(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openDataExports(in: app, captureBeforeTap: true); tap(app.buttons["account-request-export"], in: app)
        tap(app.buttons["account-check-export"], in: app); tap(app.buttons["account-download-export"], in: app)
        XCTAssertTrue(app.navigationBars["Data export"].waitForExistence(timeout: 10))
        app.rotateToLandscapeAndWait()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        // NativeUIActions requires a real visible/hittable action after bounded scrolling.
        tap(app.buttons["account-share-export"], in: app)
        let systemSave = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Save to Files")).firstMatch
        XCTAssertTrue(systemSave.waitForExistence(timeout: 45), "The actual native share sheet must expose a system file action.")
        attach("Native archive share largest text landscape")
    }
    func testGlobalPasswordAndDevicesWorkBeforeJoiningAMakerspace() {
        let app = account(extra: ["--demo-no-memberships"], withoutMakerspace: true)
        XCTAssertFalse(app.buttons["account-sessions"].exists); XCTAssertFalse(app.buttons["account-membership"].exists)
        tap(app.buttons["account-password"], in: app)
        for (identifier, value) in [("account-password-current", "DemoPass!123"), ("account-password-new", "NewDemoPass!456"), ("account-password-confirm", "NewDemoPass!456")] {
            let field = app.secureTextFields[identifier]; tap(field, in: app); field.typeText(value + "\n")
        }
        tap(app.buttons["account-password-update"], in: app)
        XCTAssertTrue(app.staticTexts["Password change preview complete. No password was changed."].waitForExistence(timeout: 10))
        attach("Global account password without membership")
        tap(app.navigationBars.buttons.element(boundBy: 0), in: app); tap(app.buttons["account-devices"], in: app)
        XCTAssertTrue(app.buttons["account-revoke-device-83000000-0000-4000-8000-000000000001"].waitForExistence(timeout: 10))
        attach("Global devices without membership")
    }
    func testDeletionPreviewRequiresIdentityAndExactTypedConfirmation() {
        let app = account(); tap(app.buttons["account-delete-preview"], in: app)
        tap(app.buttons["deletion-scenario"], in: app); tap(app.buttons["Ready to delete"], in: app)
        tap(app.buttons["deletion-check"], in: app)
        let password = app.secureTextFields["deletion-password"]; tap(password, in: app); password.typeText("DemoPass!123\n")
        tap(app.buttons["deletion-verify"], in: app)
        XCTAssertFalse(app.buttons["deletion-submit"].isEnabled)
        let confirmation = app.textFields["deletion-confirmation"]; tap(confirmation, in: app); confirmation.typeText("DELETE\n")
        XCTAssertTrue(app.buttons["deletion-submit"].isEnabled); attach("Whole account deletion demo exact confirmation")
        tap(app.buttons["deletion-submit"], in: app)
        XCTAssertTrue(app.buttons["Continue as member"].waitForExistence(timeout: 10))
    }
    func testDeletionBlockerOpensCurrentMakerspacePaymentFlow() {
        let app = account(); tap(app.buttons["account-delete-preview"], in: app); tap(app.buttons["deletion-check"], in: app)
        XCTAssertTrue(app.staticTexts["Resolve these before deleting"].waitForExistence(timeout: 10))
        tap(app.buttons["Open Payments"].firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["Payments"].waitForExistence(timeout: 10)); attach("Deletion payment blocker opens actual sample payments")
    }
    func testLeavingMakerspaceReturnsToRemainingAuthorizedMemberships() {
        let app = account(); tap(app.buttons["account-membership"], in: app)
        let reason = app.textViews["account-membership-reason"].exists ? app.textViews["account-membership-reason"] : app.textFields["account-membership-reason"]
        tap(reason, in: app); reason.typeText("Moving away")
        dismissAccountKeyboard("account-membership-keyboard-done", in: app)
        tap(app.buttons["account-leave-makerspace"], in: app)
        confirmNativeDialog("Leave this makerspace?", action: "Cancel", in: app)
        XCTAssertTrue(app.navigationBars["Your membership"].exists)
        XCTAssertTrue(app.staticTexts["Active"].exists)
        XCTAssertEqual(reason.value as? String, "Moving away")
        let renewal = app.buttons["Cancel membership renewal"]
        tap(renewal, in: app)
        confirmNativeDialog("Cancel membership renewal?", action: "Cancel", in: app)
        XCTAssertTrue(app.staticTexts["Active"].exists)
        XCTAssertEqual(reason.value as? String, "Moving away")
        XCTAssertTrue(renewal.exists)
        tap(renewal, in: app)
        confirmNativeDialog("Cancel membership renewal?", action: "Stop renewal", in: app)
        XCTAssertTrue(app.staticTexts["Membership renewal cancelled."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Your membership"].exists)
        XCTAssertTrue(app.staticTexts["Active"].exists)
        XCTAssertTrue(renewal.waitForNonExistence(timeout: 5))
        let finalReason = app.textViews["account-membership-reason"].exists ? app.textViews["account-membership-reason"] : app.textFields["account-membership-reason"]
        tap(finalReason, in: app); finalReason.typeText("Moving away")
        dismissAccountKeyboard("account-membership-keyboard-done", in: app)
        tap(app.buttons["account-leave-makerspace"], in: app)
        confirmNativeDialog("Leave this makerspace?", action: "Leave", in: app)
        XCTAssertTrue(app.buttons["demo-space-1"].waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["demo-space-0"].exists)
        attach("Confirmed membership leave keeps other makerspace")
    }

}
