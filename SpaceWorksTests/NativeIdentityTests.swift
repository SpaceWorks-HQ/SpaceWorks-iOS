import XCTest
import UIKit
@testable import SpaceWorks

@MainActor final class NativeIdentityTests: XCTestCase {
    func testGoogleWithoutRegisteredBuildConfigurationFailsBeforeSDKLaunch() async {
        do {
            _ = try await NativeIdentity.google(clientID: "", serverClientID: nil, nonce: "sample", presenting: UIViewController())
            XCTFail("Unconfigured provider must fail before presentation")
        } catch { XCTAssertEqual(error.localizedDescription, NativeIdentity.unavailable.localizedDescription) }
    }
    func testOrganizationBrowserRejectsInsecureURLBeforePresentation() async {
        let browser = NativeOIDCBrowser()
        do {
            _ = try await browser.authorize(url: URL(string: "http://identity.example/authorize")!, expectedState: "sample", anchor: UIWindow(frame: .zero))
            XCTFail("Insecure identity provider must fail before presentation")
        } catch { XCTAssertEqual(error.localizedDescription, NativeIdentity.unavailable.localizedDescription) }
    }
}
