import SwiftUI

struct AccountAccessView: View {
    @Bindable var form: AccountAccessState
    let close: () -> Void
    @FocusState private var focused: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandWordmark()
                SWCard {
                    Text(heading).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(explanation).foregroundStyle(Color.swMuted)
                    switch form.step {
                    case .signUp:
                        input("Name", value: $form.name, id: "signup-name", type: .name)
                        input("Email", value: $form.email, id: "account-email", type: .emailAddress)
                        PasswordControl(title: "Password", text: $form.password, newPassword: true, identifier: "account-password")
                        PasswordControl(title: "Confirm password", text: $form.confirmation, newPassword: true, identifier: "account-confirm-password")
                        DisclosureGroup("Phone number (optional)") {
                            input("Phone number", value: $form.phone, id: "account-phone", type: .telephoneNumber)
                        }.padding(.vertical, 8)
                        primary("Create account") { await form.signUp() }
                    case .requestReset:
                        input("Email", value: $form.email, id: "account-email", type: .emailAddress)
                        primary("Request recovery code") { await form.requestCode() }
                    case .confirmReset:
                        Text(form.email).textSelection(.enabled).foregroundStyle(Color.swMuted)
                        codeInput("Six-digit code")
                        PasswordControl(title: "New password", text: $form.password, newPassword: true, identifier: "account-password")
                        PasswordControl(title: "Confirm password", text: $form.confirmation, newPassword: true, identifier: "account-confirm-password")
                        primary("Update password") { await form.confirmReset() }
                        resend("Request another code") { await form.requestCode(resending: true) }
                        Button("Change email") { form.changeEmail() }.frame(minHeight: 48)
                    case .emailVerification:
                        Text(form.email).textSelection(.enabled).foregroundStyle(Color.swMuted)
                        codeInput("Verification code")
                        primary("Confirm email") { await form.confirmEmail() }
                        resend("Send another code") { await form.resendEmail() }
                    case .created, .resetComplete, .unavailable:
                        Image(systemName: form.step == .unavailable ? "person.crop.circle.badge.questionmark" : "checkmark.circle")
                            .font(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
                        Button(form.step == .unavailable ? "Back to sign in" : "Go to sign in", action: close).buttonStyle(SWPrimary())
                    }
                    if let error = form.error { SWError(message: error) }
                    if let notice = form.notice, form.step != .confirmReset {
                        Label(notice, systemImage: "info.circle").foregroundStyle(Color.swMuted)
                    }
                    if ![.created, .resetComplete, .unavailable].contains(form.step) {
                        Button(form.step == .emailVerification ? "Done" : "Back to sign in", action: close)
                            .frame(minHeight: 48).disabled(form.busy)
                    }
                }.disabled(form.busy)
            }.padding(24).frame(maxWidth: 508).frame(maxWidth: .infinity)
        }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(form.busy)
            .onDisappear { form.clearSecrets() }
    }
    private var heading: String {
        switch form.step {
        case .signUp: return "Create your account"
        case .created: return "Account created"
        case .requestReset: return "Reset password"
        case .confirmReset: return "Enter your recovery code"
        case .resetComplete: return "Password updated"
        case .unavailable: return "Password recovery unavailable"
        case .emailVerification: return "Confirm your email"
        }
    }
    private var explanation: String {
        switch form.step {
        case .signUp: return "Use the email you want to use with your makerspace."
        case .created: return "Sign in to continue. You may need to confirm your email."
        case .requestReset: return "Enter your account email to request a six-digit recovery code."
        case .confirmReset: return "If an account matches this email, a recovery code will arrive. Delivery may take a few minutes."
        case .resetComplete: return "Your password has been updated. You can now sign in."
        case .unavailable: return "Contact your makerspace staff to reset your password."
        case .emailVerification: return "Enter the six-digit code sent to your email."
        }
    }
    private func input(_ title: String, value: Binding<String>, id: String, type: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(title, text: value, prompt: Text(title).foregroundColor(Color.swMuted)).textContentType(type)
                .keyboardType(type == .emailAddress ? .emailAddress : type == .telephoneNumber ? .phonePad : .default)
                .textInputAutocapitalization(type == .name ? .words : .never).autocorrectionDisabled()
                .focused($focused, equals: id).accessibilityIdentifier(id)
                .padding(14).frame(minHeight: 48).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
        }
    }
    private func codeInput(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(title, text: $form.code, prompt: Text(title).foregroundColor(Color.swMuted)).keyboardType(.numberPad).textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never).autocorrectionDisabled().monospacedDigit()
                .accessibilityIdentifier("account-code").padding(14).frame(minHeight: 48)
                .background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
        }
    }
    private func primary(_ title: String, action: @escaping () async -> Void) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            Button(form.busy ? "Please wait…" : title) { focused = nil; Task { await action() } }
                .buttonStyle(SWPrimary()).disabled(form.busy || tick.date < form.submitAfter)
        }
    }
    private func resend(_ title: String, action: @escaping () async -> Void) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            VStack(alignment: .leading, spacing: 4) {
                Button(title) { Task { await action() } }.frame(minHeight: 48)
                    .disabled(form.busy || tick.date < form.resendAfter)
                if tick.date < form.resendAfter {
                    Text("Try again in \(max(1, Int(ceil(form.resendAfter.timeIntervalSince(tick.date)))))s.")
                        .font(.caption).foregroundStyle(Color.swMuted)
                }
            }
        }
    }
}
