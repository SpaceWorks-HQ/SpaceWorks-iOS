import SwiftUI
import SpaceWorksAPI

/// Whole-account deletion: server blockers with fixes, fresh identity proof, then a typed confirmation.
struct AccountDeletionView: View {
    @State private var state: AccountDeletionState
    let origin: ServerOrigin?
    let openFix: (@MainActor (MobileLink) -> Void)?
    let memberships: Set<Int>
    @State private var passwordFocused = false
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    init(state: AccountDeletionState, origin: ServerOrigin?, memberships: Set<Int>, openFix: (@MainActor (MobileLink) -> Void)?) {
        _state = State(initialValue: state); self.origin = origin; self.memberships = memberships; self.openFix = openFix
    }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("Delete account").brandFont(.largeTitle, weight: .bold).accessibilityAddTraits(.isHeader)
            Text("This deletes your whole account on this server, across every makerspace.").brandFont(.headline)
            Text("Your sessions, memberships and notifications end immediately. Payment, loan and audit history is kept anonymised under the retention policy. Leaving one makerspace is a separate action.")
                .foregroundStyle(Color.swMuted)
            if let notice = state.notice { Label(notice, systemImage: "info.circle").accessibilityIdentifier("deletion-notice") }
            if let error = state.error { SWError(message: error) }
            switch state.stage {
            case .overview:
                Button(state.busy ? "Checking…" : "Check account obligations") { Task { await state.load() } }
                    .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-check")
            case .blockers: blockers
            case .verify: verification
            case .factor: factor
            case .confirm: confirmation
            case .deleted: Label("Your account was deleted.", systemImage: "checkmark.circle").brandFont(.title2, weight: .bold)
            }
        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }
            .background(Color.swBg).foregroundStyle(Color.swInk).tint(Color.swAccentInk)
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("account-deletion")
            .onDisappear { state.password = ""; state.code = ""; state.confirmation = "" }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { fieldFocused = false; passwordFocused = false } } }
    }

    @ViewBuilder private var blockers: some View {
        Text("Resolve these first").brandFont(.title2, weight: .bold)
        ForEach(Array(state.blockers.enumerated()), id: \.offset) { _, blocker in
            SWCard {
                if let slug = blocker.makerspace_slug { Text(verbatim: slug).brandFont(.headline) }
                Text(blocker.detail)
                Text("\(blocker.count) outstanding").brandFont(.subheadline).foregroundStyle(Color.swMuted)
                if let id = blocker.makerspace_id, memberships.contains(id), let destination = AccountDeletionState.destination(for: blocker), let openFix {
                    Button("Open in the app") { openFix(MobileLink(makerspaceID: id, destination: destination)); dismiss() }
                        .frame(minHeight: 48).accessibilityIdentifier("deletion-fix-\(blocker.code)")
                }
                if let origin, let url = AccountDeletionState.trustedWebFix(blocker.organization_url ?? blocker.makerspace_member_url, origin: origin) {
                    Link("Open in the web console", destination: url).frame(minHeight: 48)
                }
            }.accessibilityElement(children: .contain)
        }
        Button(state.busy ? "Checking…" : "Check again") { Task { await state.load() } }
            .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-check")
    }

    @ViewBuilder private var verification: some View {
        Text("Confirm it's you").brandFont(.title2, weight: .bold)
        Text("Verify your identity to continue. This proof lasts ten minutes.").foregroundStyle(Color.swMuted)
        if state.methods.isEmpty {
            Text("This account has no verification method available in the app. Use the web console to delete it.").foregroundStyle(Color.swMuted)
        } else {
            if state.methods.count > 1 {
                Picker("Verification method", selection: $state.method) {
                    ForEach(state.methods) { method in Text(label(method)).tag(method) }
                }.frame(minHeight: 48).onChange(of: state.method) { _, _ in state.password = ""; state.code = "" }
            }
            switch state.method {
            case .password:
                PasswordControl(title: String(localized: "Current password"), text: $state.password, identifier: "deletion-password", focus: $passwordFocused)
                if state.authenticatorRequired { codeField(title: "Authenticator code") }
                Button(state.busy ? "Verifying…" : "Verify identity") { Task { await state.verifyPassword() } }
                    .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-verify")
            case .phone:
                if state.phoneToken == nil {
                    Button(state.busy ? "Sending…" : "Send verification code") { Task { await state.sendPhoneCode() } }
                        .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-phone-send")
                } else {
                    codeField(title: "Verification code")
                    Button(state.busy ? "Verifying…" : "Verify identity") { Task { await state.verifyPhone() } }
                        .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-verify")
                    Button("Send another code") { Task { await state.sendPhoneCode() } }.frame(minHeight: 48).disabled(state.busy)
                }
            case .social(let provider):
                Button(state.busy ? "Verifying…" : "Continue with \(label(.social(provider)))") { Task { await state.verifySocial(provider) } }
                    .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-social")
            }
        }
    }

    @ViewBuilder private var factor: some View {
        Text("One more step").brandFont(.title2, weight: .bold)
        Text(state.factorKind == .totp ? "Enter the six-digit code from your authenticator app." : "Enter the six-digit code we sent you.").foregroundStyle(Color.swMuted)
        codeField(title: "Verification code")
        Button(state.busy ? "Verifying…" : "Verify identity") { Task { await state.verifyFactor() } }
            .buttonStyle(SWPrimary()).disabled(state.busy).accessibilityIdentifier("deletion-factor")
    }

    @ViewBuilder private var confirmation: some View {
        Text("Confirm deletion").brandFont(.title2, weight: .bold)
        if state.preview?.restorable == true {
            Text("You can ask to restore your identity before the retention period ends. Memberships, roles, sessions and notifications stay revoked.").foregroundStyle(Color.swMuted)
        } else {
            Text("This account cannot be restored after deletion.").foregroundStyle(Color.swMuted)
        }
        if let reason = state.preview?.restore_reason, !reason.isEmpty { Text(reason).foregroundStyle(Color.swMuted) }
        Text("Type DELETE to confirm").brandFont(.headline)
        TextField("Type DELETE", text: $state.confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled().focused($fieldFocused)
            .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
            .accessibilityIdentifier("deletion-confirmation")
        Button(state.busy ? "Deleting…" : "Delete account", role: .destructive) { Task { await state.delete() } }
            .buttonStyle(SWPrimary()).disabled(!state.canDelete).accessibilityIdentifier("deletion-submit")
        Button("Verify again") { state.backToVerification() }.frame(minHeight: 48).disabled(state.busy)
    }

    private func codeField(title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).brandFont(.headline)
            TextField(title, text: $state.code).textContentType(.oneTimeCode).keyboardType(.numberPad).focused($fieldFocused)
                .padding(16).background(Color.swPanel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.swOutline))
                .accessibilityIdentifier("deletion-code")
        }
    }

    private func label(_ method: AccountDeletionState.Method) -> String {
        switch method {
        case .password: return String(localized: "Password")
        case .phone: return String(localized: "Phone code")
        case .social("google"): return "Google"
        case .social("apple"): return "Apple"
        case .social(let key): return NativeOIDCClient.slug(fromKey: key) ?? key
        }
    }
}
