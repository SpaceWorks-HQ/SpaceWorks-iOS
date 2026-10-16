import XCTest
import UIKit

@MainActor final class NativeBrandTests: XCTestCase {
    func testLicensedNativeAccentFontIsRegisteredByApplication() {
        XCTAssertNotNil(UIFont(name: "Unbounded-Regular", size: 24))
    }
}
