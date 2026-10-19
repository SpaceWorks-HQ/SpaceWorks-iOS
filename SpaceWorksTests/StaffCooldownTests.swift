import Foundation
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

#if DEBUG
@MainActor final class StaffCooldownTests: XCTestCase {
    func testHugeFiniteRetryDeadlineYieldsAndInvalidationCannotReopenGate() async throws {
        let state = StaffState(repository: DemoStaffRepository(), makerspaceID: 7, actions: [], features: [])
        await state.loadQueue()
        XCTAssertFalse(state.requests.isEmpty)
        var childPrivateValue = "sample pending scan"
        state.registerChild { childPrivateValue = "" }

        let deadline = Date(timeIntervalSinceNow: 1e20)
        XCTAssertTrue(deadline.timeIntervalSince1970.isFinite)
        state.refuse(APIError(status: 429, code: "rate_limited", detail: "Try again later.", retryAfter: deadline))
        // Let the actual main-actor cooldown task begin its first cancellable chunk.
        // The former direct UInt64 conversion traps here before it can suspend.
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(state.retryAfter, deadline)
        XCTAssertFalse(state.canRequest)
        XCTAssertTrue(state.isActive)

        let laterDeadline = Date(timeIntervalSinceNow: 2e20)
        state.refuse(APIError(status: 429, code: "rate_limited", detail: "Try again later.", retryAfter: laterDeadline))
        state.refuse(APIError(status: 429, code: "rate_limited", detail: "Try again later.", retryAfter: Date(timeIntervalSinceNow: 60)))
        for _ in 0..<8 { await Task.yield() }
        XCTAssertEqual(state.retryAfter, laterDeadline, "Cancelled or shorter cooldowns cannot shorten the authoritative deadline.")
        XCTAssertFalse(state.canRequest)

        state.invalidate()
        for _ in 0..<8 { await Task.yield() }
        await state.loadQueue()
        XCTAssertEqual(childPrivateValue, "")
        XCTAssertTrue(state.requests.isEmpty)
        XCTAssertTrue(state.directLoans.isEmpty)
        XCTAssertTrue(state.events.isEmpty)
        XCTAssertTrue(state.spaces.isEmpty)
        XCTAssertTrue(state.bookings.isEmpty)
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.canRequest)
        XCTAssertEqual(state.retryAfter, laterDeadline, "An invalidated timer cannot reopen this request gate.")
    }
}
#endif
