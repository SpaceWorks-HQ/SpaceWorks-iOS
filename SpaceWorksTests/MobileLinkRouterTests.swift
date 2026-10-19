import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class MobileLinkRouterTests: XCTestCase {
    func testTapWaitsForAuthenticationThenFreshIdentityBeforeSelectingAndApproving() async {
        let router = MobileLinkRouter(); let link = MobileLink(makerspaceID: 7, destination: .product(1))
        router.receive(link); await router.process(); XCTAssertNil(router.approved); XCTAssertEqual(router.pending, link)
        var steps: [String] = []
        router.bind(account: "server/account1", refresh: { steps.append("me"); return [7] }, select: { id in steps.append("select-\(id)") })
        await router.process()
        XCTAssertEqual(steps, ["me", "select-7"]); XCTAssertEqual(router.approved?.link, link); XCTAssertNil(router.pending)
    }
    func testUnauthorizedMakerspaceNeverChangesScopeOrApproves() async {
        let router = MobileLinkRouter(); var selected = false
        router.bind(account: "server/account1", refresh: { [7] }, select: { _ in selected = true })
        router.receive(.init(makerspaceID: 99, destination: .inbox)); await router.process()
        XCTAssertFalse(selected); XCTAssertNil(router.approved); XCTAssertEqual(router.error, "This makerspace isn't available to your account.")
    }
    func testFailedSelectionAndRefreshCannotPublishNavigation() async {
        let router = MobileLinkRouter()
        router.bind(account: "server/account1", refresh: { [7] }, select: { _ in throw APIError(status: 403, code: "denied", detail: "Membership is inactive.") })
        router.receive(.init(makerspaceID: 7, destination: .inbox)); await router.process()
        XCTAssertNil(router.approved); XCTAssertEqual(router.error, "Membership is inactive.")
        router.bind(account: "server/account1", refresh: { throw URLError(.notConnectedToInternet) }, select: { _ in XCTFail("Offline identity changed scope") })
        await router.process(); XCTAssertNil(router.approved); XCTAssertEqual(router.error, "Couldn't connect. Try again.")
    }
    func testLogoutDuringFreshIdentityCannotApproveOldTapOrKeepCallbacks() async {
        let gate = RoutingGate(); let router = MobileLinkRouter()
        router.bind(account: "server/account1", refresh: { await gate.wait(); return [7] }, select: { _ in XCTFail("Logged-out hint selected scope") })
        router.receive(.init(makerspaceID: 7, destination: .inbox))
        let pending = Task { await router.process() }; await gate.requested(); router.unbind(); await gate.resolve(); await pending.value
        XCTAssertNil(router.approved); XCTAssertNil(router.pending)
    }
    func testNewAccountTapProcessesWhenOldAccountLookupFinishes() async {
        let gate = RoutingGate(); let router = MobileLinkRouter()
        router.bind(account: "old", refresh: { await gate.wait(); return [7] }, select: { _ in XCTFail("Old account selected scope") })
        router.receive(.init(makerspaceID: 7, destination: .home))
        let old = Task { await router.process() }; await gate.requested(); router.unbind()
        router.bind(account: "new", refresh: { [8] }, select: { XCTAssertEqual($0, 8) })
        router.receive(.init(makerspaceID: 8, destination: .inbox)); await router.process()
        await gate.resolve(); await old.value
        XCTAssertEqual(router.approved?.account, "new"); XCTAssertEqual(router.approved?.link.makerspaceID, 8)
    }
    func testRetryAfterSurvivesAnotherHintAndExpiryAllowsFreshIdentity() async {
        let router = MobileLinkRouter(); let now = Date(); let deadline = now.addingTimeInterval(60); var calls = 0
        router.bind(account: "server/account1", refresh: { calls += 1; if calls == 1 { throw APIError(status: 429, code: "throttled", detail: "Try later.", retryAfter: deadline) }; return [7] }, select: { _ in })
        router.receive(.init(makerspaceID: 7, destination: .inbox)); await router.process(now: now)
        router.receive(.init(makerspaceID: 7, destination: .home)); await router.process(now: now)
        XCTAssertEqual(calls, 1); XCTAssertNil(router.approved)
        await router.process(now: deadline.addingTimeInterval(1)); XCTAssertEqual(calls, 2); XCTAssertEqual(router.approved?.link.destination, .home)
    }
    func testLegacySlugResolvesFromFreshIdentityBeforeSelectedScopeAndNeverGrantsItsOwnAuthority() async throws {
        let router = MobileLinkRouter(); var calls: [String] = []
        router.receive(MobileLink.Legacy(slug: "fresh-lab", staffInbox: false))
        await router.process(); XCTAssertNil(router.approved)
        router.bind(account: "account", refresh: { calls.append("me"); return [8] }, select: { calls.append("select-\($0)") }, resolveLegacy: { value in
            calls.append("resolve-fresh-" + value.slug)
            return MobileLink(makerspaceID: 8, destination: .home)
        })
        await router.process()
        XCTAssertEqual(calls, ["resolve-fresh-fresh-lab", "me", "select-8"])
        XCTAssertEqual(router.approved?.link, MobileLink(makerspaceID: 8, destination: .home))
        router.receive(MobileLink.Legacy(slug: "unknown-lab", staffInbox: false))
        router.bind(account: "account", refresh: { [7] }, select: { _ in XCTFail("Unverified legacy mapping selected scope") }, resolveLegacy: { _ in MobileLink(makerspaceID: 8, destination: .home) })
        await router.process(); XCTAssertNil(router.approved); XCTAssertNotNil(router.error)
    }
    func testNotificationLegacySlugCannotOverrideItsExplicitMakerspaceHint() async throws {
        let router = MobileLinkRouter()
        router.bind(account: "account", refresh: { [7, 8] }, select: { XCTAssertEqual($0, 7) }, resolveLegacy: { _ in .init(makerspaceID: 8, destination: .home) })
        router.receive(try XCTUnwrap(NotificationHint(payload: ["v": 2, "makerspace_id": 7, "link": "/m/other-lab/member"])))
        await router.process()
        XCTAssertEqual(router.approved?.link, MobileLink(makerspaceID: 7, destination: .inbox))
    }
    func testOldViewTeardownCannotUnbindNewAccountRoutingOwner() async {
        let router = MobileLinkRouter(); let oldOwner = UUID(); let newOwner = UUID()
        router.bind(account: "old", refresh: { [7] }, select: { _ in }, owner: oldOwner)
        router.bind(account: "new", refresh: { [8] }, select: { XCTAssertEqual($0, 8) }, owner: newOwner)
        router.receive(.init(makerspaceID: 8, destination: .inbox))
        router.unbind(owner: oldOwner); await router.process()
        XCTAssertEqual(router.approved?.account, "new"); XCTAssertEqual(router.approved?.link.makerspaceID, 8)
    }
    func testNewTapWinsOverAnEarlierIdentityLookupAndFinishedTicketCannotNavigateAgain() async throws {
        let gate = RoutingGate(); let router = MobileLinkRouter(); var calls = 0
        router.bind(account: "server/account1", refresh: { calls += 1; if calls == 1 { await gate.wait() }; return [7] }, select: { _ in })
        router.receive(.init(makerspaceID: 7, destination: .product(1)))
        let first = Task { await router.process() }; await gate.requested()
        router.receive(.init(makerspaceID: 7, destination: .inbox)); await gate.resolve(); await first.value
        let approved = try XCTUnwrap(router.approved); XCTAssertEqual(approved.link.destination, .inbox); XCTAssertEqual(calls, 2)
        XCTAssertTrue(router.isCurrent(approved)); router.finish(approved); XCTAssertFalse(router.isCurrent(approved))
    }
}
@MainActor private final class RoutingGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0; observer?.resume(); observer = nil } }
    func requested() async { if continuation != nil { return }; await withCheckedContinuation { observer = $0 } }
    func resolve() { continuation?.resume(); continuation = nil }
}
