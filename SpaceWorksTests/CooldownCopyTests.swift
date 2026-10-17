import XCTest
@testable import SpaceWorks

final class CooldownCopyTests: XCTestCase {
    func testOrdinaryFractionalDeadlineRoundsUpForAllControls() {
        let now = Date(timeIntervalSince1970: 10_000), deadline = Date(timeIntervalSince1970: 10_060.25)
        XCTAssertEqual(CooldownCopy.retryMessage(until: deadline, now: now), "Try again in 61s.")
        XCTAssertEqual(CooldownCopy.retryButton(until: deadline, now: now), "Try again in 61s")
        XCTAssertEqual(CooldownCopy.resendButton(until: deadline, now: now), "Send another code in 61s")
    }
    func testFiniteUnrepresentableServerDeadlineHasSafeCopy() {
        let now = Date(timeIntervalSince1970: 0), deadline = Date(timeIntervalSince1970: 1e20)
        XCTAssertEqual(CooldownCopy.retryMessage(until: deadline, now: now), "Try again later.")
        XCTAssertEqual(CooldownCopy.retryButton(until: deadline, now: now), "Try again later")
        XCTAssertEqual(CooldownCopy.resendButton(until: deadline, now: now), "Send another code later")
    }
    func testNonfiniteAndIntBoundaryCannotTrapTheDisplay() {
        let now = Date(timeIntervalSince1970: 0)
        for interval in [Double.infinity, Double.nan, Double(Int.max)] {
            let deadline = Date(timeIntervalSince1970: interval)
            XCTAssertEqual(CooldownCopy.retryMessage(until: deadline, now: now), "Try again later.")
        }
        let representable = Date(timeIntervalSince1970: Double(Int.max).nextDown)
        let rendered = CooldownCopy.retryMessage(until: representable, now: now)
        XCTAssertTrue(rendered.hasPrefix("Try again in "))
        XCTAssertTrue(rendered.hasSuffix("s."))
        // Native localized integer interpolation may insert grouping separators.
        let decimalDigits = rendered.compactMap(\.wholeNumberValue).map { String($0) }.joined()
        XCTAssertEqual(decimalDigits, "9223372036854774784")
    }
}
