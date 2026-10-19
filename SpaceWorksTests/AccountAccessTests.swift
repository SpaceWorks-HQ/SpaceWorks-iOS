import XCTest
import SpaceWorksAPI
@testable import SpaceWorks

@MainActor final class AccountAccessTests: XCTestCase {
    private func form(step: AccountAccessState.Step = .requestReset, now: @escaping () -> Date = Date.init,
                      create: @escaping (String, String, String, String) async throws -> Void = { _, _, _, _ in },
                      request: @escaping (String) async throws -> Void = { _ in },
                      reset: @escaping (String, String, String) async throws -> Void = { _, _, _ in }) -> AccountAccessState {
        AccountAccessState(step: step, now: now, create: create, request: request, reset: reset)
    }
    func testSignupAcknowledgementClearsSecretsAndDoesNotCreateSession() async {
        var captured: [String] = []
        let state = form(step: .signUp, create: { captured = [$0, $1, $2, $3] })
        state.name = "  മീര  "; state.email = " meera@example.test "; state.password = "a password"; state.confirmation = "a password"
        await state.signUp()
        XCTAssertEqual(captured, ["മീര", "meera@example.test", "a password", ""])
        XCTAssertEqual(state.step, .created); XCTAssertEqual(state.password, ""); XCTAssertEqual(state.confirmation, "")
    }
    func testResendDeadlineSurvivesEmailEditingAndRespectsLongerServerDeadline() async {
        var clock = Date(timeIntervalSince1970: 100)
        var requests = 0
        let state = form(now: { clock }, request: { _ in
            requests += 1
            if requests == 2 { throw APIError(status: 429, code: "throttled", detail: "Wait.", retryAfter: clock.addingTimeInterval(120)) }
        })
        state.email = "meera@example.test"; await state.requestCode()
        XCTAssertEqual(state.resendAfter, Date(timeIntervalSince1970: 160))
        state.changeEmail(); state.email = "another@example.test"; await state.requestCode()
        XCTAssertEqual(requests, 1)
        clock = Date(timeIntervalSince1970: 161); await state.requestCode()
        XCTAssertEqual(requests, 2); XCTAssertEqual(state.resendAfter, Date(timeIntervalSince1970: 281))
        XCTAssertEqual(state.submitAfter, state.resendAfter)
    }
    func testEveryResetRejectionUsesSameCopyAndNeverLeaksServerPolicy() async {
        for status in [400, 401, 403, 409, 429, 503] {
            let state = form(step: .confirmReset, reset: { _, _, _ in
                throw APIError(status: status, code: "secret_server_policy", detail: "This account exists and password policy failed.")
            })
            state.email = "meera@example.test"; state.code = "123456"; state.password = "new password"; state.confirmation = state.password
            await state.confirmReset()
            XCTAssertEqual(state.error, "Invalid or expired verification code."); XCTAssertEqual(state.step, .confirmReset)
        }
    }
    func testResetLocalValidationPrecedesTransportAndSuccessClearsSecrets() async {
        var requests = 0
        let state = form(step: .confirmReset, reset: { _, code, _ in requests += 1; XCTAssertEqual(code, "123456") })
        state.email = "meera@example.test"; state.code = "123456"; state.password = "short"; state.confirmation = "short"
        await state.confirmReset(); XCTAssertEqual(requests, 0); XCTAssertEqual(state.error, "Use at least 8 characters.")
        state.password = "new password"; state.confirmation = "different password"
        await state.confirmReset(); XCTAssertEqual(requests, 0); XCTAssertEqual(state.error, "Passwords don't match.")
        state.confirmation = state.password; await state.confirmReset()
        XCTAssertEqual(requests, 1); XCTAssertEqual(state.step, .resetComplete)
        XCTAssertEqual(state.password, ""); XCTAssertEqual(state.code, "")
    }
    func testKnownRecoveryUnavailableHasDedicatedState() async {
        let state = form(request: { _ in throw APIError(status: 503, code: "recovery_unavailable", detail: "Unavailable.") })
        state.email = "meera@example.test"; await state.requestCode()
        XCTAssertEqual(state.step, .unavailable)
        let transient = form(request: { _ in throw APIError(status: 503, code: "service_unavailable", detail: "Try later.") })
        transient.email = "meera@example.test"; await transient.requestCode()
        XCTAssertEqual(transient.step, .requestReset); XCTAssertEqual(transient.error, "Try later.")
    }
    func testPhonePreviewResendCannotBeBypassedByChangingNumber() {
        var clock = Date(timeIntervalSince1970: 100)
        let state = DemoProviderState(now: { clock })
        state.phone = "9876543210"; state.sendCode()
        XCTAssertEqual(state.step, .code)
        state.changeNumber(); state.phone = "9876543211"; state.sendCode()
        XCTAssertEqual(state.step, .phone)
        clock = clock.addingTimeInterval(61); state.sendCode()
        XCTAssertEqual(state.step, .code)
        state.code = "wrong"; XCTAssertFalse(state.complete(phone: true))
        state.code = "123456"; XCTAssertTrue(state.complete(phone: true)); XCTAssertEqual(state.code, "")
    }
    func testProviderPreviewRefusalsNeverCompleteSignIn() {
        for outcome in [DemoProviderState.Outcome.unavailable, .rejected, .expired] {
            let state = DemoProviderState(); state.outcome = outcome
            XCTAssertFalse(state.complete(phone: false)); XCTAssertNotNil(state.error)
        }
    }
    func testClosingAndReopeningRecoverySharesOnlyServerScopedDeadlines() async {
        let scope = "https://\(UUID().uuidString).example/password-recovery"
        let clock = Date(timeIntervalSince1970: 100)
        let first = AccountAccessState(step: .requestReset, now: { clock }, cooldown: AccountAccessCooldown.scoped(scope),
                                       create: { _, _, _, _ in }, request: { _ in }, reset: { _, _, _ in })
        first.email = "meera@example.test"; await first.requestCode(); first.clearSecrets()
        var calls = 0
        let reopened = AccountAccessState(step: .requestReset, now: { clock }, cooldown: AccountAccessCooldown.scoped(scope),
                                          create: { _, _, _, _ in }, request: { _ in calls += 1 }, reset: { _, _, _ in })
        reopened.email = "another@example.test"; await reopened.requestCode()
        XCTAssertEqual(calls, 0); XCTAssertEqual(reopened.resendAfter, clock.addingTimeInterval(60))
        XCTAssertEqual(reopened.password, ""); XCTAssertEqual(reopened.code, "")
        XCTAssertNotEqual(AccountAccessCooldown.scoped(scope + "-other-server").resendAfter, reopened.resendAfter)
    }
}
