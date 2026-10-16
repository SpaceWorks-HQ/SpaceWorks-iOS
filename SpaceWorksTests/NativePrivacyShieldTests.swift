import XCTest
import UIKit
@testable import SpaceWorks

@MainActor final class NativePrivacyShieldTests: XCTestCase {
    func testResignSynchronouslyCoversPresentedContentWithoutReplacingKeyWindowAndActivationRemovesIt() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let host = UIWindow(windowScene: scene)
        host.rootViewController = UIViewController()
        host.makeKeyAndVisible()
        defer { host.isHidden = true; previousKey?.makeKey() }
        let secret = UIViewController()
        secret.view.accessibilityLabel = "Private test content"
        host.rootViewController?.present(secret, animated: false)
        let controller = NativePrivacyShieldController()
        controller.attach(to: host)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        let shield = try XCTUnwrap(controller.shield)
        XCTAssertFalse(shield.isHidden)
        XCTAssertTrue(shield.isOpaque)
        XCTAssertGreaterThan(shield.windowLevel.rawValue, host.windowLevel.rawValue)
        XCTAssertEqual(shield.frame, host.frame)
        XCTAssertTrue(host.isKeyWindow)
        XCTAssertFalse(shield.isKeyWindow)
        XCTAssertEqual(shield.rootViewController?.view.accessibilityIdentifier, "private-app-snapshot")
        XCTAssertFalse(shield.rootViewController?.view.accessibilityLabel?.contains("Private") ?? true)
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: scene)
        XCTAssertNil(controller.shield)
        XCTAssertTrue(host.isKeyWindow)
        controller.detach()
        host.rootViewController?.dismiss(animated: false)
    }

    func testDetachedHostCannotCreateOrRetainPrivateSnapshotWindow() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIWindow(windowScene: scene)
        let controller = NativePrivacyShieldController()
        controller.attach(to: host)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNotNil(controller.shield)
        controller.detach()
        XCTAssertNil(controller.shield)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(controller.shield)
    }
}
