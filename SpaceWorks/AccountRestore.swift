import Foundation
import Observation
import SwiftUI
import SpaceWorksAPI

/// Identity-only restore of a deleted phone account. It never returns a session: the person signs in
/// afresh, and memberships, sessions and notifications stay revoked until the makerspace restores them.
@MainActor @Observable
final class AccountRestoreState: Identifiable {
    enum Step: Equatable { case number, code, restored }
    let id = UUID()
    var number = ""
    var code = ""
    var password = ""
    var confirmation = ""
    private(set) var step = Step.number
    private(set) var busy = false
    private(set) var error: String?
    private(set) var resendAfter = Date.distantPast
    private(set) var phone: String?
    private var started: PhoneSignInState.Started?
    private let begin: @MainActor (String) async throws -> PhoneSignInState.Started
    private let restore: @MainActor (String, String, String, String) async throws -> Components.Schemas.AccountRestoreResult
    private let now: () -> Date

    init(begin: @escaping @MainActor (String) async throws -> PhoneSignInState.Started,
         restore: @escaping @MainActor (String, String, String, String) async throws -> Components.Schemas.AccountRestoreResult,
         now: @escaping () -> Date = Date.init) {
        self.begin = begin; self.restore = restore; self.now = now
    }

    func send() async {
        guard !busy, now() >= resendAfter else { return }
        guard let phone = PhoneSignInState.normalized(step == .code ? (phone ?? number) : number) else {
            error = String(localized: "Enter your phone number with its country code."); return
        }
        busy = true; error = nil
        defer { busy = false }
        do {
            started = try await begin(phone)
            self.phone = phone; code = ""; step = .code; resendAfter = now().addingTimeInterval(60)
        } catch {
            if !APIError.isCancellation(error) { self.error = APIError.display(error) }
            if let deadline = APIError.retryDeadline(error) { resendAfter = deadline }
        }
    }

    func submit() async {
        guard !busy, step == .code, let phone else { return }
        let digits = code.filter { $0.isASCII && $0.isNumber }
        guard digits.count == 6 else { error = String(localized: "Enter the six-digit code."); return }
        guard !password.isEmpty, password == confirmation else { error = String(localized: "Enter matching new passwords."); return }
        guard let started, now() < started.expires else {
            self.started = nil; code = ""; resendAfter = .distantPast
            error = String(localized: "Your code expired. Send a new code."); return
        }
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await restore(phone, digits, password, started.challenge)
            password = ""; confirmation = ""; code = ""
            if result.restored { step = .restored } else { error = result.detail }
        } catch {
            if !APIError.isCancellation(error) { self.error = APIError.display(error) }
        }
    }

    func changeNumber() { guard !busy else { return }; step = .number; code = ""; error = nil; started = nil }
}

struct AccountRestoreView: View {
    @Bindable var form: AccountRestoreState
    @Environment(\.dismiss) private var dismiss
    @State private var passwordFocused = false
    var body: some View {
        NavigationStack {
            ScrollView {
                SWCard {
                    Text("Restore a deleted account").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
                    switch form.step {
                    case .number:
                        Text("Enter the phone number on the deleted account. If it can still be restored, we'll text a code.").foregroundStyle(Color.swMuted)
                        Text("Phone number").brandFont(.headline)
                        TextField("Phone number", text: $form.number, prompt: Text(verbatim: "+91 98765 43210").foregroundColor(Color.swMuted))
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                            .padding(16).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("restore-phone")
                        if let error = form.error { SWError(message: error) }
                        Button(form.busy ? "Sending…" : "Send verification code") { Task { await form.send() } }
                            .buttonStyle(SWPrimary()).disabled(form.busy).accessibilityIdentifier("restore-send")
                    case .code:
                        Text("Enter the code we sent and choose a new password.").foregroundStyle(Color.swMuted)
                        Text("Verification code").brandFont(.headline)
                        TextField("Verification code", text: $form.code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .padding(16).background(Color.swBg, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline)).accessibilityIdentifier("restore-code")
                        PasswordControl(title: String(localized: "New password"), text: $form.password, newPassword: true, identifier: "restore-password", focus: $passwordFocused)
                        PasswordControl(title: String(localized: "Confirm password"), text: $form.confirmation, newPassword: true, identifier: "restore-confirm")
                        if let error = form.error { SWError(message: error) }
                        Button(form.busy ? "Restoring…" : "Restore account") { Task { await form.submit() } }
                            .buttonStyle(SWPrimary()).disabled(form.busy).accessibilityIdentifier("restore-submit")
                        Button("Change number") { form.changeNumber() }.frame(minHeight: 48).disabled(form.busy)
                    case .restored:
                        Label("Account restored", systemImage: "checkmark.circle").brandFont(.title2, weight: .bold)
                        Text("Sign in with your new password. Memberships, sessions and notifications stay off until your makerspace restores them.").foregroundStyle(Color.swMuted)
                        Button("Back to sign in") { dismiss() }.buttonStyle(SWPrimary()).accessibilityIdentifier("restore-done")
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(Color.swBg).scrollDismissesKeyboard(.interactively)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 48).disabled(form.busy) } }
        }.interactiveDismissDisabled(form.busy).onDisappear { form.password = ""; form.confirmation = "" }
    }
}
