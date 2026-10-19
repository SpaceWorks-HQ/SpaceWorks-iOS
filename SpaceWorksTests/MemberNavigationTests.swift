import XCTest
@testable import SpaceWorks

@MainActor final class MemberNavigationTests: XCTestCase {
    func testAdaptiveBranchesUseSamePerTabHistoryAndPreserveOtherDestinations() {
        let state = MemberNavigation()
        state.path(.inventory).wrappedValue = [.product(3)]
        state.selected = .profile; state.path(.profile).wrappedValue = [.contact]
        state.selected = .inventory
        XCTAssertEqual(state.path(.inventory).wrappedValue, [.product(3)])
        XCTAssertEqual(state.path(.profile).wrappedValue, [.contact])
    }
    func testCompactInventoryKeepsTabletSelectionAndDoesNotDuplicateExistingHistory() {
        let state = MemberNavigation(); state.selected = .inventory; state.inventorySelection = 4
        state.compactInventory(); XCTAssertEqual(state.path(.inventory).wrappedValue, [.product(4)])
        state.compactInventory(); XCTAssertEqual(state.path(.inventory).wrappedValue.count, 1)
    }
    func testContextInvalidationRemovesProtectedNavigationAndSelection() {
        let state = MemberNavigation(); state.open(.registration(11), tab: .activity); state.inventorySelection = 4
        state.invalidate()
        XCTAssertTrue(state.paths.isEmpty); XCTAssertNil(state.inventorySelection); XCTAssertEqual(state.selected, .home)
    }
    func testProfileAndBookingDraftsSurviveLayoutReconstructionUntilContextInvalidation() async throws {
        let repository = DemoMemberActionsRepository()
        let drafts = MemberActionDrafts(repository: repository)
        await drafts.profile.load(); drafts.profile.displayName = "Unsaved maker"
        let spaces = try await DemoMemberRepository().spaces(); let space = try XCTUnwrap(spaces.first)
        let first = drafts.booking(space); first.start = first.start.addingTimeInterval(600)
        let reconstructed = drafts.booking(space)
        XCTAssertTrue(first === reconstructed); XCTAssertEqual(reconstructed.start, first.start)
        XCTAssertEqual(drafts.profile.displayName, "Unsaved maker")
        drafts.invalidate(); XCTAssertEqual(drafts.profile.displayName, "")
        await first.check(); XCTAssertNil(first.availability)
    }
    func testPoppingCompactInventoryDoesNotReopenThePreviousTabletSelection() {
        let state = MemberNavigation(); state.selected = .inventory; state.inventorySelection = 4
        state.compactInventory(); state.path(.inventory).wrappedValue = []
        state.compactInventory(); XCTAssertTrue(state.path(.inventory).wrappedValue.isEmpty); XCTAssertNil(state.inventorySelection)
    }

}
