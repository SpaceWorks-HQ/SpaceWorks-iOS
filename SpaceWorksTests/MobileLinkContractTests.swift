import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

/// Mirrors backend/apps/integrations/mobile_link_contract.py DESTINATIONS and EXCLUDED_PREFIXES.
@MainActor final class MobileLinkContractTests: XCTestCase {
    private let token = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

    func testSharedHostContractDestinationsResolveThroughTheirSlug() throws {
        let origin = try ServerOrigin("https://spaceworks.example")
        let cases: [(String, MobileLink.Destination)] = [
            ("/m/fab-lab/member", .home), ("/m/fab-lab/member/", .home), ("/m/fab-lab/member/overview", .home),
            ("/m/fab-lab/member/loans", .activity), ("/m/fab-lab/member/bookings", .bookings), ("/m/fab-lab/member/events", .events),
            ("/m/fab-lab/member/payments", .payments), ("/m/fab-lab/member/inbox", .inbox), ("/m/fab-lab/member/account", .profile),
            ("/m/fab-lab/member/events/41/ticket", .registrations(41)), ("/m/fab-lab/events/\(token)", .event(token)),
            ("/m/fab-lab/bookings/\(token)", .booking(token)), ("/m/fab-lab/items/12", .product(12)),
            ("https://spaceworks.example/m/fab-lab/items/12", .product(12))]
        for (path, destination) in cases {
            let legacy = try XCTUnwrap(MobileLink.legacy(path, origin: origin), path)
            XCTAssertEqual(legacy.slug, "fab-lab", path); XCTAssertFalse(legacy.staffInbox, path)
            XCTAssertEqual(legacy.link(makerspaceID: 7), MobileLink(makerspaceID: 7, destination: destination), path)
        }
    }

    func testExcludedAndMalformedPathsAreNeverClaimed() throws {
        let origin = try ServerOrigin("https://spaceworks.example")
        for path in ["/m/fab-lab/admin", "/m/fab-lab/admin/requests", "/control", "/api/v1/auth/me", "/m/fab-lab/events/not-a-token",
                     "/m/fab-lab/items/0", "/m/fab-lab/member/events/x/ticket", "/m/fab-lab/member/a/b", "/m/fab-lab/items/12?x=1",
                     "https://other.example/m/fab-lab/member", "/m/fab lab/member"] {
            XCTAssertNil(MobileLink.legacy(path, origin: origin), path)
        }
        XCTAssertEqual(MobileLink.legacy("/m/fab-lab/admin/notifications", origin: origin)?.staffInbox, true, "The legacy staff inbox link is unchanged")
    }

    func testCustomDomainFormsNeedAKnownMakerspace() {
        XCTAssertEqual(MobileLink.customDomain("/member"), .home)
        XCTAssertEqual(MobileLink.customDomain("/member/account"), .profile)
        XCTAssertEqual(MobileLink.customDomain("/events/\(token)"), .event(token))
        XCTAssertEqual(MobileLink.customDomain("/items/9"), .product(9))
        XCTAssertNil(MobileLink.customDomain("/admin"))
        XCTAssertNil(MobileLink.customDomain("/m/fab-lab/member"), "A shared-host path is not a custom-domain path")
    }

    func testAPNsDataDictionaryCarriesTheVersionTwoRoutingKeys() throws {
        let payload: [AnyHashable: Any] = ["aps": ["alert": ["title": "Fab Lab", "body": "Your loan is due"], "thread-id": "7"],
                                           "data": ["v": "2", "event_id": "evt-1", "makerspace_id": "7", "feature": "loans",
                                                    "event": "loan.due", "inbox_row_id": "55", "link": "/m/fab-lab/member/loans", "unknown": "kept out"]]
        let hint = try XCTUnwrap(NotificationHint(payload: payload))
        XCTAssertEqual(hint.makerspaceID, 7); XCTAssertEqual(hint.version, 2); XCTAssertEqual(hint.eventID, "evt-1")
        XCTAssertEqual(hint.inboxRowID, 55); XCTAssertEqual(hint.relativeLink, "/m/fab-lab/member/loans")
        let flat = try XCTUnwrap(NotificationHint(payload: ["makerspace_id": "8"]))
        XCTAssertEqual(flat.version, 1, "A missing version is v1"); XCTAssertNil(flat.relativeLink)
    }

    func testPushContractLinkKeepsItsDestinationAndExplicitMakerspace() async throws {
        let router = MobileLinkRouter()
        router.bind(account: "account", refresh: { [7, 8] }, select: { XCTAssertEqual($0, 7) }, resolveLegacy: { legacy in
            XCTAssertEqual(legacy.slug, "fab-lab"); return legacy.link(makerspaceID: 7)
        })
        router.receive(try XCTUnwrap(NotificationHint(payload: ["data": ["v": "2", "makerspace_id": "7", "link": "/m/fab-lab/member/loans"]])))
        await router.process()
        XCTAssertEqual(router.approved?.link, MobileLink(makerspaceID: 7, destination: .activity))
        XCTAssertEqual(router.approved?.refetchInbox, true)
        let custom = MobileLinkRouter()
        custom.bind(account: "account", refresh: { [7] }, select: { _ in })
        custom.receive(try XCTUnwrap(NotificationHint(payload: ["data": ["v": "2", "makerspace_id": "7", "link": "/items/12"]])))
        await custom.process()
        XCTAssertEqual(custom.approved?.link, MobileLink(makerspaceID: 7, destination: .product(12)))
    }
}
