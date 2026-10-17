#if DEBUG
import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class DemoAccountScopeTests: XCTestCase {
    func testZeroMembershipSignInStillOffersGlobalDeviceManagement() async {
        let session = DemoSession(); session.scenario = .noMemberships; session.username = "member"; session.password = "sample"
        session.signIn(); XCTAssertEqual(session.stage, .noMakerspaces); XCTAssertTrue(session.availableSpaces.isEmpty)
        let account = session.accountState(makerspaceID: nil)
        await account.loadGrants()
        XCTAssertFalse(account.grants.isEmpty); XCTAssertFalse(account.memberSelfServiceAvailable); XCTAssertFalse(account.dataExportAvailable)
        session.securityEnded(codes: [], message: "Sign in again."); session.finishSecurityTransition()
        session.username = "member"; session.password = "sample"; session.signIn()
        XCTAssertEqual(session.stage, .noMakerspaces, "Fresh sign-in must not strand a zero-membership account on an empty picker")
    }
    func testGlobalProvidersAndPhoneCooldownFollowAccountAcrossMakerspaces() async {
        let session = DemoSession()
        let first = session.accountState(makerspaceID: 7)
        await first.previewProviderLink("apple", outcome: .success)
        first.phone = "9876543210"; await first.sendPhoneCode()
        let second = session.accountState(makerspaceID: 8); await second.loadProviders()
        XCTAssertTrue(second.providers.contains { $0.provider == "apple" })
        XCTAssertEqual(first.resendAfter, second.resendAfter); XCTAssertGreaterThan(second.resendAfter, Date())
        session.reset()
        XCTAssertEqual(session.accountState(makerspaceID: 7).resendAfter, .distantPast)
    }
    func testLeavingOneDemoMakerspaceDoesNotRevokeAnotherMembership() async throws {
        let session = DemoSession(); session.stage = .shell
        let first = session.accountState(makerspaceID: 7), second = session.accountState(makerspaceID: 8)
        first.updateCapabilities(selfService: true, exports: true); second.updateCapabilities(selfService: true, exports: true)
        await first.loadMembership()
        let remaining = try await second.repository.membership()
        XCTAssertEqual(remaining.status.rawValue, "active")
        first.membershipReason = "Moving away"; await first.leaveMakerspace()
        XCTAssertEqual(session.availableSpaces, [1]); XCTAssertEqual(session.stage, .makerspace)
        XCTAssertEqual(session.selectedSpace, 1)
    }
    func testSecurityCompletionClearsSecretsAndRequiresExplicitReturn() {
        let session = DemoSession(); session.stage = .shell; session.password = "secret"; session.code = "123456"
        session.securityEnded(codes: ["one-use-demo"], message: "Save these codes.")
        XCTAssertEqual(session.stage, .securityCompletion); XCTAssertEqual(session.password, ""); XCTAssertEqual(session.code, "")
        XCTAssertEqual(session.securityCodes, ["one-use-demo"])
        session.finishSecurityTransition()
        XCTAssertEqual(session.stage, .signIn); XCTAssertTrue(session.securityCodes.isEmpty); XCTAssertNil(session.securityMessage)
    }
    func testBlockerFixSelectsActualAuthorizedMakerspaceBeforeRouting() {
        let session = DemoSession(); session.stage = .shell
        let blocker = DemoDeletionState.sampleBlockers.first { $0.makerspace == "Maker Space Bengaluru" }!
        session.routeAccountBlocker(blocker)
        XCTAssertEqual(session.selectedSpace, 1); XCTAssertEqual(session.pendingAccountFix?.id, blocker.id)
        session.reset(); XCTAssertNil(session.pendingAccountFix)
    }
}
#endif
