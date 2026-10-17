import SwiftUI

struct AccountAccessView: View {
    @Bindable var form: AccountAccessState
    let close: () -> Void
    @FocusState private var focused: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandWordmark()
                if form.isDemo { Label("Demo mode · no account changes are made", systemImage: "info.circle").foregroundStyle(Color.swMuted) }
                SWCard {
                    Text(heading).brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                    Text(explanation).foregroundStyle(Color.swMuted)
                    switch form.step {
                    case .signUp:
                        input(String(localized: "Name"), value: $form.name, id: "signup-name", type: .name)
                        input(String(localized: "Email"), value: $form.email, id: "account-email", type: .emailAddress)
                        PasswordControl(title: String(localized: "Password"), text: $form.password, newPassword: true, identifier: "account-password")
                        PasswordControl(title: String(localized: "Confirm password"), text: $form.confirmation, newPassword: true, identifier: "account-confirm-password")
                        DisclosureGroup("Phone number (optional)") {
                            input(String(localized: "Phone number"), value: $form.phone, id: "account-phone", type: .telephoneNumber)
                        }.padding(.vertical, 8)
                        primary(String(localized: "Create account")) { await form.signUp() }
                    case .requestReset:
                        input(String(localized: "Email"), value: $form.email, id: "account-email", type: .emailAddress)
                        primary(String(localized: "Request recovery code")) { await form.requestCode() }
                    case .confirmReset:
                        Text(form.email).textSelection(.enabled).foregroundStyle(Color.swMuted)
                        codeInput(String(localized: "Six-digit code"))
                        PasswordControl(title: String(localized: "New password"), text: $form.password, newPassword: true, identifier: "account-password")
                        PasswordControl(title: String(localized: "Confirm password"), text: $form.confirmation, newPassword: true, identifier: "account-confirm-password")
                        primary(String(localized: "Update password")) { await form.confirmReset() }
                        resend(String(localized: "Request another code")) { await form.requestCode(resending: true) }
                        Button("Change email") { form.changeEmail() }.frame(minHeight: 48)
                    case .emailVerification:
                        Text(form.email).textSelection(.enabled).foregroundStyle(Color.swMuted)
                        codeInput(String(localized: "Verification code"))
                        primary(String(localized: "Confirm email")) { await form.confirmEmail() }
                        resend(String(localized: "Send another code")) { await form.resendEmail() }
                    case .created, .resetComplete, .unavailable:
                        Image(systemName: form.step == .unavailable ? "person.crop.circle.badge.questionmark" : "checkmark.circle")
                            .brandFont(.largeTitle).foregroundStyle(Color.swAccentInk).accessibilityHidden(true)
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
            .safeAreaInset(edge: .top, spacing: 0) {
                if focused == "account-code" {
                    HStack {
                        Spacer()
                        Button { focused = nil } label: {
                            Text("Done").frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("account-code-keyboard-done")
                    }.padding(.horizontal, 24).padding(.vertical, 8)
                        .foregroundStyle(Color.swAccentInk).background(Color.swSurface)
                }
            }
            .interactiveDismissDisabled(form.busy)
            .onDisappear { form.clearSecrets() }
    }
    private var heading: String {
        switch form.step {
        case .signUp: return String(localized: "Create your account")
        case .created: return String(localized: "Account created")
        case .requestReset: return String(localized: "Reset password")
        case .confirmReset: return String(localized: "Enter your recovery code")
        case .resetComplete: return String(localized: "Password updated")
        case .unavailable: return String(localized: "Password recovery unavailable")
        case .emailVerification: return String(localized: "Confirm your email")
        }
    }
    private var explanation: String {
        if form.isDemo {
            switch form.step {
            case .requestReset, .confirmReset: return String(localized: "No message is sent in this demo. Use the sample recovery code 123456.")
            case .emailVerification: return String(localized: "No message is sent in this demo. Use the sample verification code 123456.")
            case .created: return String(localized: "Simulated account creation. No account was created on a server.")
            case .resetComplete: return String(localized: "Simulated password update. No real account was changed.")
            default: break
            }
        }
        switch form.step {
        case .signUp: return String(localized: "Use the email you want to use with your makerspace.")
        case .created: return String(localized: "Sign in to continue. You may need to confirm your email.")
        case .requestReset: return String(localized: "Enter your account email to request a six-digit recovery code.")
        case .confirmReset: return String(localized: "If an account matches this email, a recovery code will arrive. Delivery may take a few minutes.")
        case .resetComplete: return String(localized: "Your password has been updated. You can now sign in.")
        case .unavailable: return String(localized: "Contact your makerspace staff to reset your password.")
        case .emailVerification: return String(localized: "Enter the six-digit code sent to your email.")
        }
    }
    private func input(_ title: String, value: Binding<String>, id: String, type: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).brandFont(.headline)
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
            Text(title).brandFont(.headline)
            TextField(title, text: $form.code, prompt: Text(title).foregroundColor(Color.swMuted)).keyboardType(.numberPad).textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never).autocorrectionDisabled().monospacedDigit()
                .focused($focused, equals: "account-code").accessibilityIdentifier("account-code").padding(14).frame(minHeight: 48)
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
                    Text(CooldownCopy.retryMessage(until: form.resendAfter, now: tick.date))
                        .brandFont(.caption).foregroundStyle(Color.swMuted)
                }
            }
        }
    }
}
