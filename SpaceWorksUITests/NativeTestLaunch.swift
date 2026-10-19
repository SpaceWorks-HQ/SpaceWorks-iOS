import XCTest
import UIKit

/// UI-test runner policy. It never enters the application or its Release target.
extension XCUIApplication {
    func rotateToLandscapeAndWait(timeout: TimeInterval = 10) {
        let diagnostic = launchArguments.contains("--ui-orientation-diagnostics")
        var lastFrame = frame
        if diagnostic {
            print("SpaceWorksOrientationTest before device=\(XCUIDevice.shared.orientation.rawValue) frame=\(lastFrame)")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            lastFrame = self.frame
            return lastFrame.width > lastFrame.height
        }, object: nil)
        let result = XCTWaiter.wait(for: [orientation], timeout: timeout)
        if diagnostic {
            print("SpaceWorksOrientationTest after device=\(XCUIDevice.shared.orientation.rawValue) lastPredicateFrame=\(lastFrame) waitResult=\(result.rawValue)")
        }
        if result != .completed { attachFailedOrientationEvidence() }
        XCTAssertEqual(result, .completed,
                       "Requested landscape orientation must actually be visible.")
    }

    private func attachFailedOrientationEvidence() {
        XCTContext.runActivity(named: "Failed native orientation evidence") { activity in
            let pixels = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            pixels.name = "Failed orientation full OS screen"; pixels.lifetime = .keepAlways
            activity.add(pixels)
            let hierarchy = XCTAttachment(string: debugDescription)
            hierarchy.name = "Failed orientation app hierarchy"; hierarchy.lifetime = .keepAlways
            activity.add(hierarchy)
        }
    }

    func launchForDeviceProfile() {
        let profiles: Set<String> = ["compact", "phone", "large", "tablet", "tablet-landscape", "large-tablet"]
        let profile = ProcessInfo.processInfo.environment["SPACEWORKS_TEST_PROFILE"] ?? "phone"
        XCTAssertTrue(profiles.contains(profile), "The test scheme must receive a supported matrix profile.")
        XCTAssertTrue(launchArguments.contains("--ui-testing"), "Profile launches require isolated Debug fixtures.")
        if !launchArguments.contains("--ui-orientation-diagnostics") {
            launchArguments.append("--ui-orientation-diagnostics")
        }
        let dark = !launchArguments.contains("--ui-start-light") && ["large", "tablet-landscape"].contains(profile)
        let landscape = !launchArguments.contains("--ui-start-portrait") && profile == "tablet-landscape"
        let reduceMotion = profile == "large-tablet"
        launchEnvironment["SPACEWORKS_TEST_APPEARANCE"] = dark ? "dark" : "light"
        launchEnvironment["SPACEWORKS_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
        launch()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            landscape ? self.frame.width > self.frame.height : self.frame.height > self.frame.width
        }, object: nil)
        let orientationResult = XCTWaiter.wait(for: [orientation], timeout: 10)
        if orientationResult != .completed { attachFailedOrientationEvidence() }
        XCTAssertEqual(orientationResult, .completed, "Requested launch orientation must actually be visible.")
        let appearance = buttons["appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        XCTAssertEqual(appearance.label, dark ? "Light mode" : "Dark mode", "The app's explicit theme must match its matrix profile.")
        let record: [String: Any] = [
            "profile": profile, "app_appearance": dark ? "dark" : "light",
            "orientation": landscape ? "landscape" : "portrait",
            "window_width_points": frame.width, "window_height_points": frame.height,
            "reduce_motion_environment": reduceMotion,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let value = String(data: data, encoding: .utf8) {
            XCTContext.runActivity(named: "Verified initial app profile") { activity in
                let attachment = XCTAttachment(string: value)
                attachment.name = "Initial app profile"; attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
    }
}
