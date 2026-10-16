#if DEBUG
import Foundation
import Observation

@MainActor @Observable
final class DemoProviderState {
    enum Outcome: String, CaseIterable { case success = "Success", unavailable = "Unavailable", rejected = "Rejected", expired = "Expired code" }
    enum Step { case phone, code, account }
    var outcome = Outcome.success
    var step = Step.phone
    var country = "+91"
    var phone = ""
    var code = ""
    private(set) var error: String?
    private(set) var resendAfter = Date.distantPast
    private let now: () -> Date
    init(now: @escaping () -> Date = Date.init) { self.now = now }
    func sendCode() {
        guard now() >= resendAfter else { return }
        guard phone.count >= 6, phone.count <= 14, phone.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            error = "Enter a valid phone number."; return
        }
        code = ""; error = nil; resendAfter = now().addingTimeInterval(60); step = .code
    }
    func changeNumber() { code = ""; error = nil; step = .phone }
    func complete(phone: Bool) -> Bool {
        error = nil
        switch outcome {
        case .unavailable: error = "This sign-in option isn't available on this device."; return false
        case .rejected: error = "Sign-in couldn't be completed. Try again."; return false
        case .expired: error = "That verification code expired. Request another code."; return false
        case .success:
            if phone && code != "123456" { error = "That code didn't work. Check it and try again."; return false }
            code = ""; return true
        }
    }
}
#endif
