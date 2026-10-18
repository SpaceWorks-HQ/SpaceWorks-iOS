import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

final class MobileLinkTests: XCTestCase {
    private let origin = try! ServerOrigin("https://spaceworks.example")
    func testAllowlistedPathsUseOnlyActualNumericIDsAndPublicUUIDs() {
        let token = "00000000-0000-0000-0000-000000000031"
        for (path, result) in [("home", MobileLink.Destination.home), ("inventory/3", .product(3)), ("activity", .activity), ("inbox", .inbox), ("profile", .profile), ("bookings/" + token, .booking(token)), ("events/" + token, .event(token)), ("registrations/777", .registrations(777)), ("spaces/" + token, .space(token)), ("payments/501", .payment(501))] {
            XCTAssertEqual(MobileLink.path("/makerspaces/7/" + path), .init(makerspaceID: 7, destination: result))
        }
        XCTAssertEqual(MobileLink.path("/makerspaces/7/inventory/not-an-id")?.destination, .inbox)
        XCTAssertEqual(MobileLink.path("/makerspaces/7/new-server-feature")?.destination, .inbox)
    }
    func testUniversalLinksStayOnTheSelectedDeploymentAndDoNotChangeServers() throws {
        for value in ["https://spaceworks.example/makerspaces/7/inbox", "https://spaceworks.example:443/makerspaces/7/inbox"] {
            XCTAssertEqual(MobileLink.url(try XCTUnwrap(URL(string: value)), origin: origin)?.destination, .inbox)
        }
        for value in ["https://evil.example/makerspaces/7/inbox", "http://spaceworks.example/makerspaces/7/inbox", "https://user:secret@spaceworks.example/makerspaces/7/inbox", "https://spaceworks.example:8443/makerspaces/7/inbox", "https://spaceworks.example/makerspaces/7/inbox?token=secret", "https://spaceworks.example/makerspaces/7/inbox#script"] {
            XCTAssertNil(MobileLink.url(try XCTUnwrap(URL(string: value)), origin: origin))
        }
    }
    func testCustomSchemeUsesOnlyTheCurrentServerAndCanonicalInAppPath() throws {
        for value in ["spaceworks://makerspaces/7/inventory/3", "spaceworks:///makerspaces/7/inventory/3"] {
            XCTAssertEqual(MobileLink.url(try XCTUnwrap(URL(string: value)), origin: origin), .init(makerspaceID: 7, destination: .product(3)))
        }
        for value in ["spaceworks://evil.example/makerspaces/7/home", "spaceworks://user@makerspaces/7/home", "javascript:alert(1)", "file:///makerspaces/7/inbox"] {
            XCTAssertNil(MobileLink.url(try XCTUnwrap(URL(string: value)), origin: origin))
        }
    }
    func testLegacyUnknownVersionsAndScopeConflictingPayloadsFallbackToHintMakerspaceInbox() throws {
        let payloads: [[AnyHashable: Any]] = [["makerspace_id": 7], ["makerspace_id": 7, "v": "99", "link": "/makerspaces/7/inventory/3"], ["makerspace_id": 7, "v": "2", "link": "/makerspaces/9/inventory/3"], ["makerspace_id": 7, "v": "2", "link": "https://evil.example/"]]
        for payload in payloads {
            XCTAssertEqual(MobileLink.notification(try XCTUnwrap(NotificationHint(payload: payload))), .init(makerspaceID: 7, destination: .inbox))
        }
    }
    func testExistingInboxLandingLinksOnlyParseExactSafeCurrentOriginShapes() {
        XCTAssertEqual(MobileLink.legacy("/m/fab-lab-kochi/member", origin: origin), .init(slug: "fab-lab-kochi", staffInbox: false))
        XCTAssertEqual(MobileLink.legacy("https://spaceworks.example:443/m/fab-lab-kochi/admin/notifications", origin: origin), .init(slug: "fab-lab-kochi", staffInbox: true))
        // mobile_link_contract.py claims any single member tab; an unknown tab opens Home like the web portal.
        XCTAssertEqual(MobileLink.legacy("/m/fab-lab-kochi/member/extra", origin: origin), .init(slug: "fab-lab-kochi", staffInbox: false))
        for value in ["https://evil.example/m/fab-lab-kochi/member", "https://user@spaceworks.example/m/fab-lab-kochi/member", "/m/fab-lab-kochi/member?token=secret", "/m/fab-lab-kochi/member/extra/more", "/m/fab%2dlab/member", "/m/../member", "/m/fab\\lab/member", "//m/fab/member"] { XCTAssertNil(MobileLink.legacy(value, origin: origin)) }
    }
    func testEncodedTraversalControlCharactersAndInvalidMakerIDsAreRefused() {
        for value in ["//evil.example/makerspaces/7/inbox", "/makerspaces/7/../profile", "/makerspaces/7/./inbox", "/makerspaces/7/%2einbox", "/makerspaces/7/inbox\n", "/makerspaces/0/inbox", "/makerspaces/-7/inbox", "/makerspaces/999999999999999999999999999999/inbox", "/makerspaces/7//inbox"] { XCTAssertNil(MobileLink.path(value)) }
    }
}
