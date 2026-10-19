#if DEBUG
import XCTest
@testable import SpaceWorks

@MainActor final class DemoEmailVerificationTests: XCTestCase {
    func testEmailPreviewRejectsWrongCodeAndUsesSharedResendCooldownBeforeContinuing() async {
        let session = DemoSession(); session.username = "unverified"; session.password = "sample"; session.signIn()
        XCTAssertEqual(session.stage, .emailVerification)
        let form = session.emailVerificationForm(); await form.resendEmail()
        XCTAssertEqual(form.notice, "Demo code ready. Use 123456. No email was sent.")
        XCTAssertFalse(session.emailVerificationForm().canResend)
        form.code = "000000"; await form.confirmEmail()
        XCTAssertFalse(session.demoEmailConfirmed); XCTAssertEqual(session.stage, .emailVerification)
        form.code = "123456"; await form.confirmEmail()
        XCTAssertTrue(session.demoEmailConfirmed); XCTAssertEqual(form.notice, "Email confirmed."); XCTAssertTrue(form.code.isEmpty)
        session.finishEmailVerification(expectedFlowID: session.emailFlowID); XCTAssertEqual(session.stage, .makerspace)
    }
    func testRetiredEmailFormCannotMutateANewUnverifiedFlowAfterReset() async {
        let session = DemoSession(); session.username = "unverified"; session.password = "sample"; session.signIn()
        let form = session.emailVerificationForm(); let retiredID = session.emailFlowID; session.reset()
        XCTAssertEqual(session.stage, .welcome)
        session.username = "unverified"; session.password = "sample"; session.signIn()
        XCTAssertNotEqual(session.emailFlowID, retiredID); XCTAssertEqual(session.stage, .emailVerification)
        form.code = "123456"; await form.confirmEmail(); await form.resendEmail()
        session.finishEmailVerification(expectedFlowID: retiredID)
        XCTAssertFalse(session.demoEmailConfirmed); XCTAssertEqual(session.stage, .emailVerification)
        XCTAssertTrue(session.emailVerificationForm().canResend, "Retired resend must not affect the replacement flow")
    }
}
#endif
