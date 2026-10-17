#if DEBUG
import SwiftUI
import SpaceWorksAPI

extension DemoSession {
    func emailVerificationForm() -> AccountAccessState {
        let flowID = emailFlowID
        let form = AccountAccessState(step: .emailVerification, cooldown: emailCooldown, isDemo: true,
            create: { _, _, _, _ in }, request: { _ in }, reset: { _, _, _ in },
            verify: { [weak self] code in
                guard let self, self.stage == .emailVerification, self.emailFlowID == flowID else { throw CancellationError() }
                guard code == "123456" else { throw APIError(status: 400, code: "invalid_code", detail: String(localized: "Invalid or expired verification code.")) }
                self.demoEmailConfirmed = true
            }, resendVerification: { [weak self] in
                guard let self, self.stage == .emailVerification, self.emailFlowID == flowID else { throw CancellationError() }
            })
        form.email = "meera@example.invalid"
        return form
    }
    func finishEmailVerification(expectedFlowID: UUID) {
        guard stage == .emailVerification, emailFlowID == expectedFlowID else { return }
        stage = demoEmailConfirmed ? membershipStage : .signIn
    }
}
struct DemoEmailVerificationView: View {
    let session: DemoSession
    private let flowID: UUID
    @State private var form: AccountAccessState
    init(session: DemoSession) {
        self.session = session; flowID = session.emailFlowID; _form = State(initialValue: session.emailVerificationForm())
    }
    var body: some View { AccountAccessView(form: form) { session.finishEmailVerification(expectedFlowID: flowID) } }
}
#endif
