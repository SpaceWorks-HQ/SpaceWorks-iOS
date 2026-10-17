#if DEBUG
import XCTest
@testable import SpaceWorks

@MainActor final class DemoDeletionTests: XCTestCase {
    func testAllMakerspaceBlockersIncludingUnknownDetailRemainVisibleAndCannotDelete() {
        var deleted = false
        let state = DemoDeletionState(onDelete: { deleted = true }); state.checkBlockers()
        XCTAssertEqual(state.stage, .blockers); XCTAssertEqual(state.blockers.count, 13)
        XCTAssertEqual(Set(state.blockers.map(\.makerspace)), ["Fab Lab Kochi", "Maker Space Bengaluru", "This server"])
        XCTAssertEqual(state.blockers.last?.detail, "A makerspace review must finish before deletion can proceed.")
        state.credential = "DemoPass!123"; state.authenticate(); state.confirmation = "DELETE"; state.deletePreviewAccount()
        XCTAssertFalse(deleted); XCTAssertFalse(state.canConfirm)
    }
    func testDeletionRequiresFreshProofExactTypedConfirmationAndOnlyClearsDemoOnce() {
        var deletions = 0
        let state = DemoDeletionState(onDelete: { deletions += 1 }); state.scenario = .ready; state.checkBlockers()
        state.confirmation = "DELETE"; state.deletePreviewAccount(); XCTAssertEqual(deletions, 0)
        state.credential = "wrong"; state.authenticate(); XCTAssertEqual(state.stage, .reauthenticate); XCTAssertEqual(state.credential, "")
        state.credential = "DemoPass!123"; state.authenticate(); XCTAssertEqual(state.stage, .confirm)
        state.confirmation = "delete"; state.deletePreviewAccount(); XCTAssertEqual(deletions, 0)
        state.confirmation = "DELETE"; state.deletePreviewAccount(); state.deletePreviewAccount()
        XCTAssertEqual(deletions, 1); XCTAssertEqual(state.stage, .deleted); XCTAssertEqual(state.confirmation, "")
    }
    func testConfirmationConflictReplacesBlockersAndErasesReauthenticationProof() {
        var deleted = false
        let state = DemoDeletionState(onDelete: { deleted = true }); state.scenario = .conflict; state.checkBlockers()
        state.credential = "DemoPass!123"; state.authenticate(); state.confirmation = "DELETE"; state.deletePreviewAccount()
        XCTAssertEqual(state.stage, .blockers); XCTAssertEqual(state.blockers.map(\.id), ["active_loans"])
        XCTAssertFalse(state.canConfirm); XCTAssertFalse(deleted); XCTAssertEqual(state.confirmation, "")
        state.checkBlockers(); XCTAssertEqual(state.stage, .blockers); XCTAssertEqual(state.blockers.map(\.id), ["active_loans"])
    }
    func testExpiredProofRequiresIdentityAgainAndInvalidationCancelsDeletion() {
        var clock = Date(); var deleted = false
        let state = DemoDeletionState(now: { clock }, onDelete: { deleted = true }); state.scenario = .ready; state.checkBlockers()
        state.method = .authenticator; state.credential = "123456"; state.authenticate(); state.confirmation = "DELETE"
        clock = clock.addingTimeInterval(301); state.deletePreviewAccount(); XCTAssertEqual(state.stage, .reauthenticate)
        state.credential = "123456"; state.authenticate(); state.confirmation = "DELETE"; state.invalidate(); state.deletePreviewAccount()
        XCTAssertFalse(deleted); XCTAssertEqual(state.credential, ""); XCTAssertEqual(state.confirmation, "")
    }
}
#endif
