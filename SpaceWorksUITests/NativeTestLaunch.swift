import XCTest
import UIKit

/// UI-test runner policy. It never enters the application or its Release target.
extension XCUIApplication {
    func rotateToLandscapeAndWait(timeout: TimeInterval = 10) {
        XCUIDevice.shared.orientation = .landscapeLeft
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.frame.width > self.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: timeout), .completed,
                       "Requested landscape orientation must actually be visible.")
    }

    func launchForDeviceProfile() {
        let profiles: Set<String> = ["compact", "phone", "large", "tablet", "tablet-landscape", "large-tablet"]
        let profile = ProcessInfo.processInfo.environment["SPACEWORKS_TEST_PROFILE"] ?? "phone"
        XCTAssertTrue(profiles.contains(profile), "The test scheme must receive a supported matrix profile.")
        XCTAssertTrue(launchArguments.contains("--ui-testing"), "Profile launches require isolated Debug fixtures.")
        let dark = !launchArguments.contains("--ui-start-light") && ["large", "tablet-landscape"].contains(profile)
        let landscape = !launchArguments.contains("--ui-start-portrait") && profile == "tablet-landscape"
        let reduceMotion = profile == "large-tablet"
        launchEnvironment["SPACEWORKS_TEST_APPEARANCE"] = dark ? "dark" : "light"
        launchEnvironment["SPACEWORKS_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        launch()
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            landscape ? self.frame.width > self.frame.height : self.frame.height > self.frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [orientation], timeout: 10), .completed, "Requested launch orientation must actually be visible.")
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
