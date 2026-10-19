#if DEBUG
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class MobileLinkDestinationTests: XCTestCase {
    private func approved(_ router: MobileLinkRouter, _ destination: MobileLink.Destination) async throws -> MobileLinkRouter.Approved {
        router.bind(account: "demo", refresh: { [7] }, select: { _ in })
        router.receive(.init(makerspaceID: 7, destination: destination)); await router.process()
        return try XCTUnwrap(router.approved)
    }
    func testProductLinkRefetchesBeforeOpeningAndFinishesTicket() async throws {
        let router = MobileLinkRouter(); let value = try await approved(router, .product(1))
        let member = MemberState(repository: DemoMemberRepository()); let navigation = MemberNavigation()
        let drafts = MemberActionDrafts(repository: DemoMemberActionsRepository())
        await MobileLinkDestination.open(value, router: router, member: member, navigation: navigation, drafts: drafts)
        XCTAssertEqual(navigation.selected, .inventory); XCTAssertEqual(navigation.paths[.inventory], [.product(1)])
        XCTAssertNotNil(drafts.product(1, repository: member.repository).product); XCTAssertNil(router.approved)
    }
    func testPushAlwaysRefetchesInboxAndRefusalPreventsItsResourceNavigation() async throws {
        let router = MobileLinkRouter()
        router.bind(account: "demo", refresh: { [7] }, select: { _ in })
        router.receive(try XCTUnwrap(NotificationHint(payload: ["v": 2, "makerspace_id": 7, "link": "/makerspaces/7/inventory/1"])))
        await router.process(); let value = try XCTUnwrap(router.approved); XCTAssertTrue(value.refetchInbox)
        let member = MemberState(repository: DemoMemberRepository(scenario: .offline)); let navigation = MemberNavigation()
        let drafts = MemberActionDrafts(repository: DemoMemberActionsRepository())
        await MobileLinkDestination.open(value, router: router, member: member, navigation: navigation, drafts: drafts)
        XCTAssertEqual(navigation.selected, .home); XCTAssertNil(drafts.product(1, repository: member.repository).error)
        XCTAssertEqual(member.inboxLoad, .failed("Couldn't connect. Try again.")); XCTAssertNotNil(router.error)
    }
    func testMissingResourceLeavesNavigationUnchangedAndOffersSafeRetry() async throws {
        let router = MobileLinkRouter(); let value = try await approved(router, .product(99999))
        let member = MemberState(repository: DemoMemberRepository()); let navigation = MemberNavigation()
        await MobileLinkDestination.open(value, router: router, member: member, navigation: navigation, drafts: MemberActionDrafts(repository: DemoMemberActionsRepository()))
        XCTAssertEqual(navigation.selected, .home); XCTAssertTrue(navigation.paths.isEmpty)
        XCTAssertEqual(router.pending, value.link); XCTAssertEqual(router.error, "This item is no longer available.")
    }
    func testOfflineInboxDoesNotNavigateUsingCachedAuthorityOrRows() async throws {
        let router = MobileLinkRouter(); let value = try await approved(router, .inbox)
        let navigation = MemberNavigation()
        await MobileLinkDestination.open(value, router: router, member: MemberState(repository: DemoMemberRepository(scenario: .offline)), navigation: navigation, drafts: MemberActionDrafts(repository: DemoMemberActionsRepository()))
        XCTAssertEqual(navigation.selected, .home); XCTAssertNotNil(router.error); XCTAssertNil(router.approved)
    }
    func testFinishedOrLoggedOutTicketCannotNavigateEvenIfFreshResourceExists() async throws {
        let router = MobileLinkRouter(); let value = try await approved(router, .inbox); router.unbind()
        let member = MemberState(repository: DemoMemberRepository()); let navigation = MemberNavigation()
        await MobileLinkDestination.open(value, router: router, member: member, navigation: navigation, drafts: MemberActionDrafts(repository: DemoMemberActionsRepository()))
        XCTAssertEqual(member.inboxLoad, .idle); XCTAssertEqual(navigation.selected, .home)
    }
}
#endif
