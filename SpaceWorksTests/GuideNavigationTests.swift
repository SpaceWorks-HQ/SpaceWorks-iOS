#if DEBUG
import XCTest
@testable import SpaceWorks

@MainActor final class GuideNavigationTests: XCTestCase {
    func testBookingsShortcutKeepsRetainedActivityHistoryAndUnsavedDrafts() async throws {
        let navigation = MemberNavigation()
        let repository = DemoMemberActionsRepository()
        let drafts = MemberActionDrafts(repository: repository)
        let spaces = try await DemoMemberRepository().spaces()
        let space = try XCTUnwrap(spaces.first)
        let booking = drafts.booking(space)
        booking.start = booking.start.addingTimeInterval(900)
        let editedDate = booking.start
        await drafts.profile.load(); drafts.profile.displayName = "Unsaved maker"
        navigation.path(.activity).wrappedValue = [.space(space.public_token)]
        navigation.path(.profile).wrappedValue = [.contact]
        navigation.openBookings()
        XCTAssertEqual(navigation.selected, .activity)
        XCTAssertEqual(navigation.paths[.activity], [.space(space.public_token), .bookings])
        XCTAssertEqual(navigation.paths[.profile], [.contact])
        XCTAssertTrue(drafts.booking(space) === booking)
        XCTAssertEqual(booking.start, editedDate)
        XCTAssertEqual(drafts.profile.displayName, "Unsaved maker")
    }
    func testBookingsShortcutDoesNotDuplicateAndScopeInvalidationClearsHistory() {
        let navigation = MemberNavigation(); navigation.open(.event("event-token"), tab: .activity)
        navigation.openBookings(); navigation.openBookings()
        XCTAssertEqual(navigation.paths[.activity], [.event("event-token"), .bookings])
        navigation.invalidate()
        XCTAssertTrue(navigation.paths.isEmpty); XCTAssertEqual(navigation.selected, .home)
    }
}
#endif
