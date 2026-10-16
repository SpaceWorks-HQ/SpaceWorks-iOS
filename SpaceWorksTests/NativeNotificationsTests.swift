import XCTest
@testable import SpaceWorks

final class NativeNotificationsTests: XCTestCase {
    func testLegacyPayloadUsesMembershipInboxAndIgnoresLink() {
        let hint = NotificationHint(payload: ["makerspace_id": "7", "link": "/inventory/123"])
        XCTAssertEqual(hint?.version, 1)
        XCTAssertEqual(hint?.makerspaceID, 7)
        XCTAssertNil(hint?.relativeLink)
    }

    func testVersionTwoCarriesOnlyRelativeHintAndIdentifiers() {
        let hint = NotificationHint(payload: ["v": "2", "makerspace_id": 7, "event_id": "event-1",
            "inbox_row_id": "9", "link": "/inventory/123", "unknown": "ignored"])
        XCTAssertEqual(hint?.eventID, "event-1")
        XCTAssertEqual(hint?.inboxRowID, 9)
        XCTAssertEqual(hint?.relativeLink, "/inventory/123")
    }

    func testUntrustedLinksFallBackToInbox() {
        for link in ["https://evil.invalid", "//evil.invalid", "/../profile", "/%2e%2e/profile",
                     "/inventory?redirect=https://evil.invalid", "/inventory#secret", "/inventory\\evil", "/bad\ncode"] {
            XCTAssertNil(NotificationHint(payload: ["v": "2", "makerspace_id": "7", "link": link])?.relativeLink, link)
        }
    }

    func testMissingOrInvalidMembershipDoesNotRoute() {
        let values: [Any] = ["", "0", "-1", "1.5", true, "9999999999999999999999999999999999999999"]
        for value in values {
            XCTAssertNil(NotificationHint(payload: ["makerspace_id": value]))
        }
        XCTAssertNil(NotificationHint(payload: [:]))
    }

    func testUnknownVersionRetainsOnlyInboxMembership() {
        let hint = NotificationHint(payload: ["v": "99", "makerspace_id": "7", "event_id": "unsafe", "link": "/profile"])
        XCTAssertEqual(hint?.makerspaceID, 7)
        XCTAssertNil(hint?.eventID)
        XCTAssertNil(hint?.relativeLink)
    }

    @MainActor func testForegroundReceiptRefreshesWithoutBecomingATapOrRetainingPayload() throws {
        let notifications = NativeNotifications()
        let hint = try XCTUnwrap(NotificationHint(payload: ["v": "2", "makerspace_id": "7", "link": "/makerspaces/7/inventory/12"]))
        var received: [NotificationHint] = []; var taps = 0
        notifications.onForegroundHint = { received.append($0) }; notifications.onTap = { _ in taps += 1 }
        notifications.receivedInForeground(hint)
        XCTAssertEqual(received, [hint]); XCTAssertEqual(taps, 0); XCTAssertNil(notifications.pendingHint)
        notifications.reset(); notifications.receivedInForeground(hint)
        XCTAssertEqual(received.count, 1)
    }

    @MainActor func testColdLaunchHintWaitsForAuthenticatedRouterAndDeliversOnce() throws {
        let notifications = NativeNotifications()
        let hint = try XCTUnwrap(NotificationHint(payload: ["makerspace_id": "7"]))
        notifications.receive(hint)
        XCTAssertEqual(notifications.pendingHint, hint)
        var received: [NotificationHint] = []
        notifications.onTap = { received.append($0) }
        XCTAssertEqual(received, [hint])
        XCTAssertNil(notifications.pendingHint)
        notifications.onTap = { received.append($0) }
        XCTAssertEqual(received.count, 1)
    }
}
