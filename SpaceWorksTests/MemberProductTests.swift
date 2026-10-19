import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class MemberProductTests: XCTestCase {
    func testProductRetryDeadlineSurvivesReusingTheDetailDraftAndExpiryAllowsRetry() async throws {
        let counter = ProductCounter(); let now = Date(); let deadline = now.addingTimeInterval(60)
        let product = try await DemoMemberRepository().product(1)
        let state = MemberProductState(id: 1) {
            let call = await counter.increment()
            if call == 1 { throw APIError(status: 429, code: "throttled", detail: "Try later.", retryAfter: deadline) }
            return product
        }
        await state.load(now: now); await state.load(now: now)
        let before = await counter.calls; XCTAssertEqual(before, 1); XCTAssertNil(state.product)
        XCTAssertEqual(state.retryAfter, deadline)
        await state.load(now: deadline.addingTimeInterval(1))
        let after = await counter.calls; XCTAssertEqual(after, 2); XCTAssertEqual(state.product?.id, 1)
    }
    func testLateProductCannotReturnAfterAccountInvalidationOrStartNewRequest() async throws {
        let gate = ProductGate(); let product = try await DemoMemberRepository().product(1)
        let state = MemberProductState(id: 1) { await gate.wait() }
        let pending = Task { await state.load() }; await gate.requested()
        state.invalidate(); await gate.resolve(product); await pending.value
        await state.load(); XCTAssertNil(state.product)
        let calls = await gate.calls; XCTAssertEqual(calls, 1)
    }
}
private actor ProductCounter { var calls = 0; func increment() -> Int { calls += 1; return calls } }
private actor ProductGate {
    var calls = 0
    private var continuation: CheckedContinuation<Components.Schemas.PublicProduct, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func wait() async -> Components.Schemas.PublicProduct {
        calls += 1
        return await withCheckedContinuation { continuation = $0; observer?.resume(); observer = nil }
    }
    func requested() async { if continuation != nil { return }; await withCheckedContinuation { observer = $0 } }
    func resolve(_ product: Components.Schemas.PublicProduct) { continuation?.resume(returning: product); continuation = nil }
}
